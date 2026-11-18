// Nearby: finds Glide devices over Bluetooth Low Energy while the app is open,
// even when they are not on the same network, and sets up a direct Wi-Fi link
// for the transfer itself, torn down once it is over.
//
// Roles, per transfer:
// - The sender is the BLE central. It reads the receiver's [NearbyPeerInfo]
//   and writes a [NearbyRequest] to the control characteristic.
// - The receiver is the BLE peripheral ([NearbyPeripheral]). It answers on
//   the same characteristic, which the sender polls.
// - How the link comes up is a [NearbyLinkMode]: Apple peer-to-peer Wi-Fi
//   between Apple devices, otherwise whoever can host (Android, Windows,
//   Linux) creates a network, preferring the receiver, and the other side
//   joins it. If one way fails, the next one is tried. The regular HTTP
//   transfer then runs over the link, pinned to the fingerprint read over BLE.
// - When the send session ends, the sender writes [NearbyEndRequest] and both
//   sides drop the link. A watchdog on the receiver covers senders that
//   disappear without saying so.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/model/persistence/device_visibility.dart';
import 'package:glide/model/state/send/send_session_state.dart';
import 'package:glide/provider/device_info_provider.dart';
import 'package:glide/provider/device_visibility_provider.dart';
import 'package:glide/provider/favorites_provider.dart';
import 'package:glide/provider/local_ip_provider.dart';
import 'package:glide/provider/network/nearby/nearby_peripheral.dart';
import 'package:glide/provider/network/nearby/nearby_protocol.dart';
import 'package:glide/provider/network/nearby/wifi_link.dart';
import 'package:glide/provider/network/nearby_devices_provider.dart';
import 'package:glide/provider/network/send_provider.dart';
import 'package:glide/provider/network/server/server_provider.dart';
import 'package:glide/provider/security_provider.dart';
import 'package:glide/provider/settings_provider.dart';
import 'package:localsend_isolates/constants.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

final _logger = Logger('Nearby');

/// A device that is no longer advertising disappears from the radar after this.
const _peerTimeout = Duration(seconds: 45);

/// Scans are restarted periodically: some platforms report a device only once
/// per scan, which would otherwise look like the device went away.
const _scanCycle = Duration(seconds: 20);

/// The info of a device is read again after this, to pick up a renamed device.
const _infoMaxAge = Duration(minutes: 5);

/// The receiver tears its temporary network down when no transfer has been
/// running on it for this long (e.g. the sender vanished without "end").
const _receiverIdleTimeout = Duration(minutes: 2);

const _bleOperationTimeout = Duration(seconds: 10);

final nearbyProvider = NotifierProvider<NearbyService, NearbyState>((ref) => NearbyService());

enum NearbyProblem {
  /// Bluetooth is turned off or not authorized.
  bluetoothUnavailable,

  /// A permission needed for Bluetooth or Wi-Fi Direct was denied.
  permissionDenied,
}

class NearbyState {
  /// Bluetooth discovery is running.
  final bool running;

  /// Why discovery is not running although it is enabled, if known.
  final NearbyProblem? problem;

  /// Send sessions currently setting up their temporary network.
  final Set<String> connectingSessions;

  const NearbyState({required this.running, required this.problem, required this.connectingSessions});

  NearbyState copyWith({bool? running, NearbyProblem? problem, bool clearProblem = false, Set<String>? connectingSessions}) {
    return NearbyState(
      running: running ?? this.running,
      problem: clearProblem ? null : (problem ?? this.problem),
      connectingSessions: connectingSessions ?? this.connectingSessions,
    );
  }
}

class NearbyException implements Exception {
  final String message;

  const NearbyException(this.message);

  @override
  String toString() => message;
}

/// A request the receiver answered with [NearbyErrorResponse].
class _RemoteNearbyException extends NearbyException {
  final bool retryable;

  const _RemoteNearbyException(super.message, {required this.retryable});
}

/// The temporary network of one send session, as seen by the sender.
class NearbyLink {
  final String bleId;

  /// How the network came about.
  final NearbyLinkMode mode;

  /// Where the receiver's HTTP server answers on the temporary network.
  final String ip;
  final int port;
  final bool https;

  const NearbyLink({required this.bleId, required this.mode, required this.ip, required this.port, required this.https});
}

class _Peer {
  final String bleId;
  DateTime lastSeen;
  NearbyPeerInfo? info;
  DateTime? resolvedAt;
  DateTime? retryAfter;
  int failures = 0;

  /// This is our own advertisement (seen on platforms that report it).
  bool own = false;

  _Peer(this.bleId, this.lastSeen);
}

