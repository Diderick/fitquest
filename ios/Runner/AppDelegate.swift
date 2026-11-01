import Flutter
import UIKit
import CoreMotion

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let pedometer = CMPedometer()
  private var stepChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FitQuestSteps") else { return }
    let channel = FlutterMethodChannel(name: "fitquest/steps", binaryMessenger: registrar.messenger())
    stepChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "disable" {
        UserDefaults.standard.set(false, forKey: "fitquest_steps_enabled")
        self.pedometer.stopUpdates()
        result(nil)
        return
      }
      guard call.method == "read" || call.method == "enable" else { result(FlutterMethodNotImplemented); return }
      guard CMPedometer.isStepCountingAvailable() else {
        result(FlutterError(code: "unavailable", message: "Step counting is unavailable on this device.", details: nil)); return
      }
      let enabled = UserDefaults.standard.bool(forKey: "fitquest_steps_enabled") || call.method == "enable"
      guard enabled else {
        result(["steps": 0, "enabled": false, "status": "Enable motion permission to count steps"]); return
      }
      let start = Calendar.current.startOfDay(for: Date())
      self.pedometer.queryPedometerData(from: start, to: Date()) { data, error in
        DispatchQueue.main.async {
          if error != nil {
            result(FlutterError(code: "permission", message: "Allow Motion & Fitness access in Settings to count steps.", details: nil)); return
          }
          UserDefaults.standard.set(true, forKey: "fitquest_steps_enabled")
          if call.method == "enable" { result(nil) }
          else { result(["steps": data?.numberOfSteps.intValue ?? 0, "enabled": true, "status": "Today’s steps from Apple motion sensor"]) }
        }
      }
    }
  }
}
