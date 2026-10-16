import UIKit
import WebKit
import SafariServices

@MainActor
private final class SignInBridge: NSObject, WKScriptMessageHandler {
    weak var owner: WorkspaceController?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "ozyy.xyz",
              [0, 443].contains(message.frameInfo.securityOrigin.port),
              message.body as? String == "signIn" else { return }
        owner?.requestSignIn()
    }
}

@MainActor
final class WorkspaceController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private let path: String
    private let auth: NativeAuth
    private let signedIn: () -> Void
    private var browser: WKWebView!
    private let loading = UIActivityIndicatorView(style: .medium)
    private var downloads: [ObjectIdentifier: (WKDownload, URL?)] = [:]
    private var didLoadPage = false

    init(path: String, title: String, symbol: String, auth: NativeAuth, signedIn: @escaping () -> Void) {
        self.path = path; self.auth = auth; self.signedIn = signedIn
        super.init(nibName: nil, bundle: nil)
        tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), tag: 0)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic app") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.03, alpha: 1)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "OzyyNative/1.0"
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let bridge = SignInBridge(); bridge.owner = self
        config.userContentController.add(bridge, name: "ozyyNative")
        // Next.js links navigate without a document request. Capture only trusted sign-in links.
        let signInLinks = """
        document.addEventListener('click',function(event){
          var target=event.target instanceof Element?event.target.closest('a[href]'):null;
          if(!target)return;
          var url=new URL(target.href,location.href);
          if(url.origin==='https://ozyy.xyz'&&(url.pathname==='/login'||url.pathname.startsWith('/auth/'))){
            event.preventDefault();event.stopImmediatePropagation();
            window.webkit.messageHandlers.ozyyNative.postMessage('signIn');
          }
        },true);
        """
        config.userContentController.addUserScript(WKUserScript(source: signInLinks, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        browser = WKWebView(frame: .zero, configuration: config)
        browser.navigationDelegate = self; browser.uiDelegate = self
        browser.isOpaque = false
        browser.backgroundColor = view.backgroundColor
        browser.scrollView.backgroundColor = view.backgroundColor
        browser.scrollView.contentInsetAdjustmentBehavior = .never
        browser.allowsBackForwardNavigationGestures = true
        browser.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(browser)
        NSLayoutConstraint.activate([
            browser.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            browser.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            browser.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browser.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        loading.color = .white; loading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loading)
        NSLayoutConstraint.activate([loading.centerXAnchor.constraint(equalTo: view.centerXAnchor), loading.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        loadWorkspace()
    }

    func loadWorkspace() {
        guard isViewLoaded else { return }
        loading.startAnimating()
        browser.load(URLRequest(url: URL(string: "https://ozyy.xyz\(path)")!))
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { didLoadPage = true; loading.stopAnimating() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading.stopAnimating()
        guard !didLoadPage, (error as NSError).code != NSURLErrorCancelled else { return }
        let alert = UIAlertController(title: "A moment to reconnect", message: "Check your connection and open Ozyy again. Your saved workspace stays in your account.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Try again", style: .default) { [weak self] _ in self?.loadWorkspace() })
        alert.addAction(UIAlertAction(title: "Later", style: .cancel))
        present(alert, animated: true)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { didLoadPage = false; loadWorkspace() }
    fileprivate func requestSignIn() { auth.signIn(from: self, completion: signedIn) }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "about", url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        if action.targetFrame?.isMainFrame == false,
           url.absoluteString == "about:srcdoc" || url.absoluteString.hasPrefix("blob:https://ozyy.xyz/") { decisionHandler(.allow); return }
        if url.scheme == "blob", url.absoluteString.hasPrefix("blob:https://ozyy.xyz/"), action.shouldPerformDownload {
            decisionHandler(.download); return
        }
        guard url.scheme == "https", url.user == nil, url.password == nil else { decisionHandler(.cancel); return }
        if url.host == "ozyy.xyz", url.port == nil || url.port == 443 {
            if url.path == "/login" || url.path.hasPrefix("/auth/") {
                decisionHandler(.cancel)
                requestSignIn()
            } else { decisionHandler(action.shouldPerformDownload ? .download : .allow) }
        } else {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame != false {
                present(SFSafariViewController(url: url), animated: true)
            }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let attachment = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased().contains("attachment") == true
        decisionHandler(attachment || !response.canShowMIMEType ? .download : .allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard action.targetFrame == nil, action.navigationType == .linkActivated,
              let url = action.request.url, url.scheme == "https" else { return nil }
        if url.host == "ozyy.xyz" { webView.load(action.request) }
        else { present(SFSafariViewController(url: url), animated: true) }
        return nil
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { retain(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { retain(download) }
    private func retain(_ download: WKDownload) { downloads[ObjectIdentifier(download)] = (download, nil); download.delegate = self }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard response.expectedContentLength <= 32 * 1024 * 1024 else { completionHandler(nil); return }
        let name = String((suggestedFilename as NSString).lastPathComponent.prefix(120))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Ozyy-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            let target = directory.appendingPathComponent(name.isEmpty || name == "." || name == ".." ? "Ozyy-download" : name)
            downloads[ObjectIdentifier(download)] = (download, target)
            completionHandler(target)
        } catch { completionHandler(nil) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let (_, target) = downloads.removeValue(forKey: ObjectIdentifier(download)), let target else { return }
        let size = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= 32 * 1024 * 1024 else { try? FileManager.default.removeItem(at: target.deletingLastPathComponent()); return }
        let sheet = UIActivityViewController(activityItems: [target], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: target.deletingLastPathComponent()) }
        present(sheet, animated: true)
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let (_, target) = downloads.removeValue(forKey: ObjectIdentifier(download)), let target { try? FileManager.default.removeItem(at: target.deletingLastPathComponent()) }
    }
}
