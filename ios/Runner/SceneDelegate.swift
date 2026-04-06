import Flutter
import StoreKit
import UIKit
import app_links

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var flutterEngine: FlutterEngine?
  private var subscriptionManagementChannel: FlutterMethodChannel?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    window = UIWindow(windowScene: windowScene)

    let flutterEngine = FlutterEngine(name: "main")
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)
    self.flutterEngine = flutterEngine

    let flutterViewController = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    configureSubscriptionManagementChannel(
      for: flutterViewController,
      windowScene: windowScene
    )
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

  private func configureSubscriptionManagementChannel(
    for flutterViewController: FlutterViewController,
    windowScene: UIWindowScene
  ) {
    let channel = FlutterMethodChannel(
      name: "vibesync/subscription_management",
      binaryMessenger: flutterViewController.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "showManageSubscriptions" else {
        result(FlutterMethodNotImplemented)
        return
      }

      self?.showManageSubscriptions(in: windowScene, result: result)
    }

    subscriptionManagementChannel = channel
  }

  private func showManageSubscriptions(
    in windowScene: UIWindowScene,
    result: @escaping FlutterResult
  ) {
    if #available(iOS 15.0, *) {
      Task { @MainActor in
        do {
          try await AppStore.showManageSubscriptions(in: windowScene)
          result(true)
        } catch {
          result(
            FlutterError(
              code: "manage_subscriptions_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    } else {
      result(false)
    }
  }
}
