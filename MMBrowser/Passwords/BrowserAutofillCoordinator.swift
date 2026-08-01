import UIKit
import WebKit

/// Bridges WKWebView form events to the password / form / card vault.
final class BrowserAutofillCoordinator: NSObject, WKScriptMessageHandler {
    static let messageName = "mmAutofill"

    weak var hostViewController: UIViewController?
    private weak var webView: WKWebView?
    private var isIncognito = false
    private var lastSavePromptKey: String?

    static var userScript: WKUserScript {
        WKUserScript(source: Self.scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    func attach(to webView: WKWebView, isIncognito: Bool, contentController: WKUserContentController) {
        self.webView = webView
        self.isIncognito = isIncognito
        contentController.removeScriptMessageHandler(forName: Self.messageName)
        contentController.add(self, name: Self.messageName)
    }

    func detach(contentController: WKUserContentController) {
        contentController.removeScriptMessageHandler(forName: Self.messageName)
        webView = nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageName,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else { return }

        DispatchQueue.main.async { [weak self] in
            self?.handle(type: type, body: body)
        }
    }

    private func handle(type: String, body: [String: Any]) {
        guard !isIncognito else { return }
        switch type {
        case "passwordFocus":
            offerPasswordFill()
        case "formFocus":
            offerFormFill()
        case "cardFocus":
            offerCardFill()
        case "passwordSubmit":
            maybePromptSave(body: body)
        default:
            break
        }
    }

    private func offerPasswordFill() {
        guard PasswordSettings.autofillPasswords,
              VaultCrypto.isMasterUnlocked,
              let host = webView?.url?.host
        else { return }
        let matches = PasswordStore.shared.items(forHost: host)
        guard let item = matches.first else { return }
        let user = Self.jsString(item.username)
        let pass = Self.jsString(item.password)
        let js = "window.__mmAutofill && window.__mmAutofill.fillPassword(\(user), \(pass));"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    private func offerFormFill() {
        guard PasswordSettings.autofillForms,
              VaultCrypto.isMasterUnlocked
        else { return }
        let p = FormProfileStore.shared.profile
        guard p.hasAnyValue else { return }
        let payload: [String: String] = [
            "fullName": p.fullName,
            "email": p.email,
            "phone": p.phone,
            "addressLine1": p.addressLine1,
            "addressLine2": p.addressLine2,
            "city": p.city,
            "state": p.state,
            "postalCode": p.postalCode,
            "country": p.country
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        webView?.evaluateJavaScript("window.__mmAutofill && window.__mmAutofill.fillForm(\(json));", completionHandler: nil)
    }

    private func offerCardFill() {
        guard PasswordSettings.autofillBankCards,
              VaultCrypto.isMasterUnlocked,
              let host = hostViewController,
              let card = BankCardStore.shared.all.first
        else { return }

        let alert = UIAlertController(
            title: "Fill Card Details?",
            message: "Use \(card.maskedNumber) on this page?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Fill", style: .default) { [weak self] _ in
            let number = Self.jsString(card.number)
            let name = Self.jsString(card.holderName)
            let exp = Self.jsString(String(format: "%02d/%02d", card.expiryMonth, card.expiryYear % 100))
            let cvv = Self.jsString(card.cvv)
            let js = "window.__mmAutofill && window.__mmAutofill.fillCard(\(number), \(name), \(exp), \(cvv));"
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        })
        host.present(alert, animated: true)
    }

    private func maybePromptSave(body: [String: Any]) {
        guard PasswordSettings.autoSavePasswords,
              VaultCrypto.isMasterUnlocked,
              let hostVC = hostViewController
        else { return }
        let username = (body["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = body["password"] as? String ?? ""
        guard !password.isEmpty else { return }
        let host = webView?.url?.host ?? ""
        let url = webView?.url?.absoluteString ?? host
        let key = "\(host)|\(username)|\(password)"
        if lastSavePromptKey == key { return }
        lastSavePromptKey = key

        if let existing = PasswordStore.shared.items(forHost: host).first(where: { $0.username == username && $0.password == password }) {
            _ = existing
            return
        }

        let title: String
        let message: String
        if let existing = PasswordStore.shared.items(forHost: host).first(where: { $0.username == username }) {
            title = "Update Password?"
            message = "Update saved password for \(existing.host)?"
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
            alert.addAction(UIAlertAction(title: "Update", style: .default) { _ in
                var item = existing
                item.password = password
                item.url = url
                _ = PasswordStore.shared.update(item)
                Toast.show("Password updated", from: hostVC)
            })
            hostVC.present(alert, animated: true)
            return
        }

        let alert = UIAlertController(title: "Save Password?", message: host.isEmpty ? url : host, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            _ = PasswordStore.shared.add(site: url, username: username, password: password)
            Toast.show("Password saved", from: hostVC)
        })
        hostVC.present(alert, animated: true)
    }

    private static func jsString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        return "'\(escaped)'"
    }

    private static let scriptSource = """
    (function() {
      if (window.__mmAutofill) return;
      function post(type, payload) {
        try {
          var body = payload || {};
          body.type = type;
          window.webkit.messageHandlers.mmAutofill.postMessage(body);
        } catch (e) {}
      }
      function looksLikeUser(el) {
        if (!el) return false;
        var t = (el.type || '').toLowerCase();
        var n = ((el.name || '') + ' ' + (el.id || '') + ' ' + (el.autocomplete || '') + ' ' + (el.placeholder || '')).toLowerCase();
        if (t === 'email' || t === 'tel') return true;
        return /user|login|email|phone|account|id/.test(n);
      }
      function findUsername(form, pwd) {
        var inputs = (form || document).querySelectorAll('input');
        var list = Array.prototype.slice.call(inputs);
        var idx = list.indexOf(pwd);
        for (var i = idx - 1; i >= 0; i--) {
          var el = list[i];
          if (el.type === 'password' || el.type === 'hidden') continue;
          if (looksLikeUser(el) || el.type === 'text') return el;
        }
        for (var j = 0; j < list.length; j++) {
          if (looksLikeUser(list[j])) return list[j];
        }
        return null;
      }
      function setValue(el, value) {
        if (!el || value == null || value === '') return;
        el.focus();
        el.value = value;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }
      function fillPassword(user, pass) {
        var pwds = document.querySelectorAll('input[type="password"]');
        if (!pwds.length) return;
        var pwd = pwds[0];
        var form = pwd.form;
        var userEl = findUsername(form, pwd);
        setValue(userEl, user);
        setValue(pwd, pass);
      }
      function fillForm(data) {
        var map = [
          ['fullName', /name|fullname|fullname-name|cc-name/i],
          ['email', /email|e-mail/i],
          ['phone', /phone|tel|mobile/i],
          ['addressLine1', /address-line1|address1|street/i],
          ['addressLine2', /address-line2|address2/i],
          ['city', /city|address-level2/i],
          ['state', /state|address-level1|province/i],
          ['postalCode', /postal|zip|postcode/i],
          ['country', /country/i]
        ];
        var inputs = document.querySelectorAll('input, textarea, select');
        for (var i = 0; i < inputs.length; i++) {
          var el = inputs[i];
          var key = ((el.name || '') + ' ' + (el.id || '') + ' ' + (el.autocomplete || '')).toLowerCase();
          for (var m = 0; m < map.length; m++) {
            if (map[m][1].test(key) && data[map[m][0]]) {
              setValue(el, data[map[m][0]]);
              break;
            }
          }
        }
      }
      function fillCard(number, name, exp, cvv) {
        var inputs = document.querySelectorAll('input');
        for (var i = 0; i < inputs.length; i++) {
          var el = inputs[i];
          var key = ((el.name || '') + ' ' + (el.id || '') + ' ' + (el.autocomplete || '')).toLowerCase();
          if (/cc-number|cardnumber|card-number|card_number/.test(key)) setValue(el, number);
          else if (/cc-name|cardholder|card-name|nameoncard/.test(key)) setValue(el, name);
          else if (/cc-exp|expir|exp-date/.test(key)) setValue(el, exp);
          else if (/cc-csc|cvc|cvv|security-code/.test(key)) setValue(el, cvv);
        }
      }
      function onFocus(e) {
        var t = e.target;
        if (!t || !t.tagName || t.tagName.toLowerCase() !== 'input') return;
        var type = (t.type || '').toLowerCase();
        var key = ((t.name || '') + ' ' + (t.id || '') + ' ' + (t.autocomplete || '')).toLowerCase();
        if (type === 'password') post('passwordFocus');
        else if (/cc-number|cardnumber|card-number|cc-exp|cc-csc|cvc|cvv/.test(key)) post('cardFocus');
        else if (/name|email|phone|tel|address|city|postal|zip|country/.test(key)) post('formFocus');
      }
      function onSubmit(e) {
        var form = e.target;
        if (!form || !form.querySelector) return;
        var pwd = form.querySelector('input[type="password"]');
        if (!pwd || !pwd.value) return;
        var userEl = findUsername(form, pwd);
        post('passwordSubmit', { username: userEl ? userEl.value : '', password: pwd.value });
      }
      document.addEventListener('focusin', onFocus, true);
      document.addEventListener('submit', onSubmit, true);
      window.__mmAutofill = { fillPassword: fillPassword, fillForm: fillForm, fillCard: fillCard };
    })();
    """
}
