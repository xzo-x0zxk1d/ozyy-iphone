import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Ozyy", sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let auth = NativeAuth()
    private var workspaces: [WorkspaceController] = []
    private var privacyCover: UIView?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // Temporary shared exports are scoped to this app and are removed on next launch too.
        let files = FileManager.default
        if let children = try? files.contentsOfDirectory(at: files.temporaryDirectory, includingPropertiesForKeys: nil) {
            for child in children where child.lastPathComponent.hasPrefix("Ozyy-") { try? files.removeItem(at: child) }
        }
        let tabs = UITabBarController()
        let reload: () -> Void = { [weak self] in self?.workspaces.forEach { $0.loadWorkspace() } }
        workspaces = [
            WorkspaceController(path: "/chat", title: "Chat", symbol: "bubble.left.and.bubble.right", auth: auth, signedIn: reload),
            WorkspaceController(path: "/projects", title: "Projects", symbol: "square.stack.3d.up", auth: auth, signedIn: reload),
            WorkspaceController(path: "/models", title: "Models", symbol: "sparkles", auth: auth, signedIn: reload),
        ]
        tabs.viewControllers = workspaces
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(white: 0.03, alpha: 1)
        appearance.stackedLayoutAppearance.selected.iconColor = .white
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.stackedLayoutAppearance.normal.iconColor = .systemGray
        tabs.tabBar.standardAppearance = appearance
        tabs.tabBar.scrollEdgeAppearance = appearance
        tabs.tabBar.tintColor = .white
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
    }
    func sceneWillResignActive(_ scene: UIScene) {
        guard let window, privacyCover == nil else { return }
        let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        cover.frame = window.bounds; cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let label = UILabel(); label.text = "ozyy ✳"; label.font = .systemFont(ofSize: 32, weight: .medium); label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        cover.contentView.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: cover.centerXAnchor), label.centerYAnchor.constraint(equalTo: cover.centerYAnchor)])
        window.addSubview(cover); privacyCover = cover
    }
    func sceneDidBecomeActive(_ scene: UIScene) { privacyCover?.removeFromSuperview(); privacyCover = nil }
}
