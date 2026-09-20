import 'package:glide/model/persistence/device_visibility.dart';
import 'package:glide/model/state/server/server_state.dart';
import 'package:glide/provider/network/server/server_provider.dart';
import 'package:glide/provider/persistence_provider.dart';
import 'package:glide/provider/settings_provider.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/dto/multicast_dto.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Settings > Visibility (§3.6). See the "Visibility" decision in the
/// implementation summary for what each value actually does.
final deviceVisibilityProvider = NotifierProvider<DeviceVisibilityService, DeviceVisibility>((ref) {
  return DeviceVisibilityService(ref.read(persistenceProvider));
});

class DeviceVisibilityService extends Notifier<DeviceVisibility> {
  final PersistenceService _persistence;

  DeviceVisibilityService(this._persistence);

  @override
  DeviceVisibility init() => _persistence.getVisibility();

  Future<void> setVisibility(DeviceVisibility visibility) async {
    await _persistence.setVisibility(visibility);
    state = visibility;

    // Discoverability is applied live: no server restart needed.
    final settings = ref.read(settingsProvider);
    final ServerState? server = ref.read(serverProvider);
    ref
        .redux(parentIsolateProvider)
        .dispatch(
          IsolateSyncServerStateAction(
            alias: server?.alias ?? settings.alias,
            port: server?.port ?? settings.port,
            protocol: (server?.https ?? settings.https) ? ProtocolType.https : ProtocolType.http,
            serverRunning: server != null,
            download: server?.webDownloadState != null,
            discoverable: visibility != DeviceVisibility.hidden,
          ),
        );
  }
}
