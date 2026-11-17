import UIKit
import Flutter
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let channel = FlutterMethodChannel(
        name: "ios-delegate-channel",
        binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "isReduceMotionEnabled" {
          result(UIAccessibility.isReduceMotionEnabled)
        } else {
          result(FlutterMethodNotImplemented)
        }
    }
    let nearbyWifiChannel = FlutterMethodChannel(
        name: "org.glideapp.glide/nearby_wifi",
        binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    nearbyWifiChannel.setMethodCallHandler(nearbyWifi.handle)
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private let nearbyWifi = NearbyWifi()
}

/// The temporary Wi-Fi network of a Nearby transfer (see nearby_service.dart).
///
/// iOS cannot create a network another device could join, but it can join the
/// Wi-Fi Direct group of an Android device, which acts as a regular WPA2
/// access point for devices that do not speak Wi-Fi Direct. The system asks the
/// user to confirm the first time.
final class NearbyWifi {
  private var joinedSsid: String?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capabilities":
      result(["canHost": false, "canJoin": true])
    case "join":
      guard let args = call.arguments as? [String: Any],
            let ssid = args["ssid"] as? String,
            let passphrase = args["passphrase"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing ssid or passphrase", details: nil))
        return
      }
      join(ssid: ssid, passphrase: passphrase, result: result)
    case "leave":
      leave()
      result(nil)
    case "startHosting":
      result(FlutterError(code: "UNSUPPORTED", message: "iOS cannot host a Wi-Fi network", details: nil))
    case "stopHosting":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func join(ssid: String, passphrase: String, result: @escaping FlutterResult) {
    let configuration = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
    // Only while Glide is in use; it is removed again by leave() anyway.
    configuration.joinOnce = true
    NEHotspotConfigurationManager.shared.apply(configuration) { error in
      DispatchQueue.main.async {
        if let error = error as NSError?,
           !(error.domain == NEHotspotConfigurationErrorDomain
             && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue) {
          let message = error.code == NEHotspotConfigurationError.userDenied.rawValue
            ? "Joining the direct Wi-Fi network was declined"
            : error.localizedDescription
          result(FlutterError(code: "JOIN_FAILED", message: message, details: nil))
          return
        }
        self.joinedSsid = ssid
        result(nil)
      }
    }
  }

  /// Forgets the temporary network, after which iOS returns to the previous one.
  private func leave() {
    if let ssid = joinedSsid {
      NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
      joinedSsid = nil
    }
  }
}