/// The temporary network on the receiving side.
class _ReceiverNetwork {
  final NearbyLinkMode mode;

  /// The SSID of the network, or the Bonjour service name in peer-to-peer mode.
  final String ssid;

  /// The address the sender was told to dial.
  final String ip;

  /// Fingerprints of the senders that asked for this network and did not send
  /// "end" yet.
  final Set<String> senders;
  DateTime lastActive;

  _ReceiverNetwork({required this.mode, required this.ssid, required this.ip, required this.senders, required this.lastActive});
}

class NearbyService extends Notifier<NearbyState> {
  final WifiLink _wifi = WifiLink.forPlatform();
  final NearbyPeripheral _peripheral = NearbyPeripheral.forPlatform();

  final _peers = <String, _Peer>{};
  final _resolveQueue = <String>[];
  bool _resolving = false;

  /// Paused while a sender talks to a receiver: one BLE connection at a time
  /// keeps the slower stacks (Windows, Linux) out of trouble.
  int _exchangeCount = 0;

  final _assemblers = <String, FrameAssembler>{};
  final _responses = <String, NearbyResponse>{};
  _ReceiverNetwork? _receiverNetwork;

  /// Send session ID -> its temporary network.
  final _senderLinks = <String, NearbyLink>{};

  bool _starting = false;

  /// Whether the app is paused (mobile: in the background).
  bool _inBackground = false;
  bool _advertising = false;
  bool _availabilityListenerSet = false;
  Timer? _cycleTimer;
  Timer? _watchdogTimer;
  StreamSubscription<NotifierEvent<Map<String, SendSessionState>>>? _sendSubscription;
  AppLifecycleListener? _lifecycleListener;

