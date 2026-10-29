import UIKit
import WebKit

private enum RoomSite {
    static let homeURL = URL(string: "http://43.129.180.6:3210/?online=1")!

    static func allows(_ url: URL?) -> Bool {
        guard let url = url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme?.lowercased() == "http"
            && components.host == "43.129.180.6"
            && components.port == 3210
            && components.user == nil
            && components.password == nil
    }
}

final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let webView: WKWebView
    private let isPopup: Bool
    private var retryURL: URL
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let failureOverlay = UIView()
    private let failureMessage = UILabel()

    convenience init() {
        self.init(initialURL: RoomSite.homeURL, configuration: WKWebViewConfiguration(), isPopup: false)
    }

    private init(initialURL: URL, configuration: WKWebViewConfiguration, isPopup: Bool) {
        self.isPopup = isPopup
        retryURL = initialURL
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        if !isPopup {
            configuration.websiteDataStore = .default()
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        failureOverlay.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("This view controller is created without a storyboard.")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        [.landscapeLeft, .landscapeRight]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.15, blue: 0.13, alpha: 1)
        if isPopup {
            title = "音频库"
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "关闭", style: .done, target: self, action: #selector(closePopup)
            )
        }

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(webView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        failureOverlay.translatesAutoresizingMaskIntoConstraints = false
        failureOverlay.backgroundColor = view.backgroundColor
        view.addSubview(failureOverlay)

        let heading = UILabel()
        heading.text = "页面暂时无法打开"
        heading.font = .preferredFont(forTextStyle: .headline)
        heading.textColor = .white
        heading.textAlignment = .center
        heading.numberOfLines = 0
        failureMessage.font = .preferredFont(forTextStyle: .body)
        failureMessage.textColor = .white
        failureMessage.textAlignment = .center
        failureMessage.numberOfLines = 0

        let retryButton = UIButton(type: .system)
        retryButton.setTitle("重新加载", for: .normal)
        retryButton.tintColor = .white
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retryButton.addTarget(self, action: #selector(retryLoading), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [heading, failureMessage, retryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        failureOverlay.addSubview(stack)

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            webView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor),
            failureOverlay.topAnchor.constraint(equalTo: safeArea.topAnchor),
            failureOverlay.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            failureOverlay.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            failureOverlay.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: failureOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: failureOverlay.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: failureOverlay.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: failureOverlay.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        // Never reload on appearance/background transitions or clear website data.
        // UIKit/WebKit retain their standard keyboard and text-input behavior.
        if !isPopup {
            retryLoading()
        }
    }

    @objc private func retryLoading() {
        guard RoomSite.allows(retryURL) else { return }
        failureOverlay.isHidden = true
        activityIndicator.startAnimating()
        webView.load(URLRequest(url: retryURL))
    }

    @objc private func closePopup() {
        guard isPopup else { return }
        navigationController?.dismiss(animated: true)
    }

    private func showFailure(_ message: String) {
        activityIndicator.stopAnimating()
        failureMessage.text = message
        failureOverlay.isHidden = false
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        // A nil target frame is a new window, not permission to replace the table.
        let isTopLevel = navigationAction.targetFrame?.isMainFrame ?? true
        if isTopLevel {
            guard RoomSite.allows(url) else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame?.isMainFrame == true, let url = url {
                retryURL = url
            }
        } else {
            // Subframes may use web resources, but never launch external schemes.
            let scheme = url?.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" else {
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        // Subresource/iframe failures must not replace the table with an error UI.
        guard navigationResponse.isForMainFrame else {
            decisionHandler(.allow)
            return
        }
        guard RoomSite.allows(navigationResponse.response.url) else {
            decisionHandler(.cancel)
            showFailure("已阻止跳转到非游戏地址。")
            return
        }
        if let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode >= 400 {
            decisionHandler(.cancel)
            showFailure("服务器暂时无法提供此页面（HTTP \(response.statusCode)），请重试。")
            return
        }
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.cancel)
            showFailure("此页面格式无法在客户端中显示。")
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        failureOverlay.isHidden = true
        activityIndicator.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
        failureOverlay.isHidden = true
    }

    // These navigation callbacks describe main-page failures, not failed images/audio.
    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    private func handleNavigationFailure(_ error: Error) {
        let error = error as NSError
        // Cancellation also occurs for denied URLs, popups, and superseded loads.
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            return
        }
        if error.domain == "WebKitErrorDomain" && error.code == 102 {
            return // Frame load interrupted by a navigation policy decision.
        }
        showFailure("请检查网络连接，然后点击重新加载。")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showFailure("页面进程已结束，请点击重新加载。")
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url,
              RoomSite.allows(url),
              presentedViewController == nil else {
            return nil
        }
        let popup = WebViewController(initialURL: url, configuration: configuration, isPopup: true)
        let navigationController = UINavigationController(rootViewController: popup)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
        // WebKit loads the original request itself; do not load it a second time.
        return popup.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        closePopup()
    }
}
