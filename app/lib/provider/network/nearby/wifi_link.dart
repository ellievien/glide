// Platform access to the temporary network of a Nearby transfer.
//
// - Android hosts a Wi-Fi Direct group (which legacy WPA2 clients can join as
//   a regular access point) and joins other Android groups as a P2P client.
// - Windows hosts a Wi-Fi Direct legacy access point (WinRT, in the runner)
//   and joins with a temporary WLAN profile (wlanapi.dll).
// - Linux hosts a hotspot and joins through NetworkManager (nmcli).
// - iOS and macOS join through the system (NEHotspotConfiguration /
//   CoreWLAN), and talk to each other over peer-to-peer Wi-Fi (AWDL), found
//   through Bonjour, so that two Apple devices need no host at all.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:glide/provider/network/nearby/nearby_protocol.dart';
import 'package:logging/logging.dart';
import 'package:win32/win32.dart' as win32;

final _logger = Logger('WifiLink');

/// A network created by this device.
class HostedWifiNetwork {
  final String ssid;
  final String passphrase;

  /// This device's address on the network.
  final String ip;

  const HostedWifiNetwork({required this.ssid, required this.passphrase, required this.ip});
}

class WifiLinkException implements Exception {
  final String message;

  const WifiLinkException(this.message);

  @override
  String toString() => message;
}

abstract class WifiLink {
  WifiLink();

  /// Resolved once by [init]; [NearbyWifiCapabilities.none] until then.
  NearbyWifiCapabilities get capabilities;

  Future<void> init();

  /// Creates a network, or returns the one already created by this device.
  Future<HostedWifiNetwork> startHosting();

  /// Tears the network down. No-op when not hosting.
  Future<void> stopHosting();

  /// Joins the network [ssid] whose host is at [hostIp], and returns this
  /// device's address on it.
  Future<String> join({required String ssid, required String passphrase, required String hostIp});

  /// Leaves the network joined by [join] and lets the system return to the
  /// previous one. No-op when not joined.
  Future<void> leave();

  /// Advertises this device's HTTP server at [port] over Apple's
  /// peer-to-peer Wi-Fi (Bonjour with AWDL) under the service [name].
  Future<void> advertisePeerToPeer({required String name, required int port}) =>
      throw const WifiLinkException('Peer-to-peer Wi-Fi is only available on Apple devices');

  Future<void> stopAdvertisingPeerToPeer() async {}

  /// Finds the service [name] advertised by [advertisePeerToPeer] and
  /// returns an address of it that is reachable over peer-to-peer Wi-Fi.
  /// Keeps the peer-to-peer link up until [stopResolvingPeerToPeer].
  Future<String> resolvePeerToPeer({required String name}) => throw const WifiLinkException('Peer-to-peer Wi-Fi is only available on Apple devices');

  Future<void> stopResolvingPeerToPeer() async {}

  factory WifiLink.forPlatform() {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      return _ChannelWifiLink();
    }
    if (Platform.isWindows) {
      return _WindowsWifiLink();
    }
    if (Platform.isLinux) {
      return _LinuxWifiLink();
    }
    return _UnsupportedWifiLink();
  }
}

/// A random string for network names and passphrases, without look-alike characters.
String _randomString(int length) {
  const alphabet = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(length, (_) => alphabet[random.nextInt(alphabet.length)]).join();
}

