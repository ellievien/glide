import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:logging/logging.dart';

final _logger = Logger('DeviceName');

/// The name the user gave this device (the computer name on desktops, the
/// device name on phones), used as the alias other devices see. `null` when
/// the platform does not tell.
///
/// iOS 16 and later only report the model ("iPhone") unless the app has the
/// user-assigned-device-name entitlement; that is still better than a random
/// name and the user can rename it in the settings.
Future<String?> getDeviceName() async {
  try {
    final plugin = DeviceInfoPlugin();
    final String name;
    if (Platform.isAndroid) {
      name = (await plugin.androidInfo).name;
    } else if (Platform.isIOS) {
      name = (await plugin.iosInfo).name;
    } else if (Platform.isMacOS) {
      name = (await plugin.macOsInfo).computerName;
    } else if (Platform.isWindows) {
      name = (await plugin.windowsInfo).computerName;
    } else {
      name = Platform.localHostname;
    }
    final trimmed = name.trim();
    return trimmed.isEmpty || trimmed == 'localhost' ? null : trimmed;
  } catch (e) {
    _logger.warning('Could not read the device name', e);
    return null;
  }
}

/// Whether [alias] looks like one made by `generateRandomAlias` in the
/// current locale, i.e. the user never chose it.
bool isGeneratedAlias(String alias) {
  final adjectives = t.aliasGenerator.adjectives;
  final fruits = t.aliasGenerator.fruits;
  for (final adjective in adjectives) {
    for (final fruit in fruits) {
      if (t.aliasGenerator.combination(adjective: adjective, fruit: fruit) == alias) {
        return true;
      }
    }
  }
  return false;
}