  @override
  NearbyState init() => const NearbyState(running: false, problem: null, connectingSessions: {});

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _watchdogTimer?.cancel();
    unawaited(_sendSubscription?.cancel());
    _lifecycleListener?.dispose();
    super.dispose();
  }

  static bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Starts advertising and scanning if enabled in the settings.
  /// Safe to call repeatedly; called on app start and whenever a relevant
  /// setting changes.
  Future<void> start() async {
    if (!isSupportedPlatform || _starting || state.running) {
      return;
    }
    if (!ref.read(settingsProvider).nearbyBluetooth) {
      return;
    }
    _starting = true;
    try {
      _sendSubscription ??= ref.stream(sendProvider).listen((event) => _onSendSessionsChanged(event.next));
      _lifecycleListener ??= AppLifecycleListener(
        onPause: () {
          _inBackground = true;
          unawaited(_stopIfIdleInBackground());
        },
        onResume: () {
          _inBackground = false;
          unawaited(_resumeInForeground());
        },
      );

      await _wifi.init();
      _logger.info('Wi-Fi capabilities: ${_wifi.capabilities}');

      if (!await _requestPermissions()) {
        state = state.copyWith(problem: NearbyProblem.permissionDenied);
        return;
      }

      if (!_availabilityListenerSet) {
        _availabilityListenerSet = true;
        UniversalBle.onAvailabilityChange = _onAvailabilityChange;
      }
      final availability = await UniversalBle.getBluetoothAvailabilityState();
      if (availability != AvailabilityState.poweredOn) {
        _logger.info('Bluetooth is not available: $availability');
        state = state.copyWith(problem: NearbyProblem.bluetoothUnavailable);
        return;
      }

      await _startAdvertising();
      await _startScan();
      _cycleTimer?.cancel();
      _cycleTimer = Timer.periodic(_scanCycle, (_) => unawaited(_onCycle()));
      state = state.copyWith(running: true, clearProblem: true);
      // The app may have gone to the background while this was starting.
      unawaited(_stopIfIdleInBackground());
    } catch (e, st) {
      _logger.warning('Could not start Bluetooth discovery', e, st);
      state = state.copyWith(problem: NearbyProblem.bluetoothUnavailable);
    } finally {
      _starting = false;
    }
  }

  /// Stops advertising and scanning and removes every device found over BLE.
  /// Running transfers and their networks are not affected.
  Future<void> stop() async {
    _cycleTimer?.cancel();
    _cycleTimer = null;
    state = state.copyWith(running: false);
    try {
      await UniversalBle.stopScan();
    } catch (e) {
      _logger.fine('stopScan failed', e);
    }
    await _stopAdvertising();
    for (final peer in _peers.values) {
      final fingerprint = peer.info?.fingerprint;
      if (fingerprint != null) {
        ref.redux(nearbyDevicesProvider).dispatch(UnregisterBluetoothDeviceAction(fingerprint));
      }
    }
    _peers.clear();
    _resolveQueue.clear();
  }

  /// Applies a change of the "Nearby" setting.
  Future<void> setEnabled(bool enabled) async {
    await ref.notifier(settingsProvider).setNearbyBluetooth(enabled);
    if (enabled) {
      await start();
    } else {
      await stop();
      state = state.copyWith(clearProblem: true);
    }
  }

  /// Advertises or stops advertising after the visibility changed.
  Future<void> refreshAdvertising() async {
    if (!state.running) {
      return;
    }
    await _stopAdvertising();
    await _startAdvertising();
  }

  /// Whether a transfer still needs BLE: a link being set up, a sender link
  /// that has to be ended over BLE, a temporary network as receiver, or a
  /// send session that may still need [openLink] or [lanAddressesOf].
  bool get _busy => _exchangeCount > 0 || _senderLinks.isNotEmpty || _receiverNetwork != null || ref.read(sendProvider).isNotEmpty;

  /// Mobile apps cannot keep a BLE peripheral useful in the background, and a
  /// receive server that is suspended would not answer anyway, so discovery
  /// stops there. Not while a transfer is going on, though: switching apps (or
  /// the system's Wi-Fi join prompt) must not drop the peer it depends on.
  /// Called again whenever a transfer ends.
  Future<void> _stopIfIdleInBackground() async {
    if (!_inBackground || !(Platform.isAndroid || Platform.isIOS) || !state.running || _starting || _busy) {
      return;
    }
    _logger.info('In the background, stopping Bluetooth discovery');
    await stop();
  }

  /// Back in the foreground: start again, or, when discovery kept running
  /// (a transfer was going on, or a desktop), re-advertise and restart the
  /// scan, which the OS may have stopped silently, so the info reflects the
  /// current addresses.
  Future<void> _resumeInForeground() async {
    if (!state.running) {
      await start();
      return;
    }
    if (!_busy) {
      await refreshAdvertising();
    }
    try {
      await UniversalBle.stopScan();
    } catch (e) {
      _logger.fine('stopScan failed', e);
    }
    try {
      await _startScan();
    } catch (e, st) {
      _logger.warning('Could not restart the Bluetooth scan', e, st);
    }
  }

  void _onAvailabilityChange(AvailabilityState availability) {
    _logger.info('Bluetooth availability: $availability');
    if (availability == AvailabilityState.poweredOn) {
      unawaited(start());
    } else if (state.running) {
      unawaited(stop().then((_) => state = state.copyWith(problem: NearbyProblem.bluetoothUnavailable)));
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final sdkInt = ref.read(deviceRawInfoProvider).androidSdkInt ?? 0;
      final permissions = <Permission>[
        if (sdkInt >= 31) ...[Permission.bluetoothScan, Permission.bluetoothConnect, Permission.bluetoothAdvertise],
        if (sdkInt >= 33) Permission.nearbyWifiDevices,
        // BLE scans before Android 12 and Wi-Fi Direct before Android 13 are
        // gated behind the location permission.
        if (sdkInt < 33) Permission.locationWhenInUse,
      ];
      final statuses = await permissions.request();
      final denied = statuses.entries.where((e) => !e.value.isGranted).map((e) => e.key).toList();
      if (denied.isNotEmpty) {
        _logger.warning('Nearby permissions denied: $denied');
        return false;
      }
      return true;
    }
    try {
      await UniversalBle.requestPermissions();
      return true;
    } catch (e) {
      _logger.warning('Bluetooth permission denied', e);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Receiver side: GATT server
  // ---------------------------------------------------------------------------

  Future<void> _startAdvertising() async {
    if (_advertising) {
      return;
    }
    if (ref.read(deviceVisibilityProvider) == DeviceVisibility.hidden) {
      return;
    }
    if (ref.read(serverProvider) == null) {
      // Nothing could be received anyway.
      return;
    }
    try {
      _advertising = await _peripheral.start(onRead: _onReadRequest, onWrite: _onWriteRequest);
      if (_advertising) {
        _logger.info('Advertising over BLE');
      }
    } catch (e, st) {
      _logger.warning('Could not advertise over BLE', e, st);
    }
  }

  Future<void> _stopAdvertising() async {
    if (!_advertising) {
      return;
    }
    _advertising = false;
    try {
      await _peripheral.stop();
    } catch (e) {
      _logger.fine('Stopping the BLE peripheral failed', e);
    }
  }

  /// The info characteristic, built on every read so it reflects renames and
  /// server restarts.
  NearbyPeerInfo? _ownInfo() {
    final server = ref.read(serverProvider);
    if (server == null) {
      return null;
    }
    final deviceInfo = ref.read(deviceInfoProvider);
    return NearbyPeerInfo(
      version: nearbyProtocolVersion,
      alias: server.alias,
      fingerprint: ref.read(securityProvider).certificateHash,
      deviceModel: deviceInfo.deviceModel,
      deviceType: deviceInfo.deviceType,
      port: server.port,
      https: server.https,
      wifi: _wifi.capabilities,
      lanAddresses: _ownLanAddresses(),
    );
  }

  /// This device's IPv4 addresses on regular networks, private ranges first,
  /// so a sender on the same router can skip the temporary Wi-Fi network.
  List<String> _ownLanAddresses() {
    final ips = ref.read(localIpProvider).localIps.where((ip) {
      final address = InternetAddress.tryParse(ip);
      return address != null && address.type == InternetAddressType.IPv4 && !address.isLoopback && !address.isLinkLocal;
    }).toList();
    bool isPrivate(String ip) => ip.startsWith('192.168.') || ip.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
    ips.sort((a, b) => (isPrivate(a) ? 0 : 1).compareTo(isPrivate(b) ? 0 : 1));
    return ips.take(6).toList();
  }

  /// The regular-network addresses [target] announced over BLE, to try
  /// before setting up a temporary Wi-Fi network.
  List<String> lanAddressesOf(Device target) {
    return _peers.values.where((p) => p.info?.fingerprint == target.fingerprint).expand((p) => p.info!.lanAddresses).toSet().toList();
  }

  Uint8List? _onReadRequest(String deviceId, String characteristic) {
    if (characteristic == nearbyInfoCharacteristicUuid) {
      return _ownInfo()?.toBytes() ?? Uint8List(0);
    }
    if (characteristic == nearbyControlCharacteristicUuid) {
      final response = _responses[_centralKey(deviceId)] ?? const NearbyIdleResponse();
      return response.toBytes();
    }
    return null;
  }

  void _onWriteRequest(String deviceId, String characteristic, Uint8List value) {
    if (characteristic != nearbyControlCharacteristicUuid) {
      return;
    }
    final central = _centralKey(deviceId);
    try {
      final payload = _assemblers.putIfAbsent(central, FrameAssembler.new).add(value);
      if (payload != null) {
        final request = NearbyRequest.fromBytes(payload);
        _responses[central] = const NearbyPendingResponse();
        unawaited(_handleRequest(central, request));
      }
    } on FormatException catch (e) {
      _logger.warning('Invalid Nearby request from $central', e);
      _responses[central] = NearbyErrorResponse('Invalid request: ${e.message}');
    }
  }

  static String _centralKey(String deviceId) => deviceId.toLowerCase();

  Future<void> _handleRequest(String central, NearbyRequest request) async {
    NearbyResponse response;
    try {
      response = switch (request) {
        NearbyHostRequest() => await _handleHostRequest(central, request),
        NearbyJoinRequest() => await _handleJoinRequest(central, request),
        NearbyPeerToPeerRequest() => await _handlePeerToPeerRequest(central, request),
        NearbyEndRequest() => await _handleEndRequest(central, request),
      };
    } catch (e, st) {
      _logger.warning('Nearby request ${request.runtimeType} from $central failed', e, st);
      // Refusals are NearbyExceptions; anything else failed while setting up
      // Wi-Fi, and the sender may try another way.
      response = NearbyErrorResponse(e.toString(), retryable: e is! NearbyException);
    }
    _responses[central] = response;
  }

  /// Checks a sender before a network is set up for it.
  /// The HTTP layer applies the same rules again with verified identities.
  void _checkSenderAllowed(String fingerprint) {
    if (ref.read(serverProvider) == null) {
      throw const NearbyException('Receiving is turned off');
    }
    final visibility = ref.read(deviceVisibilityProvider);
    if (visibility == DeviceVisibility.hidden) {
      throw const NearbyException('Not accepting transfers');
    }
    if (visibility == DeviceVisibility.contactsOnly && !ref.read(favoritesProvider).any((f) => f.fingerprint == fingerprint)) {
      throw const NearbyException('Only accepting transfers from contacts');
    }
  }

  Future<NearbyResponse> _handleHostRequest(String central, NearbyHostRequest request) async {
    _checkSenderAllowed(request.fingerprint);
    if (!_wifi.capabilities.canHost) {
      throw const NearbyException('This device cannot host a Wi-Fi Direct network');
    }
    final existing = _receiverNetwork;
    if (existing != null && existing.mode != NearbyLinkMode.receiverHosts) {
      throw const NearbyException('Busy with another transfer');
    }
    _logger.info('Hosting a Wi-Fi Direct network for ${request.alias}');
    final network = await _wifi.startHosting();
    final server = ref.read(serverProvider)!;
    _setReceiverNetwork(
      existing ?? _ReceiverNetwork(mode: NearbyLinkMode.receiverHosts, ssid: network.ssid, ip: network.ip, senders: {}, lastActive: DateTime.now()),
      request.fingerprint,
    );
    return NearbyHostingResponse(ssid: network.ssid, passphrase: network.passphrase, ip: network.ip, port: server.port, https: server.https);
  }

  Future<NearbyResponse> _handleJoinRequest(String central, NearbyJoinRequest request) async {
    _checkSenderAllowed(request.fingerprint);
    if (!_wifi.capabilities.canJoin) {
      throw const NearbyException('This device cannot join a Wi-Fi Direct network');
    }
    final existing = _receiverNetwork;
    if (existing != null && (existing.mode != NearbyLinkMode.senderHosts || existing.ssid != request.ssid)) {
      throw const NearbyException('Busy with another transfer');
    }
    final String ip;
    if (existing != null) {
      ip = existing.ip;
    } else {
      _logger.info('Joining ${request.ssid} for ${request.alias}');
      try {
        ip = await _wifi
            .join(ssid: request.ssid, passphrase: request.passphrase, hostIp: request.hostIp)
            .timeout(const Duration(seconds: 60), onTimeout: () => throw WifiLinkException('Timed out joining ${request.ssid}'));
      } catch (e) {
        await _wifi.leave();
        rethrow;
      }
    }
    final server = ref.read(serverProvider)!;
    _setReceiverNetwork(
      existing ?? _ReceiverNetwork(mode: NearbyLinkMode.senderHosts, ssid: request.ssid, ip: ip, senders: {}, lastActive: DateTime.now()),
      request.fingerprint,
    );
    return NearbyJoinedResponse(ip: ip, port: server.port, https: server.https);
  }

  Future<NearbyResponse> _handlePeerToPeerRequest(String central, NearbyPeerToPeerRequest request) async {
    _checkSenderAllowed(request.fingerprint);
    if (!_wifi.capabilities.peerToPeer) {
      throw const NearbyException('This device does not support peer-to-peer Wi-Fi');
    }
    final existing = _receiverNetwork;
    if (existing != null && existing.mode != NearbyLinkMode.peerToPeer) {
      throw const NearbyException('Busy with another transfer');
    }
    final server = ref.read(serverProvider)!;
    // Unique enough to tell nearby Glide devices apart; only this sender looks for it.
    final serviceName = existing?.ssid ?? 'Glide-${ref.read(securityProvider).certificateHash.substring(0, 16)}';
    if (existing == null) {
      _logger.info('Advertising over peer-to-peer Wi-Fi for ${request.alias}');
      await _wifi.advertisePeerToPeer(name: serviceName, port: server.port);
    }
    _setReceiverNetwork(
      existing ?? _ReceiverNetwork(mode: NearbyLinkMode.peerToPeer, ssid: serviceName, ip: '', senders: {}, lastActive: DateTime.now()),
      request.fingerprint,
    );
    return NearbyPeerToPeerResponse(serviceName: serviceName, port: server.port, https: server.https);
  }

  Future<NearbyResponse> _handleEndRequest(String central, NearbyEndRequest request) async {
    final network = _receiverNetwork;
    if (network != null) {
      network.senders.remove(request.fingerprint);
      if (network.senders.isEmpty) {
        await _tearDownReceiverNetwork('transfer ended');
      }
    }
    _assemblers.remove(central);
    return const NearbyEndedResponse();
  }

  void _setReceiverNetwork(_ReceiverNetwork network, String senderFingerprint) {
    network.senders.add(senderFingerprint);
    network.lastActive = DateTime.now();
    _receiverNetwork = network;
    _watchdogTimer ??= Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_receiverWatchdog()));
  }

  Future<void> _receiverWatchdog() async {
    final network = _receiverNetwork;
    if (network == null) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
      return;
    }
    final session = ref.read(serverProvider)?.session;
    if (session != null && (session.status == SessionStatus.waiting || session.status == SessionStatus.sending)) {
      network.lastActive = DateTime.now();
      return;
    }
    if (DateTime.now().difference(network.lastActive) > _receiverIdleTimeout) {
      await _tearDownReceiverNetwork('idle');
    }
  }

  Future<void> _tearDownReceiverNetwork(String reason) async {
    final network = _receiverNetwork;
    if (network == null) {
      return;
    }
    _receiverNetwork = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    unawaited(Future<void>.delayed(Duration.zero, _stopIfIdleInBackground));
    _logger.info('Leaving the temporary network ${network.ssid} ($reason)');
    try {
      switch (network.mode) {
        case NearbyLinkMode.peerToPeer:
          await _wifi.stopAdvertisingPeerToPeer();
        case NearbyLinkMode.receiverHosts:
          await _wifi.stopHosting();
        case NearbyLinkMode.senderHosts:
          await _wifi.leave();
      }
    } catch (e) {
      _logger.warning('Could not leave the temporary network', e);
    }
  }

  // ---------------------------------------------------------------------------
  // Discovery: scanning and reading the info of found devices
  // ---------------------------------------------------------------------------

  Future<void> _startScan() async {
    UniversalBle.onScanResult = _onScanResult;
    await UniversalBle.startScan(scanFilter: ScanFilter(withServices: [nearbyServiceUuid]));
  }

  Future<void> _onCycle() async {
    final now = DateTime.now();
    for (final peer in _peers.values.toList()) {
      if (now.difference(peer.lastSeen) > _peerTimeout) {
        _removePeer(peer);
      }
    }
    if (_exchangeCount > 0) {
      return;
    }
    try {
      await UniversalBle.stopScan();
      await _startScan();
    } catch (e) {
      _logger.fine('Restarting the scan failed', e);
    }
  }

  void _onScanResult(BleDevice device) {
    final now = DateTime.now();
    final peer = _peers.putIfAbsent(device.deviceId, () => _Peer(device.deviceId, now))..lastSeen = now;
    if (peer.own) {
      return;
    }
    final resolvedAt = peer.resolvedAt;
    final needsInfo = resolvedAt == null || now.difference(resolvedAt) > _infoMaxAge;
    final retryAfter = peer.retryAfter;
    if (needsInfo && (retryAfter == null || now.isAfter(retryAfter)) && !_resolveQueue.contains(peer.bleId)) {
      _resolveQueue.add(peer.bleId);
      unawaited(_drainResolveQueue());
    } else if (!needsInfo) {
      _publish(peer);
    }
  }

  Future<void> _drainResolveQueue() async {
    if (_resolving) {
      return;
    }
    _resolving = true;
    try {
      while (_resolveQueue.isNotEmpty && state.running) {
        if (_exchangeCount > 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        final peer = _peers[_resolveQueue.removeAt(0)];
        if (peer != null) {
          await _resolve(peer);
        }
      }
    } finally {
      _resolving = false;
    }
  }

  Future<void> _resolve(_Peer peer) async {
    final id = peer.bleId;
    try {
      await UniversalBle.connect(id, timeout: _bleOperationTimeout);
      await UniversalBle.discoverServices(id, timeout: _bleOperationTimeout);
      final bytes = await UniversalBle.read(id, nearbyServiceUuid, nearbyInfoCharacteristicUuid, timeout: _bleOperationTimeout);
      final info = NearbyPeerInfo.fromBytes(bytes);
      if (info.fingerprint == ref.read(securityProvider).certificateHash) {
        peer.own = true;
        return;
      }
      peer
        ..info = info
        ..resolvedAt = DateTime.now()
        ..failures = 0
        ..retryAfter = null;
      _logger.info('Found ${info.alias} over BLE ($id)');
      _publish(peer);
    } catch (e) {
      peer.failures++;
      // 5s, 10s, 20s, ... capped at 2 minutes.
      final backoff = Duration(seconds: (5 * (1 << (peer.failures - 1).clamp(0, 5))).clamp(5, 120));
      peer.retryAfter = DateTime.now().add(backoff);
      _logger.fine('Could not read the info of $id (attempt ${peer.failures})', e);
    } finally {
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {
        // Already disconnected.
      }
    }
  }

  void _publish(_Peer peer) {
    final info = peer.info;
    if (info == null) {
      return;
    }
    final device = Device(
      signalingId: null,
      ip: null,
      version: protocolVersion,
      port: info.port,
      https: info.https,
      fingerprint: info.fingerprint,
      alias: info.alias,
      deviceModel: info.deviceModel,
      deviceType: info.deviceType,
      download: false,
      channels: [
        BluetoothChannel(bleId: peer.bleId, canHost: info.wifi.canHost, canJoin: info.wifi.canJoin, peerToPeer: info.wifi.peerToPeer),
      ],
    );
    final current = ref.read(nearbyDevicesProvider).bluetoothDevices[info.fingerprint];
    if (current != device) {
      ref.redux(nearbyDevicesProvider).dispatch(RegisterBluetoothDeviceAction(device));
    }
  }

  void _removePeer(_Peer peer) {
    _peers.remove(peer.bleId);
    final fingerprint = peer.info?.fingerprint;
    if (fingerprint == null) {
      return;
    }
    // The device may still be advertising under a newer (rotated) address.
    final stillSeen = _peers.values.any((p) => p.info?.fingerprint == fingerprint);
    if (!stillSeen) {
      _logger.info('Lost ${peer.info?.alias} over BLE');
      ref.redux(nearbyDevicesProvider).dispatch(UnregisterBluetoothDeviceAction(fingerprint));
    }
  }

  // ---------------------------------------------------------------------------
  // Sender side
  // ---------------------------------------------------------------------------

  /// Whether a send to [target] has to go through [openLink]: it was found
  /// over BLE and its HTTP server is not reachable on any shared network.
  static BluetoothChannel? bluetoothChannelOf(Device target) => target.channels.whereType<BluetoothChannel>().firstOrNull;

  /// Sets up the temporary network to [target] for the send session
  /// [sessionId]. The network is torn down automatically once that session
  /// ends. Throws [NearbyException] with a user-facing message on failure.
  Future<NearbyLink> openLink({required String sessionId, required Device target}) async {
    final channel = bluetoothChannelOf(target);
    if (channel == null) {
      throw NearbyException(t.glide.nearby.errors.incompatible(device: target.alias));
    }
    final modes = candidateLinkModes(
      sender: _wifi.capabilities,
      receiver: NearbyWifiCapabilities(canHost: channel.canHost, canJoin: channel.canJoin, peerToPeer: channel.peerToPeer),
    );
    if (modes.isEmpty) {
      throw NearbyException(t.glide.nearby.errors.incompatible(device: target.alias));
    }

    state = state.copyWith(connectingSessions: {...state.connectingSessions, sessionId});
    _exchangeCount++;
    try {
      Object? lastError;
      for (final mode in modes) {
        if (ref.read(sendProvider)[sessionId] == null) {
          throw const NearbyException('Canceled');
        }
        try {
          final link = await _openLinkWithMode(target: target, channel: channel, mode: mode);
          _senderLinks[sessionId] = link;
          _logger.info('Link to ${target.alias} is up ($mode), receiver at ${link.ip}:${link.port}');
          // The session may have been canceled meanwhile.
          _onSendSessionsChanged(ref.read(sendProvider));
          return link;
        } catch (e, st) {
          _logger.warning('Could not connect to ${target.alias} with $mode', e, st);
          lastError = e;
          final retryable = e is WifiLinkException || (e is _RemoteNearbyException && e.retryable);
          if (!retryable) {
            break;
          }
        }
      }
      throw switch (lastError) {
        NearbyException() => lastError,
        TimeoutException() => NearbyException(t.glide.nearby.errors.timeout(device: target.alias)),
        WifiLinkException(:final message) => NearbyException(t.glide.nearby.errors.wifi(reason: message)),
        _ => NearbyException(t.glide.nearby.errors.wifi(reason: lastError.toString())),
      };
    } finally {
      _exchangeCount--;
      state = state.copyWith(connectingSessions: {...state.connectingSessions}..remove(sessionId));
    }
  }

  /// Sets up one [mode]; on failure everything it set up is undone again.
  Future<NearbyLink> _openLinkWithMode({required Device target, required BluetoothChannel channel, required NearbyLinkMode mode}) async {
    final self = ref.read(deviceFullInfoProvider);
    var hosting = false;
    var joined = false;
    var resolving = false;
    try {
      switch (mode) {
        case NearbyLinkMode.peerToPeer:
          final response = await _exchange<NearbyPeerToPeerResponse>(
            channel.bleId,
            NearbyPeerToPeerRequest(fingerprint: self.fingerprint, alias: self.alias),
            timeout: const Duration(seconds: 30),
          );
          resolving = true;
          final ip = await _wifi
              .resolvePeerToPeer(name: response.serviceName)
              .timeout(
                const Duration(seconds: 30),
                onTimeout: () => throw WifiLinkException('${target.alias} was not found over peer-to-peer Wi-Fi'),
              );
          return NearbyLink(bleId: channel.bleId, mode: mode, ip: ip, port: response.port, https: response.https);
        case NearbyLinkMode.receiverHosts:
          final response = await _exchange<NearbyHostingResponse>(
            channel.bleId,
            NearbyHostRequest(fingerprint: self.fingerprint, alias: self.alias),
            timeout: const Duration(seconds: 45),
          );
          joined = true;
          await _wifi
              .join(ssid: response.ssid, passphrase: response.passphrase, hostIp: response.ip)
              .timeout(const Duration(seconds: 60), onTimeout: () => throw WifiLinkException('Timed out joining ${response.ssid}'));
          return NearbyLink(bleId: channel.bleId, mode: mode, ip: response.ip, port: response.port, https: response.https);
        case NearbyLinkMode.senderHosts:
          hosting = true;
          final network = await _wifi.startHosting().timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const WifiLinkException('Timed out creating the network'),
          );
          final response = await _exchange<NearbyJoinedResponse>(
            channel.bleId,
            NearbyJoinRequest(
              fingerprint: self.fingerprint,
              alias: self.alias,
              ssid: network.ssid,
              passphrase: network.passphrase,
              hostIp: network.ip,
            ),
            // Joining can wait for the user to confirm a system prompt (iOS).
            timeout: const Duration(seconds: 90),
          );
          return NearbyLink(bleId: channel.bleId, mode: mode, ip: response.ip, port: response.port, https: response.https);
      }
    } catch (_) {
      // Tell the receiver first, so it does not keep its side up.
      await _sendEnd(channel.bleId, self.fingerprint);
      if (joined) {
        await _wifi.leave().catchError((Object _) {});
      }
      if (hosting) {
        await _wifi.stopHosting().catchError((Object _) {});
      }
      if (resolving) {
        await _wifi.stopResolvingPeerToPeer().catchError((Object _) {});
      }
      rethrow;
    }
  }

  void _onSendSessionsChanged(Map<String, SendSessionState> sessions) {
    for (final sessionId in _senderLinks.keys.toList()) {
      final status = sessions[sessionId]?.status;
      final ended = switch (status) {
        null => true,
        SessionStatus.waiting || SessionStatus.sending => false,
        _ => true,
      };
      if (ended) {
        final link = _senderLinks.remove(sessionId)!;
        unawaited(_closeLink(link).whenComplete(_stopIfIdleInBackground));
      }
    }
    if (sessions.isEmpty) {
      unawaited(_stopIfIdleInBackground());
    }
  }

  Future<void> _closeLink(NearbyLink link) async {
    _logger.info('Transfer over, leaving the temporary network');
    await _sendEnd(link.bleId, ref.read(securityProvider).certificateHash);
    try {
      switch (link.mode) {
        case NearbyLinkMode.peerToPeer:
          await _wifi.stopResolvingPeerToPeer();
        case NearbyLinkMode.receiverHosts:
          await _wifi.leave();
        case NearbyLinkMode.senderHosts:
          await _wifi.stopHosting();
      }
    } catch (e) {
      _logger.warning('Could not leave the temporary network', e);
    }
  }

  Future<void> _sendEnd(String bleId, String ownFingerprint) async {
    _exchangeCount++;
    try {
      await _exchange<NearbyEndedResponse>(bleId, NearbyEndRequest(fingerprint: ownFingerprint), timeout: const Duration(seconds: 15));
    } catch (e) {
      // The receiver's watchdog tears its side down eventually.
      _logger.info('Could not tell the receiver that the transfer ended', e);
    } finally {
      _exchangeCount--;
    }
  }

  /// Writes [request] to [bleId] and polls until it answers with a [T].
  Future<T> _exchange<T extends NearbyResponse>(String bleId, NearbyRequest request, {required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    try {
      await UniversalBle.connect(bleId, timeout: _bleOperationTimeout);
      await UniversalBle.discoverServices(bleId, timeout: _bleOperationTimeout);
      var mtu = 23;
      try {
        mtu = await UniversalBle.requestMtu(bleId, 185, timeout: _bleOperationTimeout);
      } catch (e) {
        _logger.fine('MTU negotiation failed, using the default', e);
      }
      for (final frame in encodeFrames(request.toBytes(), (mtu - 3).clamp(20, 512))) {
        await UniversalBle.write(bleId, nearbyServiceUuid, nearbyControlCharacteristicUuid, frame, timeout: _bleOperationTimeout);
      }
      while (true) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('No answer to ${request.runtimeType}', timeout);
        }
        final bytes = await UniversalBle.read(bleId, nearbyServiceUuid, nearbyControlCharacteristicUuid, timeout: _bleOperationTimeout);
        final response = NearbyResponse.fromBytes(bytes);
        switch (response) {
          case T():
            return response;
          case NearbyErrorResponse(:final message, :final retryable):
            throw _RemoteNearbyException(message, retryable: retryable);
          case NearbyPendingResponse() || NearbyIdleResponse():
            await Future<void>.delayed(const Duration(milliseconds: 500));
          default:
            throw NearbyException('Unexpected answer: ${response.runtimeType}');
        }
      }
    } finally {
      try {
        await UniversalBle.disconnect(bleId);
      } catch (_) {
        // Already disconnected.
      }
    }
  }
}
