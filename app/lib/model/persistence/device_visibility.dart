import 'package:glide/gen/strings.g.dart';

/// Settings > Visibility (§3.6 of the design spec). Not a concept the
/// LocalSend protocol has natively; see the "Visibility" decision in the
/// implementation summary for exactly what each value does.
enum DeviceVisibility {
  everyone,
  contactsOnly,
  hidden
  ;

  String get label {
    switch (this) {
      case DeviceVisibility.everyone:
        return t.glide.deviceVisibility.everyone;
      case DeviceVisibility.contactsOnly:
        return t.glide.deviceVisibility.contactsOnly;
      case DeviceVisibility.hidden:
        return t.glide.deviceVisibility.hidden;
    }
  }

  /// The Home pill text: "Discoverable by {visibility}" in lowercase, or
  /// the dedicated "Hidden from nearby devices" string.
  String get pillLabel {
    switch (this) {
      case DeviceVisibility.everyone:
        return t.glide.deviceVisibility.pillEveryone;
      case DeviceVisibility.contactsOnly:
        return t.glide.deviceVisibility.pillContactsOnly;
      case DeviceVisibility.hidden:
        return t.glide.deviceVisibility.pillHidden;
    }
  }
}
