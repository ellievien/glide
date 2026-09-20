import 'package:glide/widget/glide/glide_icon.dart';
import 'package:glide/widget/glide/glide_transfer_widgets.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:test/test.dart';

void main() {
  group('deviceIconFor', () {
    test('mobile is always phone, regardless of deviceModel', () {
      expect(deviceIconFor(DeviceType.mobile), GlideIconAsset.phone);
      expect(deviceIconFor(DeviceType.mobile, deviceModel: 'MacBook Pro'), GlideIconAsset.phone);
    });

    test('desktop without a laptop hint falls back to desktop', () {
      expect(deviceIconFor(DeviceType.desktop), GlideIconAsset.desktop);
      expect(deviceIconFor(DeviceType.desktop, deviceModel: null), GlideIconAsset.desktop);
      expect(deviceIconFor(DeviceType.desktop, deviceModel: 'macOS'), GlideIconAsset.desktop);
      expect(deviceIconFor(DeviceType.desktop, deviceModel: 'Windows'), GlideIconAsset.desktop);
      expect(deviceIconFor(DeviceType.desktop, deviceModel: 'iMac'), GlideIconAsset.desktop);
    });

    test('a laptop hint in deviceModel selects laptop for non-mobile types', () {
      expect(deviceIconFor(DeviceType.desktop, deviceModel: 'MacBook Pro'), GlideIconAsset.laptop);
      expect(deviceIconFor(DeviceType.desktop, deviceModel: 'MacBook Air (M2, 2022)'), GlideIconAsset.laptop);
      expect(deviceIconFor(DeviceType.desktop, deviceModel: 'ThinkPad X1 Carbon'), GlideIconAsset.laptop);
      expect(deviceIconFor(DeviceType.desktop, deviceModel: 'Some Gaming Notebook'), GlideIconAsset.laptop);
      expect(deviceIconFor(DeviceType.headless, deviceModel: 'laptop-server'), GlideIconAsset.laptop);
    });

    test('matching is case-insensitive', () {
      expect(deviceIconFor(DeviceType.desktop, deviceModel: 'MACBOOK PRO'), GlideIconAsset.laptop);
    });
  });
}
