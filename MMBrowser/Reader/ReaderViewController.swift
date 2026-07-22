import UIKit
import WebKit
import SnapKit

final class ReaderViewController: UIViewController {
    private let webView = WKWebView()
    private let titleText: String
    private let htmlBody: String
    private var fontSize: CGFloat = 18
    private var themeIndex = 2 // dark default

    init(title: String, bodyHTML: String) {
        self.titleText = title
        self.htmlBody = bodyHTML
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Reader"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "textformat.size"), style: .plain, target: self, action: #selector(cycleFont)),
            UIBarButtonItem(image: UIImage(systemName: "circle.lefthalf.fill"), style: .plain, target: self, action: #selector(cycleTheme))
        ]
        view.addSubview(webView)
        webView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        reloadContent()
    }

    private func reloadContent() {
        let themes = [
            ("#111", "#eee", "#222"),
            ("#f5f1e6", "#222", "#ebe5d6"),
            ("#000", "#ddd", "#111")
        ]
        let t = themes[themeIndex % themes.count]
        let html = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body{font-family:-apple-system;background:\(t.0);color:\(t.1);padding:20px;line-height:1.65;font-size:\(Int(fontSize))px;}
        h1{font-size:1.6em;} img{max-width:100%;height:auto;} a{color:#8ab4f8;}
        article{max-width:720px;margin:0 auto;background:\(t.2);padding:16px;border-radius:12px;}
        </style></head><body><article><h1>\(titleText)</h1>\(htmlBody)</article></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    @objc private func cycleFont() { fontSize = fontSize >= 24 ? 16 : fontSize + 2; reloadContent() }
    @objc private func cycleTheme() { themeIndex += 1; reloadContent() }
    @objc private func close() { dismiss(animated: true) }
}

enum ReaderExtractor {
    static let script = """
    (function(){
      function text(el){return el ? (el.innerText||'').trim() : '';}
      var article = document.querySelector('article') || document.querySelector('[role=main]') || document.querySelector('main') || document.body;
      var title = text(document.querySelector('h1')) || document.title || '';
      var clone = article.cloneNode(true);
      clone.querySelectorAll('script,style,nav,footer,iframe,ins.adsbygoogle,.adsbygoogle').forEach(function(n){n.remove();});
      var html = clone.innerHTML || '';
      if ((clone.innerText||'').trim().length < 80) {
        return JSON.stringify({ok:false, title:title, html:''});
      }
      return JSON.stringify({ok:true, title:title, html:html});
    })();
    """
}
