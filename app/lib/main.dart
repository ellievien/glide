import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:glide/config/init.dart';
import 'package:glide/config/init_error.dart';
import 'package:glide/config/theme.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/model/persistence/color_mode.dart';
import 'package:glide/pages/glide/glide_home_page.dart';
import 'package:glide/provider/local_ip_provider.dart';
import 'package:glide/provider/network/server/server_provider.dart';
import 'package:glide/provider/settings_provider.dart';
import 'package:glide/util/native/platform_check.dart';
import 'package:glide/util/ui/dynamic_colors.dart';
import 'package:glide/widget/watcher/life_cycle_watcher.dart';
import 'package:glide/widget/watcher/shortcut_watcher.dart';
import 'package:glide/widget/watcher/tray_watcher.dart';
import 'package:glide/widget/watcher/window_watcher.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

Future<void> main(List<String> args) async {
  // GLIDE is a fork of LocalSend (https://github.com/localsend/localsend),
  // Apache License 2.0. This registers that attribution alongside the
  // auto-discovered dependency licenses shown on the in-app License
  // Notices screen (Settings > About).
  LicenseRegistry.addLicense(() {
    return Stream<LicenseEntry>.value(
      const LicenseEntryWithLineBreaks(
        <String>['glide'],
        'GLIDE is a fork of LocalSend (https://github.com/localsend/localsend), '
        'Copyright 2022-2026 Tien Do Nam and the LocalSend contributors, '
        'licensed under the Apache License, Version 2.0. See the NOTICE file '
        'in the GLIDE source distribution for details of what has changed. '
        'GLIDE is an independent project and is not affiliated with or '
        'endorsed by LocalSend.',
      ),
    );
  });

  final RefenaContainer container;
  try {
    container = await preInit(args);
  } catch (e, stackTrace) {
    showInitErrorApp(
      error: e,
      stackTrace: stackTrace,
    );
    return;
  }

  runApp(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: const GlideApp(),
      ),
    ),
  );
}

class GlideApp extends StatelessWidget {
  const GlideApp();

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final (themeMode, colorMode, customColor) = ref.watch(
      settingsProvider.select((settings) => (settings.theme, settings.colorMode, settings.customColor)),
    );
    final dynamicColors = ref.watch(dynamicColorsProvider);
    return TrayWatcher(
      child: WindowWatcher(
        child: LifeCycleWatcher(
          onChangedState: (AppLifecycleState state) {
            switch (state) {
              case AppLifecycleState.resumed:
                ref.redux(localIpProvider).dispatch(InitLocalIpAction());
                if (checkPlatform([TargetPlatform.iOS, TargetPlatform.android])) {
                  // The OS may have invalidated the sockets of the suspended app without any error ever reaching the accept loop.
                  // ignore: discarded_futures
                  ref.notifier(serverProvider).ensureRunning();
                }
                if (checkPlatform([TargetPlatform.iOS])) {
                  // The multicast sockets die the same silent way but cannot be probed, so always rebind them.
                  ref.redux(parentIsolateProvider).dispatch(IsolateDiscoveryRestartAction());
                }
                break;
              case AppLifecycleState.detached:
                // The main isolate is only exited when all child isolates are exited.
                // https://github.com/localsend/localsend/issues/1568
                ref.redux(parentIsolateProvider).dispatch(IsolateDisposeAction());
                break;
              default:
                break;
            }
          },
          child: ShortcutWatcher(
            child: MaterialApp(
              title: t.appName,
              locale: TranslationProvider.of(context).flutterLocale,
              supportedLocales: AppLocaleUtils.supportedLocales,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              debugShowCheckedModeBanner: false,
              theme: getTheme(colorMode, customColor, Brightness.light, dynamicColors),
              darkTheme: getTheme(colorMode, customColor, Brightness.dark, dynamicColors),
              themeMode: colorMode == ColorMode.oled ? ThemeMode.dark : themeMode,
              navigatorKey: context.read(navigationProvider).key,
              home: RouterinoHome(
                builder: () => const GlideHomePage(
                  appStart: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
