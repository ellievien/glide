import 'dart:io';
import 'package:glide/util/native/channel/android_channel.dart';
import 'package:glide/util/native/ios_channel.dart';
import 'package:glide/util/native/macos_channel.dart';

Future<bool> getSystemAnimationsStatus() async {
  if (Platform.isAndroid) {
    return await getSystemAnimationsStatusAndroid();
  } else if (Platform.isIOS) {
    bool isReduceMotionEnabledBool = await isReduceMotionEnabledIOS();
    return !isReduceMotionEnabledBool;
  } else if (Platform.isMacOS) {
    bool isReduceMotionEnabledBool = await isReduceMotionEnabledMacOs();
    return !isReduceMotionEnabledBool;
  }

  return true; // Default to true for other platforms.
}
