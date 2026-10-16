import UIKit
import WebKit
import AuthenticationServices
import CryptoKit
import Security

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class NativeAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private weak var presenter: UIViewController?
    private var browser: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var task: Task<Void, Never>?
    private let origin = URL(string: "https://ozyy.xyz")!
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    private struct Start: Decodable { let id: String; let verificationUrl: URL; let expiresAt: Double }
    private enum SignInError: LocalizedError {
        case invalid, unavailable
        var errorDescription: String? {
            switch self {
            case .invalid: return "This connection expired or could not be verified. Start sign-in again."
            case .unavailable: return "Ozyy could not connect. Check your connection and try again."
            }
        }
    }

    func signIn(from controller: UIViewController, completion: @escaping () -> Void) {
        guard task == nil else { return }
        presenter = controller
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil; self.browser = nil }
            do {
                var random = [UInt8](repeating: 0, count: 32)
                guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw SignInError.invalid }
                let verifier = Self.base64(Data(random))
                let challenge = Self.base64(Data(SHA256.hash(data: Data(verifier.utf8))))
                let (data, _) = try await self.post("/api/native/start", body: ["challenge": challenge])
                let start = try JSONDecoder().decode(Start.self, from: data)
                guard UUID(uuidString: start.id) != nil,
                      start.verificationUrl.scheme == "https", start.verificationUrl.host == self.origin.host,
                      start.verificationUrl.port == nil, start.verificationUrl.user == nil,
                      start.verificationUrl.path == "/native/sign-in",
                      start.expiresAt > Date().timeIntervalSince1970 * 1000 else { throw SignInError.invalid }
                let callback = try await self.authenticate(start.verificationUrl)
                let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false)
                let values = parts?.queryItems?.filter { $0.name == "request" } ?? []
                guard callback.scheme == "ozyy", callback.host == "auth-complete",
                      values.count == 1, values[0].value == start.id else { throw SignInError.invalid }
                let (_, response) = try await self.post("/api/native/exchange", body: ["id": start.id, "verifier": verifier])
                let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
                    if let key = item.key as? String, let value = item.value as? String { result[key] = value }
                }
                let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: self.origin)
                guard let cookie = cookies.first(where: {
                    $0.name == "ozyy_session" && $0.isSecure && $0.isHTTPOnly &&
                    $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == "ozyy.xyz" && $0.path == "/"
                }) else { throw SignInError.invalid }
                // HttpOnly remains HttpOnly. No access token or cookie is injected into JavaScript.
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) { done.resume() }
                }
                completion()
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // Cancelling the system browser leaves the workspace unchanged.
            } catch {
                guard let controller = self.presenter else { return }
                let alert = UIAlertController(title: "Couldn’t sign in", message: (error as? SignInError)?.localizedDescription ?? SignInError.unavailable.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                controller.present(alert, animated: true)
            }
        }
    }

    private func post(_ path: String, body: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: path, relativeTo: origin)!.absoluteURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("OzyyNative/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, result) = try await session.data(for: request)
        guard let response = result as? HTTPURLResponse,
              response.url?.scheme == "https", response.url?.host == origin.host,
              response.statusCode == 200 else { throw SignInError.invalid }
        return (data, response)
    }

    private func authenticate(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { pending in
            continuation = pending
            let browser = ASWebAuthenticationSession(url: url, callbackURLScheme: "ozyy") { [weak self] callback, error in
                Task { @MainActor in
                    guard let self, let pending = self.continuation else { return }
                    self.continuation = nil
                    if let error { pending.resume(throwing: error) }
                    else if let callback { pending.resume(returning: callback) }
                    else { pending.resume(throwing: SignInError.invalid) }
                }
            }
            browser.presentationContextProvider = self
            browser.prefersEphemeralWebBrowserSession = false
            self.browser = browser
            if !browser.start(), let pending = continuation {
                continuation = nil
                pending.resume(throwing: SignInError.unavailable)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presenter?.view.window ?? ASPresentationAnchor()
    }
    private static func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
