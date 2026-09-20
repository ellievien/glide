import 'dart:async';
import 'dart:io';

import 'package:glide/provider/favorites_provider.dart';
import 'package:glide/provider/local_ip_provider.dart';
import 'package:glide/provider/network/nearby_devices_provider.dart';
import 'package:glide/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Discovers devices in stages, cheapest first: multicast announcement and
/// favorite probes right away, http-based discovery on the subnets only when
/// nothing was confirmed within the grace period (immediately on iOS, where
/// multicast cannot work at all).
class StartSmartScan extends AsyncGlobalAction {
  /// Maximum number of interfaces to scan.
  /// If there are more interfaces, the first ones will be used or the user needs to select one.
  static const maxInterfaces = 3;

  @override
  Future<void> reduce() async {
    final favorites = ref.read(favoritesProvider);
    final settings = ref.read(settingsProvider);
    final networkInterfaces = ref.read(localIpProvider).localIps.take(maxInterfaces).toList();

    // iOS never answers a multicast announcement: the
    // com.apple.developer.networking.multicast entitlement is gated behind a
    // per-team approval from Apple that this team does not hold, so the socket
    // can neither announce nor join the group (see ios/Runner/Runner.entitlements).
    // Waiting out the grace period there only delays the http scan that has to
    // do the work anyway, so start it immediately.
    final grace = Platform.isIOS ? Duration.zero : const Duration(seconds: 1);

    await ref
        .redux(nearbyDevicesProvider)
        .dispatchAsync(
          StartStagedScan(
            favorites: favorites,
            interfaces: networkInterfaces,
            port: settings.port,
            https: settings.https,
            grace: grace,
          ),
        );
  }
}

/// HTTP based discovery on a fixed set of subnets.
class StartLegacySubnetScan extends AsyncGlobalAction {
  final List<String> subnets;

  StartLegacySubnetScan({
    required this.subnets,
  });

  @override
  Future<void> reduce() async {
    final settings = ref.read(settingsProvider);
    final port = settings.port;
    final https = settings.https;

    // send announcement in parallel
    ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());

    await Future.wait<void>([
      for (final subnet in subnets) ref.redux(nearbyDevicesProvider).dispatchAsync(StartLegacyScan(port: port, localIp: subnet, https: https)),
    ]);
  }
}
