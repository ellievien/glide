import 'dart:async';
import 'dart:io';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:glide/config/refena.dart';
import 'package:glide/config/theme.dart';
import 'package:glide/model/persistence/device_visibility.dart';
import 'package:glide/provider/animation_provider.dart';
import 'package:glide/provider/app_arguments_provider.dart';
import 'package:glide/provider/device_info_provider.dart';
import 'package:glide/provider/network/nearby_devices_provider.dart';
import 'package:glide/provider/network/server/server_provider.dart';
import 'package:glide/provider/network/webrtc/signaling_provider.dart';
import 'package:glide/provider/persistence_provider.dart';
import 'package:glide/provider/selection/selected_sending_files_provider.dart';
import 'package:glide/provider/settings_provider.dart';
import 'package:glide/provider/tv_provider.dart';
import 'package:glide/provider/window_dimensions_provider.dart';
import 'package:glide/util/i18n.dart';
import 'package:glide/util/native/autostart_helper.dart';
import 'package:glide/util/native/cache_helper.dart';
import 'package:glide/util/native/channel/android_channel.dart';
import 'package:glide/util/native/context_menu_helper.dart';
import 'package:glide/util/native/cross_file_converters.dart';
import 'package:glide/util/native/device_info_helper.dart';
import 'package:glide/util/native/macos_channel.dart';
import 'package:glide/util/native/platform_check.dart';
import 'package:glide/util/native/tray_helper.dart';
import 'package:glide/util/notification_strings.dart';
import 'package:glide/util/ui/dynamic_colors.dart';
import 'package:glide/util/ui/snackbar.dart';
import 'package:glide/widget/dialogs/local_network_dialog.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/dto/multicast_dto.dart';
import 'package:localsend_isolates/rust/api/logging.dart' as rust_logging;
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:localsend_isolates/util/logger.dart';
import 'package:localsend_isolates/util/show_instance.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:share_handler/share_handler.dart';
import 'package:window_manager/window_manager.dart';

final _logger = Logger('Init');

/// Will be called before the MaterialApp started
Future<RefenaContainer> preInit(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  initLogger(args.contains('-v') || args.contains('--verbose') ? Level.ALL : Level.INFO);
  MapperContainer.globals.use(const FileDtoMapper());

  await RustLib.init();

  if (kDebugMode) {
    try {
      await rust_logging.enableDebugLogging();
    } catch (e) {
      _logger.warning('Enabling debug logging failed', e);
    }
  }

  final dynamicColors = await getDynamicColors();

  final persistenceService = await PersistenceService.initialize(
    supportsDynamicColors: dynamicColors != null,
  );

  if (persistenceService.isFirstAppStart && !persistenceService.isPortableMode()) {
    await enableContextMenu();
  }

  await initI18n();

  TransferNotification.init(notificationStrings);

  bool startHidden = false;
  if (checkPlatformIsDesktop()) {
    // Check if this app is already open and let it "show up".
    // If this is the case, then exit the current instance.

    final handedOver = await notifyRunningInstance(
      securityContext: persistenceService.getSecurityContext(),
      port: persistenceService.getPort(),
      https: persistenceService.isHttps(),
      showToken: persistenceService.getShowToken(),
      args: args,
    );
    if (handedOver) {
      exit(0); // Another instance does exist
    }

    // initialize tray AFTER i18n has been initialized
    try {
      await initTray();
    } catch (e) {
      _logger.warning('Initializing tray failed: $e');
    }

    // initialize size and position
    await WindowManager.instance.ensureInitialized();
    await WindowDimensionsController(persistenceService).initDimensionsConfiguration();
    if (args.contains(startHiddenFlag)) {
      // keep this app hidden
      startHidden = true;
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      startHidden = await isLaunchedAsLoginItem() && await getLaunchAtLoginMinimized();
    }

    if (startHidden) {
      unawaited(hideToTray());
    } else {
      unawaited(showFromTray());
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await setupStatusBar();
    }
  }

  setDefaultRouteTransition();

  final container = RefenaContainer(
    observers: kDebugMode ? [CustomRefenaObserver()] : [],
    overrides: [
      persistenceProvider.overrideWithValue(persistenceService),
      deviceRawInfoProvider.overrideWithValue(await getDeviceInfo()),
      appArgumentsProvider.overrideWithValue(args),
      tvProvider.overrideWithValue(await checkIfTv()),
      dynamicColorsProvider.overrideWithValue(dynamicColors),
      sleepProvider.overrideWithInitialState((ref) => startHidden),
    ],
    platformHint: RefenaScope.getPlatformHint(), // help Refena know the correct platform
  );

  // compatibility for Routerino. TODO: Remove Routerino
  Routerino.navigatorKey = container.read(navigationProvider).key;

  // initialize multi-threading
  await container.set(
    parentIsolateProvider.overrideWithNotifier((ref) {
      final settings = ref.read(settingsProvider);
      return IsolateController(
        initialState: ParentIsolateState.initial(
          SyncState(
            rootIsolateToken: RootIsolateToken.instance!,
            securityContext: persistenceService.getSecurityContext(),
            deviceInfo: ref.read(deviceInfoProvider),
            alias: settings.alias,
            port: settings.port,
            networkWhitelist: settings.networkWhitelist,
            networkBlacklist: settings.networkBlacklist,
            protocol: settings.https ? ProtocolType.https : ProtocolType.http,
            multicastGroup: settings.multicastGroup,
            discoveryTimeout: settings.discoveryTimeout,
            serverRunning: true,
            download: false,
            discoverable: persistenceService.getVisibility() != DeviceVisibility.hidden,
          ),
        ),
      );
    }),
  );

  await container.redux(parentIsolateProvider).dispatchAsync(IsolateSetupAction());

  return container;
}

