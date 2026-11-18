// The wire format of "Nearby" transfers: devices that are not on the same
// network find each other over Bluetooth Low Energy, agree over BLE on a
// temporary Wi-Fi network (a Wi-Fi Direct group hosted by one of them), and
// then run the regular HTTP transfer over that network.
//
// Everything here is pure Dart so it can be unit tested without a radio.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:localsend_isolates/model/device.dart';

/// The GATT service every Glide instance advertises while it is open.
const nearbyServiceUuid = 'a14b7de9-f229-48d0-ae41-0e3488273987';

/// Read-only: the [NearbyPeerInfo] of the advertising device.
const nearbyInfoCharacteristicUuid = 'b6bc6434-d31a-4001-b1b5-45637ca5102c';

/// Write: a [NearbyRequest], split into frames by [encodeFrames].
/// Read: the [NearbyResponse] to the last request of the reading central.
const nearbyControlCharacteristicUuid = 'cddc666d-cd9d-4f90-b629-a75b69cc45bf';

/// The Bonjour service type of the peer-to-peer mode (also declared in the
/// iOS and macOS Info.plist under NSBonjourServices).
const nearbyBonjourType = '_glide-p2p._tcp';

/// Bumped on incompatible changes of the messages below.
const nearbyProtocolVersion = 1;

/// Payloads larger than this are rejected (a request is ~200 bytes).
const nearbyMaxPayloadSize = 4096;

/// First frame of a payload: discards whatever was buffered before.
const _frameFirst = 0x01;

/// Last frame of a payload: the buffered payload is complete.
const _frameLast = 0x02;

/// What a device can do with Wi-Fi to get a temporary network up.
class NearbyWifiCapabilities {
  /// Can create a Wi-Fi Direct group (with legacy WPA2 client support) that
  /// the other device joins.
  final bool canHost;

  /// Can join a network created by the other device given its SSID and passphrase.
  final bool canJoin;

  /// Can use Apple's peer-to-peer Wi-Fi (AWDL) through Bonjour, which needs
  /// no network at all. Only between Apple devices.
  final bool peerToPeer;

  const NearbyWifiCapabilities({required this.canHost, required this.canJoin, this.peerToPeer = false});

  static const none = NearbyWifiCapabilities(canHost: false, canJoin: false);

  @override
  bool operator ==(Object other) =>
      other is NearbyWifiCapabilities && other.canHost == canHost && other.canJoin == canJoin && other.peerToPeer == peerToPeer;

  @override
  int get hashCode => Object.hash(canHost, canJoin, peerToPeer);

  @override
  String toString() => 'NearbyWifiCapabilities(canHost: $canHost, canJoin: $canJoin, peerToPeer: $peerToPeer)';
}

/// The content of the info characteristic: everything needed to show the
/// device in the radar and to address its HTTP server once a network is up.
class NearbyPeerInfo {
  final int version;
  final String alias;
  final String fingerprint;
  final String? deviceModel;
  final DeviceType deviceType;
  final int port;
  final bool https;
  final NearbyWifiCapabilities wifi;

  /// The device's IPv4 addresses on its regular networks (Ethernet, Wi-Fi).
  /// A sender on another network segment of the same router (for example an
  /// iPhone on Wi-Fi and a PC on Ethernet) reaches the HTTP server there, so
  /// no temporary Wi-Fi network is needed. Missing in older versions.
  final List<String> lanAddresses;

  const NearbyPeerInfo({
    required this.version,
    required this.alias,
    required this.fingerprint,
    required this.deviceModel,
    required this.deviceType,
    required this.port,
    required this.https,
    required this.wifi,
    this.lanAddresses = const [],
  });

  Map<String, Object?> toJson() => {
    'v': version,
    'a': alias,
    'f': fingerprint,
    if (deviceModel != null) 'm': deviceModel,
    't': deviceType.name,
    'p': port,
    's': https,
    'h': wifi.canHost,
    'j': wifi.canJoin,
    'w': wifi.peerToPeer,
    if (lanAddresses.isNotEmpty) 'l': lanAddresses,
  };

  Uint8List toBytes() => _encodeJson(toJson());

