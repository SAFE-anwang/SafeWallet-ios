
import UIKit
import WebKit
import ThemeKit
import SnapKit

class MarketDappLinkViewController: ThemeViewController {
    
    private let estimatedProgressKeyPath = "estimatedProgress"

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .clear
        webView.isOpaque = false
//        webView.navigationDelegate = self;
        return webView
    }()
    
    private lazy var textInput: UITextField = {
        let textInput = UITextField(frame: CGRect(x: 10, y: 0, width: UIScreen.main.bounds.width - 117, height: 40))
        textInput.placeholder = "safe_dapp.input".localized
        textInput.font = UIFont.systemFont(ofSize: 16)
        textInput.clearButtonMode = .always
        textInput.returnKeyType = .search
        textInput.delegate = self
        return textInput
    }()

    
    override init() {
        super.init()
        navigationItem.largeTitleDisplayMode = .never
        hidesBottomBarWhenPushed = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let searchView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width - 88, height: 40))
        searchView.backgroundColor = .white
        searchView.layer.borderColor = UIColor.white.cgColor
        searchView.layer.cornerRadius = 8
        searchView.layer.borderWidth = 1
        searchView.clipsToBounds = true
        searchView.addSubview(textInput)
        navigationItem.titleView = searchView
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "search_discovery_24"), style: .plain, target: self, action: #selector(reloadSearch(_ :)))
        
        view.addSubview(webView)
        webView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    

    deinit {
        guard let _ = webView.observationInfo else { return }
        webView.removeObserver(self, forKeyPath: estimatedProgressKeyPath, context: nil)
    }
    
    @objc
    private func reloadSearch(_ sender: UIBarButtonItem) {
        loadWeb(url: textInput.text ?? "")
    }
    
    private func loadWeb(url: String) {
        guard let _url = URL(string: url) else { return }
        let request = URLRequest(url: _url)
        webView.load(request)
    }
}

extension MarketDappLinkViewController: UITextFieldDelegate {
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        loadWeb(url: textInput.text ?? "")
        textField.resignFirstResponder()
        return true
    }
}
