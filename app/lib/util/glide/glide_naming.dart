import 'package:flutter/foundation.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/util/native/platform_check.dart';

/// Home radar node labels drop a long "{owner}'s {device}" prefix down to
/// just the device name (§3.1: "Ced's MacBook Pro" -> "MacBook Pro").
String shortDeviceName(String alias) {
  final match = RegExp(r"^.+?'s\s+(.+)$").firstMatch(alias);
  final shortened = match?.group(1)?.trim();
  if (shortened != null && shortened.isNotEmpty) {
    return shortened;
  }
  return alias;
}

/// The generic "This Mac" / "This PC" / "This Phone" label used for *this*
/// device on the Sending/Landed screens (§3.2, §3.3) - the reference always
/// shows a platform noun there, never this device's own alias.
String thisDeviceLabel() {
  if (checkPlatform([TargetPlatform.macOS])) {
    return t.glide.common.thisMac;
  }
  if (checkPlatform([TargetPlatform.windows, TargetPlatform.linux])) {
    return t.glide.common.thisPc;
  }
  if (checkPlatform([TargetPlatform.android, TargetPlatform.iOS])) {
    return t.glide.common.thisPhone;
  }
  return t.glide.common.thisDevice;
}