  /// Throws [FormatException] on anything that is not a valid info payload.
  static NearbyPeerInfo fromBytes(List<int> bytes) {
    final json = _decodeJson(bytes);
    final fingerprint = _requireString(json, 'f');
    final alias = _requireString(json, 'a');
    if (fingerprint.isEmpty) {
      throw const FormatException('Empty fingerprint');
    }
    return NearbyPeerInfo(
      version: _requireInt(json, 'v'),
      alias: alias,
      fingerprint: fingerprint,
      deviceModel: json['m'] is String ? json['m']! as String : null,
      deviceType: DeviceType.values.firstWhere((t) => t.name == json['t'], orElse: () => DeviceType.desktop),
      port: _requirePort(json, 'p'),
      https: json['s'] == true,
      wifi: NearbyWifiCapabilities(canHost: json['h'] == true, canJoin: json['j'] == true, peerToPeer: json['w'] == true),
      lanAddresses: switch (json['l']) {
        final List<Object?> list => list.whereType<String>().where(_isIpv4).toList(),
        _ => const [],
      },
    );
  }
}

/// A request a sender (BLE central) writes to the receiver (BLE peripheral).
sealed class NearbyRequest {
  const NearbyRequest();

  Map<String, Object?> toJson();

  Uint8List toBytes() => _encodeJson(toJson());

  /// Throws [FormatException] on anything that is not a valid request.
  static NearbyRequest fromBytes(List<int> bytes) {
    final json = _decodeJson(bytes);
    return switch (json['op']) {
      'host' => NearbyHostRequest(fingerprint: _requireString(json, 'f'), alias: _requireString(json, 'a')),
      'join' => NearbyJoinRequest(
        fingerprint: _requireString(json, 'f'),
        alias: _requireString(json, 'a'),
        ssid: _requireString(json, 'n'),
        passphrase: _requireString(json, 'k'),
        hostIp: _requireString(json, 'g'),
      ),
      'p2p' => NearbyPeerToPeerRequest(fingerprint: _requireString(json, 'f'), alias: _requireString(json, 'a')),
      'end' => NearbyEndRequest(fingerprint: _requireString(json, 'f')),
      final op => throw FormatException('Unknown request "$op"'),
    };
  }
}

/// "Create a Wi-Fi network and tell me how to join it."
/// Sent when the receiver can host.
class NearbyHostRequest extends NearbyRequest {
  /// The sender, as shown in logs; the HTTP transfer verifies the real identity.
  final String fingerprint;
  final String alias;

  const NearbyHostRequest({required this.fingerprint, required this.alias});

  @override
  Map<String, Object?> toJson() => {'op': 'host', 'f': fingerprint, 'a': alias};
}

/// "Join the Wi-Fi network I created and tell me your address on it."
/// Sent when only the sender can host.
class NearbyJoinRequest extends NearbyRequest {
  final String fingerprint;
  final String alias;
  final String ssid;
  final String passphrase;

  /// The address of the host on its network; the joiner looks for its own
  /// address in the same subnet.
  final String hostIp;

  const NearbyJoinRequest({
    required this.fingerprint,
    required this.alias,
    required this.ssid,
    required this.passphrase,
    required this.hostIp,
  });

  @override
  Map<String, Object?> toJson() => {'op': 'join', 'f': fingerprint, 'a': alias, 'n': ssid, 'k': passphrase, 'g': hostIp};
}

/// "Advertise your HTTP server over Apple's peer-to-peer Wi-Fi."
/// Sent when both devices support [NearbyWifiCapabilities.peerToPeer].
class NearbyPeerToPeerRequest extends NearbyRequest {
  final String fingerprint;
  final String alias;

  const NearbyPeerToPeerRequest({required this.fingerprint, required this.alias});

  @override
  Map<String, Object?> toJson() => {'op': 'p2p', 'f': fingerprint, 'a': alias};
}

/// "The transfer is over, tear the temporary network down."
class NearbyEndRequest extends NearbyRequest {
  /// The sender that is done. Identifies it across BLE connections, whose
  /// addresses may rotate during a long transfer.
  final String fingerprint;

  const NearbyEndRequest({required this.fingerprint});

  @override
  Map<String, Object?> toJson() => {'op': 'end', 'f': fingerprint};
}

/// What the receiver answers on the control characteristic.
sealed class NearbyResponse {
  const NearbyResponse();

  Map<String, Object?> toJson();

