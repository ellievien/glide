import Cocoa
import CoreLocation
import CoreWLAN
import FlutterMacOS
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let nearbyWifiChannel = FlutterMethodChannel(
      name: "org.glideapp.glide/nearby_wifi",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    nearbyWifiChannel.setMethodCallHandler(nearbyWifi.handle)

    super.awakeFromNib()
  }

  private let nearbyWifi = NearbyWifi()

  // window_manager: start hidden
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}

/// The temporary Wi-Fi network of a Nearby transfer (see nearby_service.dart).
///
/// macOS cannot create a network another device could join, but it can join
/// the Wi-Fi Direct group of an Android device, which acts as a regular WPA2
/// access point. Since macOS 14, Wi-Fi network names are only visible to apps
/// with Location access, so that is asked for the first time.
final class NearbyWifi: NSObject, CLLocationManagerDelegate {
  private let locationManager = CLLocationManager()
  private var authorizationWaiters: [(Bool) -> Void] = []
  private var joined = false

  override init() {
    super.init()
    locationManager.delegate = self
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capabilities":
      result(["canHost": false, "canJoin": CWWiFiClient.shared().interface() != nil])
    case "join":
      guard let args = call.arguments as? [String: Any],
            let ssid = args["ssid"] as? String,
            let passphrase = args["passphrase"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing ssid or passphrase", details: nil))
        return
      }
      ensureLocationAccess { granted in
        guard granted else {
          result(FlutterError(
            code: "LOCATION_DENIED",
            message: "Allow Location for Glide in System Settings > Privacy & Security to join a direct Wi-Fi network",
            details: nil))
          return
        }
        self.join(ssid: ssid, passphrase: passphrase, result: result)
      }
    case "leave":
      leave()
      result(nil)
    case "startHosting":
      result(FlutterError(code: "UNSUPPORTED", message: "macOS cannot host a Wi-Fi network", details: nil))
    case "stopHosting":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func join(ssid: String, passphrase: String, result: @escaping FlutterResult) {
    guard let interface = CWWiFiClient.shared().interface() else {
      result(FlutterError(code: "UNSUPPORTED", message: "No Wi-Fi interface", details: nil))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        // The group was created moments ago; give the scan a few tries.
        var network: CWNetwork?
        for attempt in 0..<5 {
          network = try interface.scanForNetworks(withName: ssid).first
          if network != nil { break }
          if attempt < 4 { Thread.sleep(forTimeInterval: 1) }
        }
        guard let target = network else {
          throw NSError(domain: "NearbyWifi", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network \(ssid) not found"])
        }
        try interface.associate(to: target, password: passphrase)
        DispatchQueue.main.async {
          self.joined = true
          result(nil)
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "JOIN_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  /// Leaves the temporary network; macOS then auto-joins the user's known networks.
  private func leave() {
    guard joined else { return }
    joined = false
    CWWiFiClient.shared().interface()?.disassociate()
  }

  private func ensureLocationAccess(_ completion: @escaping (Bool) -> Void) {
    switch locationManager.authorizationStatus {
    case .notDetermined:
      authorizationWaiters.append(completion)
      if authorizationWaiters.count == 1 {
        locationManager.requestWhenInUseAuthorization()
      }
    case .denied, .restricted:
      completion(false)
    default:
      completion(true)
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    guard status != .notDetermined else { return }
    let granted = status != .denied && status != .restricted
    let waiters = authorizationWaiters
    authorizationWaiters.removeAll()
    waiters.forEach { $0(granted) }
  }
}
