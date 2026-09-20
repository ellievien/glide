// The plain device list opened from the Home radar's "+N" overflow node
// (§3.1: "a 9th+ device is represented by one extra node showing '+N' that
// opens a plain device list").
import 'package:flutter/material.dart';
import 'package:glide/config/glide_tokens.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/util/glide/glide_naming.dart';
import 'package:glide/widget/glide/glide_components.dart';
import 'package:glide/widget/glide/glide_transfer_widgets.dart';
import 'package:localsend_isolates/model/device.dart';

class GlideDeviceListPage extends StatelessWidget {
  final List<Device> devices;
  final Future<void> Function(Device device) onDeviceTap;

  const GlideDeviceListPage({required this.devices, required this.onDeviceTap, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GT.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: GT.desktopWideMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, GT.topBarPaddingTop, 20, 0),
                  child: Row(
                    children: [
                      GlideTopBarButton.back(onTap: () => Navigator.of(context).pop(), semanticLabel: t.general.back),
                      const SizedBox(width: 12),
                      Text(t.glide.deviceList.title, style: GT.screenTitle),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: GT.screenPadding),
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return GlideListRow(
                        icon: deviceIconFor(device.deviceType, deviceModel: device.deviceModel),
                        title: shortDeviceName(device.alias),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await onDeviceTap(device);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
