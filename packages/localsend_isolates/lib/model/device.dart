import 'package:dart_mappable/dart_mappable.dart';

part 'device.mapper.dart';

@MappableEnum(defaultValue: DeviceType.desktop)
enum DeviceType {
  mobile,
  desktop,
  web,
  headless,
  server,
}

/// A channel a device is reachable on.
@MappableClass()
sealed class DeviceChannel with DeviceChannelMappable {
  const DeviceChannel();
}

/// The device's HTTP server, reachable at one address.
@MappableClass()
class HttpChannel extends DeviceChannel with HttpChannelMappable {
  /// The host to dial: an IP address, or the scoped form `fe80::1%3` for
  /// link-local IPv6 (the Rust HTTP client accepts both back as a host).
  final String host;

  /// The port of the device's HTTP server at this address.
  final int port;

  /// Whether the HTTP server uses TLS.
  final bool https;

  const HttpChannel({required this.host, required this.port, required this.https});
}

/// The device is reachable over WebRTC through a signaling server.
@MappableClass()
class SignalingChannel extends DeviceChannel with SignalingChannelMappable {
  final String signalingServer;

  const SignalingChannel({required this.signalingServer});
}

/// The device was found over Bluetooth Low Energy and is not on a shared
/// network: a temporary Wi-Fi Direct network has to be set up over BLE before
/// its HTTP server can be reached (see the app's Nearby service).
@MappableClass()
class BluetoothChannel extends DeviceChannel with BluetoothChannelMappable {
  /// The platform's BLE identifier of the device (a MAC address on Android,
  /// Windows and Linux, a per-app UUID on iOS and macOS).
  final String bleId;

  /// Whether the device can create the temporary network.
  final bool canHost;

  /// Whether the device can join a temporary network created by this one.
  final bool canJoin;

  const BluetoothChannel({required this.bleId, required this.canHost, required this.canJoin});
}

/// Whether a [DeviceLog] discovered the device or re-confirmed it.
enum DeviceLogKind {
  discovered,
  updated,
}

/// One retained confirmation of a stored device, for the device details UI.
class DeviceLog {
  /// When the confirmation happened.
  final DateTime timestamp;

  final DeviceLogKind kind;

  /// The channel the confirmation happened on.
  final HttpChannel channel;

  const DeviceLog({
    required this.timestamp,
    required this.kind,
    required this.channel,
  });
}

enum TransmissionMethod {
  http('HTTP'),
  webrtc('WebRTC'),
  bluetooth('Bluetooth + Wi-Fi Direct')
  ;

  final String label;

  const TransmissionMethod(this.label);
}

/// Internal device model.
/// It gets not serialized.
@MappableClass()
class Device with DeviceMappable {
  /// A unique ID provided by the signaling server.
  final String? signalingId;

  /// The IP address of the device.
  /// Is null when found via signaling.
  final String? ip;

  final String version;
  final int port;
  final bool https;
  final String fingerprint;
  final String alias;
  final String? deviceModel;
  final DeviceType deviceType;
  final bool download;

  /// Every channel the device was confirmed on, best first.
  final List<DeviceChannel> channels;

  Set<TransmissionMethod> get transmissionMethods {
    return {
      for (final channel in channels)
        switch (channel) {
          HttpChannel() => TransmissionMethod.http,
          SignalingChannel() => TransmissionMethod.webrtc,
          BluetoothChannel() => TransmissionMethod.bluetooth,
        },
    };
  }

  const Device({
    required this.signalingId,
    required this.ip,
    required this.version,
    required this.port,
    required this.https,
    required this.fingerprint,
    required this.alias,
    required this.deviceModel,
    required this.deviceType,
    required this.download,
    required this.channels,
  });

  static const empty = Device(
    signalingId: null,
    ip: null,
    version: '',
    port: -1,
    https: false,
    fingerprint: '',
    alias: '',
    deviceModel: null,
    deviceType: DeviceType.desktop,
    download: false,
    channels: [],
  );
}
