import UIKit
import WebKit

final class WebViewController: UIViewController, WKUIDelegate, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private let bridge = NativeBridge()
    private let legacy = LegacyHandler()
    private let keyboardPin = KeyboardPin()

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        SchemeHandler.cleanOutDir()

        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.setURLSchemeHandler(SchemeHandler(), forURLScheme: "lucida")
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true

        let ucc = cfg.userContentController
        ucc.addScriptMessageHandler(bridge, contentWorld: .page, name: "lucida")
        ucc.add(legacy, name: "lucidaLive")
        ucc.add(legacy, name: "lucidaLG")
        ucc.add(legacy, name: "lucidaSkin")
        let probe = DeviceProbe.json()
        ucc.addUserScript(WKUserScript(source: "window.__LUCIDA_NATIVE__=\(probe);",
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let wv = WKWebView(frame: view.bounds, configuration: cfg)
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wv.uiDelegate = self
        wv.navigationDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.contentInsetAdjustmentBehavior = .never   // 安全区交给网页的 env(safe-area-inset-*)
        wv.scrollView.bounces = false
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.showsHorizontalScrollIndicator = false
        wv.scrollView.showsVerticalScrollIndicator = false
        wv.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        view.addSubview(wv)
        webView = wv

        bridge.host = self
        legacy.host = self

        // 键盘弹出时页面原地不动（登录验证码条不被顶出屏幕）；键盘遮住多少告诉网页，由网页只抬输入框那一行
        keyboardPin.attach(to: wv)
        keyboardPin.onHeight = { [weak self] h, _ in
            self?.js("window.__lucidaKb&&window.__lucidaKb(\(Int(h.rounded())))")
        }

        wv.load(URLRequest(url: URL(string: "lucida://app/index.html")!))
    }

    // MARK: - 相机 / 麦克风 / 动作与方向 权限：App 已有系统授权，网页内直接放行
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    // MARK: - JS 弹窗
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        present(a, animated: true)
    }

    // MARK: - 外部链接用系统打开，页面本身只在 lucida:// 内
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let s = url.scheme?.lowercased() ?? ""
        if ["lucida", "about", "blob", "data"].contains(s) { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
            UIApplication.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme?.lowercased() != "lucida" {
            UIApplication.shared.open(url)
        }
        return nil
    }

    // 网页进程被系统回收（内存紧张）时自动重新加载
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.load(URLRequest(url: URL(string: "lucida://app/index.html")!))
    }

    // 回调网页：evaluateJavaScript 的封装
    func js(_ code: String) {
        DispatchQueue.main.async { [weak self] in self?.webView?.evaluateJavaScript(code, completionHandler: nil) }
    }
}

/// 普通（无回复）消息：lucidaLive（实况写入）/ lucidaLG（液态玻璃状态）/ lucidaSkin（皮肤）。
/// 这三个名字是网页早就约定好的接口，这里照约定实现。
final class LegacyHandler: NSObject, WKScriptMessageHandler {
    weak var host: WebViewController?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "lucidaLive":
            guard let body = message.body as? [String: Any] else { return }
            LivePhotoSaver.saveFromWeb(body) { [weak host] ok, msg in
                let m = (msg ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                host?.js("window.lucidaLiveResult&&window.lucidaLiveResult(\(ok ? "true" : "false"),'\(m)')")
            }
        default:
            break   // lucidaLG（主题状态）/ lucidaSkin：原生液态玻璃叠层已整体去掉，这两个消息目前原生侧不处理
        }
    }
}
