import Flutter
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    window = UIWindow(windowScene: windowScene)

    let flutterEngine = FlutterEngine(name: "main")
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    let flutterViewController = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    window?.rootViewController = flutterViewController
    window?.makeKeyAndVisible()
  }
}
