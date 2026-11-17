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
  private let peerToPeer = NearbyPeerToPeer()

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capabilities":
      result(["canHost": false, "canJoin": true, "peerToPeer": true])
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
    case "advertisePeerToPeer":
      guard let args = call.arguments as? [String: Any],
            let name = args["name"] as? String,
            let type = args["type"] as? String,
            let port = args["port"] as? Int else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing name, type or port", details: nil))
        return
      }
      peerToPeer.advertise(name: name, type: type, port: port, result: result)
    case "stopAdvertisingPeerToPeer":
      peerToPeer.stopAdvertising()
      result(nil)
    case "resolvePeerToPeer":
      guard let args = call.arguments as? [String: Any],
            let name = args["name"] as? String,
            let type = args["type"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing name or type", details: nil))
        return
      }
      peerToPeer.resolve(name: name, type: type, result: result)
    case "stopResolvingPeerToPeer":
      peerToPeer.stopResolving()
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

/// Apple peer-to-peer Wi-Fi (AWDL) between two Apple devices for Nearby
/// transfers (see nearby_service.dart), with no shared network at all.
///
/// The receiver advertises its HTTP server through Bonjour with peer-to-peer
/// enabled; the sender browses and resolves it the same way, which brings the
/// peer-to-peer link up, and dials the receiver's link-local IPv6 address on
/// that link. The Rust server accepts it because its IPv6 listener sets
/// SO_RECV_ANYIF. The link stays up while the advertisement and the browser
/// exist, so both are kept until the transfer ends.
final class NearbyPeerToPeer: NSObject, NetServiceDelegate, NetServiceBrowserDelegate {
  private var published: NetService?
  private var publishResult: FlutterResult?

  private var browser: NetServiceBrowser?
  private var resolving: NetService?
  private var targetName: String?
  private var resolveResult: FlutterResult?
  private var resolveTimeout: DispatchWorkItem?

  // MARK: Receiver

  func advertise(name: String, type: String, port: Int, result: @escaping FlutterResult) {
    stopAdvertising()
    let service = NetService(domain: "local.", type: type + ".", name: name, port: Int32(port))
    service.includesPeerToPeer = true
    service.delegate = self
    published = service
    publishResult = result
    service.publish()
  }

  func stopAdvertising() {
    published?.stop()
    published = nil
    publishResult?(nil)
    publishResult = nil
  }

  func netServiceDidPublish(_ sender: NetService) {
    guard sender === published else { return }
    publishResult?(nil)
    publishResult = nil
  }

  func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
    guard sender === published else { return }
    published = nil
    publishResult?(FlutterError(code: "P2P_PUBLISH_FAILED", message: "Could not advertise over peer-to-peer Wi-Fi: \(errorDict)", details: nil))
    publishResult = nil
  }

  // MARK: Sender

  func resolve(name: String, type: String, result: @escaping FlutterResult) {
    stopResolving()
    targetName = name
    resolveResult = result
    let browser = NetServiceBrowser()
    browser.includesPeerToPeer = true
    browser.delegate = self
    self.browser = browser
    browser.searchForServices(ofType: type + ".", inDomain: "local.")
    let timeout = DispatchWorkItem { [weak self] in
      self?.finishResolve(FlutterError(code: "P2P_NOT_FOUND", message: "\(name) was not found over peer-to-peer Wi-Fi", details: nil))
    }
    resolveTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
  }

  /// Ends the peer-to-peer link of the sender.
  func stopResolving() {
    finishResolve(FlutterError(code: "P2P_CANCELED", message: "Canceled", details: nil))
    browser?.stop()
    browser = nil
    resolving?.stop()
    resolving = nil
    targetName = nil
  }

  func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
    guard service.name == targetName, resolving == nil else { return }
    service.includesPeerToPeer = true
    service.delegate = self
    resolving = service
    service.resolve(withTimeout: 20)
  }

  func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
    finishResolve(FlutterError(code: "P2P_BROWSE_FAILED", message: "Could not search over peer-to-peer Wi-Fi: \(errorDict)", details: nil))
  }

  func netServiceDidResolveAddress(_ sender: NetService) {
    guard sender === resolving, let addresses = sender.addresses else { return }
    // More addresses may follow; wait for one on the peer-to-peer interface.
    if let address = NearbyPeerToPeer.peerToPeerAddress(addresses) {
      finishResolve(address)
    }
  }

  func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
    guard sender === resolving else { return }
    finishResolve(FlutterError(code: "P2P_RESOLVE_FAILED", message: "Could not resolve over peer-to-peer Wi-Fi: \(errorDict)", details: nil))
  }

  private func finishResolve(_ value: Any?) {
    resolveTimeout?.cancel()
    resolveTimeout = nil
    let result = resolveResult
    resolveResult = nil
    result?(value)
  }

  /// The first link-local IPv6 address on an `awdl` interface, in the scoped
  /// form `fe80::1%12` the HTTP client dials.
  static func peerToPeerAddress(_ addresses: [Data]) -> String? {
    for data in addresses {
      let candidate: String? = data.withUnsafeBytes { raw in
        guard raw.count >= MemoryLayout<sockaddr_in6>.size,
              raw.loadUnaligned(as: sockaddr.self).sa_family == sa_family_t(AF_INET6) else {
          return nil
        }
        var address = raw.loadUnaligned(as: sockaddr_in6.self)
        let scope = address.sin6_scope_id
        guard scope != 0 else { return nil }
        var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard let interfaceName = if_indextoname(scope, &nameBuffer), String(cString: interfaceName).hasPrefix("awdl") else {
          return nil
        }
        var hostBuffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &address.sin6_addr, &hostBuffer, socklen_t(hostBuffer.count)) != nil else {
          return nil
        }
        return "\(String(cString: hostBuffer))%\(scope)"
      }
      if let candidate = candidate {
        return candidate
      }
    }
    return nil
  }
}