  Uint8List toBytes() => _encodeJson(toJson());

  /// Throws [FormatException] on anything that is not a valid response.
  static NearbyResponse fromBytes(List<int> bytes) {
    final json = _decodeJson(bytes);
    return switch (json['s']) {
      'idle' => const NearbyIdleResponse(),
      'pending' => const NearbyPendingResponse(),
      'hosting' => NearbyHostingResponse(
        ssid: _requireString(json, 'n'),
        passphrase: _requireString(json, 'k'),
        ip: _requireString(json, 'i'),
        port: _requirePort(json, 'p'),
        https: json['x'] == true,
      ),
      'joined' => NearbyJoinedResponse(ip: _requireString(json, 'i'), port: _requirePort(json, 'p'), https: json['x'] == true),
      'p2p' => NearbyPeerToPeerResponse(
        serviceName: _requireString(json, 'n'),
        port: _requirePort(json, 'p'),
        https: json['x'] == true,
      ),
      'ended' => const NearbyEndedResponse(),
      'error' => NearbyErrorResponse(json['e'] is String ? json['e']! as String : 'Unknown error', retryable: json['r'] == true),
      final status => throw FormatException('Unknown response "$status"'),
    };
  }
}

/// No request has been received from this central yet.
class NearbyIdleResponse extends NearbyResponse {
  const NearbyIdleResponse();

  @override
  Map<String, Object?> toJson() => {'s': 'idle'};
}

/// The request is being processed; read again later.
class NearbyPendingResponse extends NearbyResponse {
  const NearbyPendingResponse();

  @override
  Map<String, Object?> toJson() => {'s': 'pending'};
}

/// Answer to [NearbyHostRequest]: the network is up.
class NearbyHostingResponse extends NearbyResponse {
  final String ssid;
  final String passphrase;

  /// The receiver's address on that network, where its HTTP server answers.
  final String ip;
  final int port;
  final bool https;

  const NearbyHostingResponse({required this.ssid, required this.passphrase, required this.ip, required this.port, required this.https});

  @override
  Map<String, Object?> toJson() => {'s': 'hosting', 'n': ssid, 'k': passphrase, 'i': ip, 'p': port, 'x': https};
}

/// Answer to [NearbyJoinRequest]: the receiver joined and listens at [ip].
class NearbyJoinedResponse extends NearbyResponse {
  final String ip;
  final int port;
  final bool https;

  const NearbyJoinedResponse({required this.ip, required this.port, required this.https});

  @override
  Map<String, Object?> toJson() => {'s': 'joined', 'i': ip, 'p': port, 'x': https};
}

/// Answer to [NearbyPeerToPeerRequest]: the HTTP server is advertised over
/// peer-to-peer Bonjour as [serviceName] (type [nearbyBonjourType]).
class NearbyPeerToPeerResponse extends NearbyResponse {
  final String serviceName;
  final int port;
  final bool https;

  const NearbyPeerToPeerResponse({required this.serviceName, required this.port, required this.https});

  @override
  Map<String, Object?> toJson() => {'s': 'p2p', 'n': serviceName, 'p': port, 'x': https};
}

/// Answer to [NearbyEndRequest].
class NearbyEndedResponse extends NearbyResponse {
  const NearbyEndedResponse();

  @override
  Map<String, Object?> toJson() => {'s': 'ended'};
}

/// The request failed; [message] is meant for the sender's UI.
class NearbyErrorResponse extends NearbyResponse {
  final String message;

  /// The request failed while setting up Wi-Fi, so another [NearbyLinkMode]
  /// may still work. `false` when the receiver refused the sender.
  final bool retryable;

  const NearbyErrorResponse(this.message, {this.retryable = false});

  @override
  Map<String, Object?> toJson() => {'s': 'error', 'e': message, if (retryable) 'r': true};
}

/// How the two devices get a network for the transfer.
enum NearbyLinkMode {
  /// Apple peer-to-peer Wi-Fi (AWDL): nobody hosts, nobody leaves their
  /// network. Preferred whenever both devices support it.
  peerToPeer,

  /// The receiver hosts, the sender joins. Preferred over [senderHosts]: the
  /// receiver is the one whose HTTP server is dialed, and as the host it has
  /// a fixed address.
  receiverHosts,

  /// The sender hosts, the receiver joins and reports its address.
  senderHosts,
}

