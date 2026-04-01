import Flutter
import UIKit
import app_links

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var flutterEngine: FlutterEngine?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    window = UIWindow(windowScene: windowScene)

    let flutterEngine = FlutterEngine(name: "main")
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)
    self.flutterEngine = flutterEngine

    let flutterViewController = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    window?.rootViewController = flutterViewController
    window?.makeKeyAndVisible()

    if let url = connectionOptions.urlContexts.first?.url {
      AppLinks.shared.handleLink(url: url)
    } else if let url = connectionOptions.userActivities.first?.webpageURL {
      AppLinks.shared.handleLink(url: url)
    }
  }

  func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    guard let url = urlContexts.first?.url else { return }
    AppLinks.shared.handleLink(url: url)
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    guard let url = userActivity.webpageURL else { return }
    AppLinks.shared.handleLink(url: url)
  }
}