/// Waits until one of this device's IPv4 addresses is in the subnet of
/// [hostIp], i.e. until DHCP on the joined network finished.
Future<String> waitForAddressInSubnet(String hostIp, {Duration timeout = const Duration(seconds: 20)}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.address != hostIp && isSameIpv4Subnet24(address.address, hostIp)) {
          return address.address;
        }
      }
    }
    if (DateTime.now().isAfter(deadline)) {
      throw const WifiLinkException('Joined the network but got no address on it');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

/// Android, iOS and macOS: implemented natively behind a method channel
/// (MainActivity / AppDelegate).
class _ChannelWifiLink extends WifiLink {
  static const _channel = MethodChannel('org.glideapp.glide/nearby_wifi');

  @override
  NearbyWifiCapabilities capabilities = NearbyWifiCapabilities.none;

  @override
  Future<void> init() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('capabilities');
      capabilities = NearbyWifiCapabilities(
        canHost: result?['canHost'] == true,
        canJoin: result?['canJoin'] == true,
        peerToPeer: result?['peerToPeer'] == true,
      );
    } on MissingPluginException {
      capabilities = NearbyWifiCapabilities.none;
    }
  }

  @override
  Future<HostedWifiNetwork> startHosting() async {
    final result = await _invoke<Map<Object?, Object?>>('startHosting');
    final ssid = result?['ssid'];
    final passphrase = result?['passphrase'];
    final ip = result?['ip'];
    if (ssid is! String || passphrase is! String || ip is! String) {
      throw const WifiLinkException('The Wi-Fi Direct group did not report its credentials');
    }
    return HostedWifiNetwork(ssid: ssid, passphrase: passphrase, ip: ip);
  }

  @override
  Future<void> stopHosting() => _invoke<void>('stopHosting');

  @override
  Future<String> join({required String ssid, required String passphrase, required String hostIp}) async {
    await _invoke<void>('join', {'ssid': ssid, 'passphrase': passphrase});
    return waitForAddressInSubnet(hostIp);
  }

  @override
  Future<void> leave() => _invoke<void>('leave');

  @override
  Future<void> advertisePeerToPeer({required String name, required int port}) =>
      _invoke<void>('advertisePeerToPeer', {'name': name, 'type': nearbyBonjourType, 'port': port});

  @override
  Future<void> stopAdvertisingPeerToPeer() => _invoke<void>('stopAdvertisingPeerToPeer');

  @override
  Future<String> resolvePeerToPeer({required String name}) async {
    final address = await _invoke<String>('resolvePeerToPeer', {'name': name, 'type': nearbyBonjourType});
    if (address == null) {
      throw WifiLinkException('$name has no peer-to-peer address');
    }
    return address;
  }

  @override
  Future<void> stopResolvingPeerToPeer() => _invoke<void>('stopResolvingPeerToPeer');

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw WifiLinkException(e.message ?? e.code);
    }
  }
}

/// Windows:
/// - joining uses a temporary, manually connecting WLAN profile on the first
///   wireless interface (wlanapi.dll). Deleting the profile disconnects, after
///   which Windows reconnects to the user's preferred network on its own.
/// - hosting starts a Wi-Fi Direct advertisement with legacy access point
///   settings (WinRT, in the runner's nearby_wifi.cpp), which iPhones, Macs
///   and other PCs join like a regular WPA2 network.
class _WindowsWifiLink extends WifiLink {
  static const _profileName = 'Glide Nearby';
  static const _channel = MethodChannel('org.glideapp.glide/nearby_wifi');

  @override
  NearbyWifiCapabilities capabilities = NearbyWifiCapabilities.none;

  /// The interface the profile was added to, while joined.
  String? _joinedInterface;

  HostedWifiNetwork? _hosted;