/// Every way the two devices can connect, best first. The next one is tried
/// when one fails, e.g. on a PC whose adapter turns out not to support Wi-Fi
/// Direct.
List<NearbyLinkMode> candidateLinkModes({required NearbyWifiCapabilities sender, required NearbyWifiCapabilities receiver}) {
  return [
    if (sender.peerToPeer && receiver.peerToPeer) NearbyLinkMode.peerToPeer,
    if (receiver.canHost && sender.canJoin) NearbyLinkMode.receiverHosts,
    if (sender.canHost && receiver.canJoin) NearbyLinkMode.senderHosts,
  ];
}

/// Picks how to connect, or `null` when no combination works (e.g. a
/// Windows PC and a Mac where neither can host).
NearbyLinkMode? decideLinkMode({required NearbyWifiCapabilities sender, required NearbyWifiCapabilities receiver}) {
  return candidateLinkModes(sender: sender, receiver: receiver).firstOrNull;
}

/// Splits [payload] into frames of at most [maxFrameSize] bytes, each
/// prefixed with a flag byte, so that a request never needs a "long write"
/// (prepared writes are rejected by CoreBluetooth peripherals).
///
/// [maxFrameSize] is the usable ATT payload, i.e. the negotiated MTU minus 3.
List<Uint8List> encodeFrames(List<int> payload, int maxFrameSize) {
  if (maxFrameSize < 2) {
    throw ArgumentError.value(maxFrameSize, 'maxFrameSize', 'must leave room for at least one data byte');
  }
  if (payload.length > nearbyMaxPayloadSize) {
    throw ArgumentError.value(payload.length, 'payload', 'exceeds $nearbyMaxPayloadSize bytes');
  }
  final chunkSize = maxFrameSize - 1;
  final frames = <Uint8List>[];
  var offset = 0;
  do {
    final end = (offset + chunkSize).clamp(0, payload.length);
    var flags = 0;
    if (offset == 0) {
      flags |= _frameFirst;
    }
    if (end == payload.length) {
      flags |= _frameLast;
    }
    frames.add(Uint8List.fromList([flags, ...payload.sublist(offset, end)]));
    offset = end;
  } while (offset < payload.length);
  return frames;
}

/// Reassembles frames produced by [encodeFrames], one instance per central.
class FrameAssembler {
  final _buffer = BytesBuilder(copy: false);
  bool _started = false;

  /// Returns the complete payload once the last frame arrived, otherwise `null`.
  /// Throws [FormatException] on frames that do not form a valid sequence.
  Uint8List? add(List<int> frame) {
    if (frame.isEmpty) {
      throw const FormatException('Empty frame');
    }
    final flags = frame[0];
    if (flags & _frameFirst != 0) {
      _buffer.clear();
      _started = true;
    } else if (!_started) {
      throw const FormatException('Continuation frame without a first frame');
    }
    _buffer.add(frame.sublist(1));
    if (_buffer.length > nearbyMaxPayloadSize) {
      reset();
      throw const FormatException('Payload too large');
    }
    if (flags & _frameLast != 0) {
      _started = false;
      return _buffer.takeBytes();
    }
    return null;
  }

  void reset() {
    _buffer.clear();
    _started = false;
  }
}

/// Whether [ip] and [other] are IPv4 addresses in the same /24, the subnet of
/// a Wi-Fi Direct group (192.168.49.0/24 on Android).
bool isSameIpv4Subnet24(String ip, String other) {
  final a = ip.split('.');
  final b = other.split('.');
  if (a.length != 4 || b.length != 4) {
    return false;
  }
  return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
}

bool _isIpv4(String ip) => InternetAddress.tryParse(ip)?.type == InternetAddressType.IPv4;

Uint8List _encodeJson(Map<String, Object?> json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

Map<String, Object?> _decodeJson(List<int> bytes) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('Invalid payload: $e');
  }
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Payload is not an object');
  }
  return decoded;
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Missing "$key"');
  }
  return value;
}

int _requireInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('Missing "$key"');
  }
  return value;
}

int _requirePort(Map<String, Object?> json, String key) {
  final value = _requireInt(json, key);
  if (value <= 0 || value > 65535) {
    throw FormatException('Invalid port $value');
  }
  return value;
}
