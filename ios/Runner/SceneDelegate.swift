import Flutter
import UIKit
import app_links

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts where context.url.scheme == "fitquest-auth" {
      AppLinks.shared.handleLink(url: context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for context in URLContexts where context.url.scheme == "fitquest-auth" {
      AppLinks.shared.handleLink(url: context.url)
    }
  }
}