  @override
  Future<void> init() async {
    var canJoin = false;
    try {
      canJoin = _withClient((client) => _firstInterfaceGuid(client) != null);
    } catch (e) {
      _logger.info('No usable WLAN interface', e);
    }
    var canHost = false;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('capabilities');
      canHost = canJoin && result?['canHost'] == true;
    } on MissingPluginException {
      canHost = false;
    } on PlatformException catch (e) {
      _logger.info('Wi-Fi Direct hosting is not available', e);
    }
    capabilities = NearbyWifiCapabilities(canHost: canHost, canJoin: canJoin);
  }

  @override
  Future<HostedWifiNetwork> startHosting() async {
    final hosted = _hosted;
    if (hosted != null) {
      return hosted;
    }
    // The access point gets its own virtual adapter; its address is the one
    // that was not there before.
    final before = await _ipv4Addresses();
    final ssid = 'DIRECT-${_randomString(2)}-Glide';
    final passphrase = _randomString(12);
    try {
      await _channel.invokeMethod<void>('startHosting', {'ssid': ssid, 'passphrase': passphrase});
    } on PlatformException catch (e) {
      throw WifiLinkException(e.message ?? e.code);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (true) {
      final status = await _channel.invokeMapMethod<String, Object?>('hostingStatus');
      if (status?['status'] == 'aborted') {
        await _stopHostingNow();
        // WiFiDirectError: 1 = radio not available, 2 = resource in use.
        final reason = switch (status?['error']) {
          1 => 'the Wi-Fi adapter does not support Wi-Fi Direct or is turned off',
          2 => 'Wi-Fi Direct is in use by another app',
          final code => 'error $code',
        };
        throw WifiLinkException('Could not start the Wi-Fi Direct access point: $reason');
      }
      final added = (await _ipv4Addresses()).difference(before);
      if (added.isNotEmpty) {
        // Internet Connection Sharing's range, which the access point uses, first.
        final ip = added.firstWhere((a) => a.startsWith('192.168.137.'), orElse: () => added.first);
        return _hosted = HostedWifiNetwork(ssid: ssid, passphrase: passphrase, ip: ip);
      }
      if (DateTime.now().isAfter(deadline)) {
        await _stopHostingNow();
        throw const WifiLinkException('The Wi-Fi Direct access point got no address');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Future<void> stopHosting() async {
    if (_hosted == null) {
      return;
    }
    await _stopHostingNow();
  }

  Future<void> _stopHostingNow() async {
    _hosted = null;
    try {
      await _channel.invokeMethod<void>('stopHosting');
    } on PlatformException catch (e) {
      _logger.warning('Could not stop the Wi-Fi Direct access point', e);
    }
  }

  static Future<Set<String>> _ipv4Addresses() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return {for (final interface in interfaces) ...interface.addresses.map((a) => a.address)};
  }

  @override
  Future<String> join({required String ssid, required String passphrase, required String hostIp}) async {
    _withClient((client) {
      final guid = _firstInterfaceGuid(client);
      if (guid == null) {
        throw const WifiLinkException('No Wi-Fi adapter found');
      }
      final interfaceGuid = calloc<win32.GUID>();
      final profileXml = _profileXml(ssid: ssid, passphrase: passphrase).toNativeUtf16();
      final profileName = _profileName.toNativeUtf16();
      final reasonCode = calloc<Uint32>();
      final parameters = calloc<win32.WLAN_CONNECTION_PARAMETERS>();
      try {
        interfaceGuid.ref.setGUID(guid);
        _check(
          win32.WlanSetProfile(client, interfaceGuid, 0, profileXml, nullptr, win32.TRUE, nullptr, reasonCode),
          'WlanSetProfile (reason ${reasonCode.value})',
        );
        _joinedInterface = guid;
        parameters.ref
          ..wlanConnectionMode = win32.wlan_connection_mode_profile
          ..strProfile = profileName
          ..pDot11Ssid = nullptr
          ..pDesiredBssidList = nullptr
          ..dot11BssType = win32.dot11_BSS_type_infrastructure
          ..dwFlags = 0;
        _check(win32.WlanConnect(client, interfaceGuid, parameters, nullptr), 'WlanConnect');
      } finally {
        calloc.free(interfaceGuid);
        calloc.free(profileXml);
        calloc.free(profileName);
        calloc.free(reasonCode);
        calloc.free(parameters);
      }
    });
    // WlanConnect only starts the association; the address shows up once it
    // and DHCP completed.
    return waitForAddressInSubnet(hostIp, timeout: const Duration(seconds: 40));
  }

  @override
  Future<void> leave() async {
    final guid = _joinedInterface;
    if (guid == null) {
      return;
    }
    _joinedInterface = null;
    _withClient((client) {
      final interfaceGuid = calloc<win32.GUID>();
      final profileName = _profileName.toNativeUtf16();
      try {
        interfaceGuid.ref.setGUID(guid);
        win32.WlanDisconnect(client, interfaceGuid, nullptr);
        final result = win32.WlanDeleteProfile(client, interfaceGuid, profileName, nullptr);
        if (result != win32.ERROR_SUCCESS && result != win32.ERROR_NOT_FOUND) {
          _logger.warning('WlanDeleteProfile failed: $result');
        }
      } finally {
        calloc.free(interfaceGuid);
        calloc.free(profileName);
      }
    });
  }

  T _withClient<T>(T Function(int client) action) {
    final negotiatedVersion = calloc<Uint32>();
    final handle = calloc<IntPtr>();
    try {
      _check(win32.WlanOpenHandle(2, nullptr, negotiatedVersion, handle), 'WlanOpenHandle');
      try {
        return action(handle.value);
      } finally {
        win32.WlanCloseHandle(handle.value, nullptr);
      }
    } finally {
      calloc.free(negotiatedVersion);
      calloc.free(handle);
    }
  }

  String? _firstInterfaceGuid(int client) {
    final list = calloc<Pointer<win32.WLAN_INTERFACE_INFO_LIST>>();
    try {
      _check(win32.WlanEnumInterfaces(client, nullptr, list), 'WlanEnumInterfaces');
      try {
        if (list.value.ref.dwNumberOfItems == 0) {
          return null;
        }
        return list.value.ref.InterfaceInfo[0].InterfaceGuid.toString();
      } finally {
        win32.WlanFreeMemory(list.value);
      }
    } finally {
      calloc.free(list);
    }
  }

  static void _check(int result, String call) {
    if (result != win32.ERROR_SUCCESS) {
      throw WifiLinkException('$call failed with error $result');
    }
  }

  static String _profileXml({required String ssid, required String passphrase}) {
    return '''<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>${_xmlEscape(_profileName)}</name>
  <SSIDConfig><SSID><name>${_xmlEscape(ssid)}</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>manual</connectionMode>
  <MSM><security>
    <authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption>
    <sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>${_xmlEscape(passphrase)}</keyMaterial></sharedKey>
  </security></MSM>
</WLANProfile>''';
  }

  static String _xmlEscape(String value) =>
      value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
}

/// Linux, through NetworkManager (nmcli):
/// - joining adds the connection [_joinConnection], deleted on [leave];
/// - hosting turns the Wi-Fi adapter into a hotspot ([_hostConnection]),
///   deleted on [stopHosting].
/// Either way NetworkManager reconnects to the previous network afterwards.
class _LinuxWifiLink extends WifiLink {
  static const _joinConnection = 'glide-nearby';
  static const _hostConnection = 'glide-nearby-hotspot';

  @override
  NearbyWifiCapabilities capabilities = NearbyWifiCapabilities.none;

  /// The Wi-Fi device, e.g. `wlp2s0`.
  String? _device;
  bool _joined = false;
  HostedWifiNetwork? _hosted;

  @override
  Future<void> init() async {
    try {
      final devices = await _nmcli(['-t', '-f', 'DEVICE,TYPE', 'device']);
      _device = (devices.stdout as String)
          .split('\n')
          .map((line) => line.trim().split(':'))
          .where((parts) => parts.length == 2 && parts[1] == 'wifi')
          .map((parts) => parts[0])
          .firstOrNull;
      final device = _device;
      if (devices.exitCode != 0 || device == null) {
        _logger.info('nmcli reports no Wi-Fi device: ${devices.stderr}');
        capabilities = NearbyWifiCapabilities.none;
        return;
      }
      // Hotspots need an adapter that supports access point mode.
      final properties = await _nmcli(['-t', '-f', 'WIFI-PROPERTIES.AP', 'device', 'show', device]);
      final canHost = properties.exitCode == 0 && (properties.stdout as String).trim().endsWith(':yes');
      capabilities = NearbyWifiCapabilities(canHost: canHost, canJoin: true);
    } on ProcessException catch (e) {
      // NetworkManager is not installed.
      _logger.info('nmcli is not available', e);
      capabilities = NearbyWifiCapabilities.none;
    }
  }

  @override
  Future<HostedWifiNetwork> startHosting() async {
    final hosted = _hosted;
    if (hosted != null) {
      return hosted;
    }
    final device = _device;
    if (device == null || !capabilities.canHost) {
      throw const WifiLinkException('This Wi-Fi adapter cannot host a network');
    }
    final ssid = 'Glide-${_randomString(4)}';
    final passphrase = _randomString(12);
    await _nmcli(['connection', 'delete', _hostConnection]);
    final result = await _nmcli([
      '--wait',
      '30',
      'device',
      'wifi',
      'hotspot',
      'ifname',
      device,
      'con-name',
      _hostConnection,
      'ssid',
      ssid,
      'password',
      passphrase,
    ]);
    if (result.exitCode != 0) {
      await _nmcli(['connection', 'delete', _hostConnection]);
      throw WifiLinkException('nmcli could not start a hotspot: ${(result.stderr as String).trim()}');
    }
    // Shared mode assigns the adapter an address (10.42.0.1 by default).
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      final address = await _nmcli(['-g', 'IP4.ADDRESS', 'device', 'show', device]);
      final ip = (address.stdout as String).split('\n').first.split('/').first.trim();
      if (address.exitCode == 0 && ip.isNotEmpty) {
        return _hosted = HostedWifiNetwork(ssid: ssid, passphrase: passphrase, ip: ip);
      }
      if (DateTime.now().isAfter(deadline)) {
        await stopHostingNow();
        throw const WifiLinkException('The hotspot got no address');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Future<void> stopHosting() async {
    if (_hosted == null) {
      return;
    }
    await stopHostingNow();
  }

  Future<void> stopHostingNow() async {
    _hosted = null;
    final result = await _nmcli(['connection', 'delete', _hostConnection]);
    if (result.exitCode != 0) {
      _logger.warning('nmcli could not delete $_hostConnection: ${result.stderr}');
    }
  }

  @override
  Future<String> join({required String ssid, required String passphrase, required String hostIp}) async {
    // A stale connection from an interrupted transfer would make "connect" fail.
    await _nmcli(['connection', 'delete', _joinConnection]);
    // The network was created a moment ago and is usually not in the scan cache yet.
    await _nmcli(['device', 'wifi', 'rescan', 'ssid', ssid]);
    _joined = true;
    final result = await _nmcli(['--wait', '40', 'device', 'wifi', 'connect', ssid, 'password', passphrase, 'name', _joinConnection]);
    if (result.exitCode != 0) {
      await leave();
      throw WifiLinkException('nmcli could not join $ssid: ${(result.stderr as String).trim()}');
    }
    return waitForAddressInSubnet(hostIp);
  }

  @override
  Future<void> leave() async {
    if (!_joined) {
      return;
    }
    _joined = false;
    final result = await _nmcli(['connection', 'delete', _joinConnection]);
    if (result.exitCode != 0) {
      _logger.warning('nmcli could not delete $_joinConnection: ${result.stderr}');
    }
  }

  static Future<ProcessResult> _nmcli(List<String> arguments) => Process.run('nmcli', arguments);
}

class _UnsupportedWifiLink extends WifiLink {
  @override
  NearbyWifiCapabilities get capabilities => NearbyWifiCapabilities.none;

  @override
  Future<void> init() async {}

  @override
  Future<HostedWifiNetwork> startHosting() => throw const WifiLinkException('Not supported on this platform');

  @override
  Future<void> stopHosting() async {}

  @override
  Future<String> join({required String ssid, required String passphrase, required String hostIp}) =>
      throw const WifiLinkException('Not supported on this platform');

  @override
  Future<void> leave() async {}
}
