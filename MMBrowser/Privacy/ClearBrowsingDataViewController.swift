import UIKit
import WebKit
import SnapKit

final class ClearBrowsingDataViewController: UIViewController {
    private let historySwitch = UISwitch()
    private let cookiesSwitch = UISwitch()
    private let localStorageSwitch = UISwitch()
    private let cacheSwitch = UISwitch()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Clear Data"
        BrowserTheme.applyScreenChrome(to: self)
        [historySwitch, cookiesSwitch, localStorageSwitch, cacheSwitch].forEach { $0.isOn = true }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(24)
            make.leading.trailing.equalToSuperview().inset(20)
        }

        stack.addArrangedSubview(row("Browsing History", historySwitch))
        stack.addArrangedSubview(row("Cookies", cookiesSwitch))
        stack.addArrangedSubview(row("Local Storage", localStorageSwitch))
        stack.addArrangedSubview(row("Cached Files", cacheSwitch))

        let button = UIButton(type: .system)
        button.setTitle("Clear Selected Data", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemRed
        button.layer.cornerRadius = 12
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        view.addSubview(button)
        button.snp.makeConstraints { make in
            make.top.equalTo(stack.snp.bottom).offset(32)
            make.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(50)
        }
    }

    private func row(_ title: String, _ sw: UISwitch) -> UIView {
        let box = UIView()
        box.backgroundColor = BrowserTheme.card
        box.layer.cornerRadius = 12
        let label = UILabel()
        label.text = title
        label.textColor = BrowserTheme.textPrimary
        box.addSubview(label)
        box.addSubview(sw)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
        }
        sw.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
        }
        box.snp.makeConstraints { $0.height.equalTo(52) }
        return box
    }

    @objc private func clearTapped() {
        if historySwitch.isOn { HistoryStore.shared.clear() }
        var types = Set<String>()
        if cookiesSwitch.isOn {
            types.insert(WKWebsiteDataTypeCookies)
        }
        if localStorageSwitch.isOn {
            types.formUnion([
                WKWebsiteDataTypeLocalStorage,
                WKWebsiteDataTypeSessionStorage,
                WKWebsiteDataTypeIndexedDBDatabases,
                WKWebsiteDataTypeWebSQLDatabases
            ])
        }
        if cacheSwitch.isOn {
            types.formUnion([WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache])
        }
        let finish = { [weak self] in
            guard let self = self else { return }
            Toast.show("Browsing data cleared", from: self)
            self.navigationController?.popViewController(animated: true)
        }
        if types.isEmpty {
            finish()
            return
        }
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {
                DispatchQueue.main.async(execute: finish)
            }
        }
    }
}