StreamSubscription? _sharedMediaSubscription;

/// Will be called when home page has been initialized
Future<void> postInit(BuildContext context, Ref ref, bool appStart) async {
  await updateSystemOverlayStyle(context);

  if (checkPlatform([TargetPlatform.android])) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e) {
      _logger.warning('Setting high refresh rate failed', e);
    }

    // Android 17+ blocks multicast discovery and LAN connections until this permission is granted,
    // so ask before the server and discovery start.
    final localNetworkGranted = await requestLocalNetworkPermissionAndroid();
    if (!localNetworkGranted) {
      _logger.warning('Local network permission denied. Discovery and transfers may not work.');
      if (context.mounted) {
        await context.pushBottomSheet(() => const LocalNetworkDialog());
      }
    }
  }

  try {
    await ref.notifier(serverProvider).startServerFromSettings();
  } catch (e) {
    if (context.mounted) {
      context.showSnackBar(e.toString());
    }
  }

  try {
    ref.redux(nearbyDevicesProvider).dispatchAsync(StartDiscoveryListener()); // ignore: unawaited_futures
  } catch (e) {
    _logger.warning('Starting discovery listener failed', e);
  }

  // ignore: dead_code
  if (webRTCEnabled) {
    ref.redux(signalingProvider).dispatch(SetupSignalingConnection());
  }

  if (appStart) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      // handle dropped files
      pendingFilesStream.listen((files) async {
        await ref.global.dispatchAsync(
          _HandleAppStartArgumentsAction(
            args: files,
          ),
        );
      });

      // handle dropped strings
      pendingStringsStream.listen((pendingStrings) {
        for (final string in pendingStrings) {
          ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: string));
        }
      });

      await setupMethodCallHandler();
    } else {
      final args = ref.read(appArgumentsProvider);
      await ref.global.dispatchAsync(
        _HandleAppStartArgumentsAction(
          args: args,
        ),
      );
    }
  }

  bool hasInitialShare = false;

  if (checkPlatformCanReceiveShareIntent()) {
    final shareHandler = ShareHandlerPlatform.instance;

    if (appStart) {
      final initialSharedPayload = await shareHandler.getInitialSharedMedia();
      if (initialSharedPayload != null) {
        hasInitialShare = true;
        // ignore: unawaited_futures
        ref.global.dispatchAsync(
          _HandleShareIntentAction(
            payload: initialSharedPayload,
          ),
        );
      }
    }

    _sharedMediaSubscription?.cancel(); // ignore: unawaited_futures
    _sharedMediaSubscription = shareHandler.sharedMediaStream.listen((SharedMedia payload) async {
      await ref.global.dispatchAsync(
        _HandleShareIntentAction(
          payload: payload,
        ),
      );
    });

    if (checkPlatform([TargetPlatform.android])) {
      // Both messages above travel through the same messenger in order, so the stream is
      // guaranteed to be attached natively before MainActivity replays held-back intents.
      await flushPendingShareIntentsAndroid();
    }
  }

  if (appStart && !hasInitialShare && (checkPlatformWithGallery() || checkPlatformCanReceiveShareIntent())) {
    // Clear cache on every app start.
    // If we received a share intent, then don't clear it, otherwise the shared file will be lost.
    ref.global.dispatchAsync(ClearCacheAction()); // ignore: unawaited_futures
  }
}

class _HandleShareIntentAction extends AsyncGlobalAction {
  final SharedMedia payload;

  _HandleShareIntentAction({
    required this.payload,
  });

  @override
  Future<void> reduce() async {
    final message = payload.content;
    if (message != null && message.trim().isNotEmpty) {
      ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: message));
    }
    await ref
        .redux(selectedSendingFilesProvider)
        .dispatchAsync(
          AddFilesAction(
            files: payload.attachments?.where((a) => a != null).cast<SharedAttachment>() ?? <SharedAttachment>[],
            converter: CrossFileConverters.convertSharedAttachment,
          ),
        );
  }
}

class _HandleAppStartArgumentsAction extends AsyncGlobalAction {
  final List<String> args;

  _HandleAppStartArgumentsAction({
    required this.args,
  });

  @override
  Future<void> reduce() async {
    await ref.redux(selectedSendingFilesProvider).dispatchAsyncTakeResult(LoadSelectionFromArgsAction(args));
  }
}
