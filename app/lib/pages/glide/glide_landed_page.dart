// Landed (§3.3) and Failed (§3.7, derived from Landed). Shown after a send
// or receive finishes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:glide/config/glide_tokens.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/pages/glide/glide_home_page.dart';
import 'package:glide/provider/animation_provider.dart';
import 'package:glide/provider/network/send_provider.dart';
import 'package:glide/provider/selection/selected_sending_files_provider.dart';
import 'package:glide/util/native/open_file.dart';
import 'package:glide/util/native/open_folder.dart';
import 'package:glide/util/native/platform_check.dart';
import 'package:glide/widget/glide/glide_components.dart';
import 'package:glide/widget/glide/glide_icon.dart';
import 'package:glide/widget/glide/glide_transfer_widgets.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class GlideLandedPage extends StatelessWidget {
  final bool receiving;
  final bool success;
  final String thisDeviceLabel;
  final DeviceType thisDeviceType;
  final String? thisDeviceModel;
  final Device otherDevice;
  final String otherDeviceLabel;
  final String fileLabel;
  final String sizeLabel;
  final double? durationSeconds;
  final String? failureReason;
  final String? filePath;

  const GlideLandedPage({
    required this.receiving,
    required this.success,
    required this.thisDeviceLabel,
    required this.thisDeviceType,
    this.thisDeviceModel,
    required this.otherDevice,
    required this.otherDeviceLabel,
    required this.fileLabel,
    required this.sizeLabel,
    required this.durationSeconds,
    required this.failureReason,
    required this.filePath,
    super.key,
  });

  String get _headline {
    if (!success) {
      return t.glide.landed.transferFailed;
    }
    return receiving ? t.glide.landed.landedFrom(device: otherDeviceLabel) : t.glide.landed.landedOn(device: otherDeviceLabel);
  }

  String get _meta {
    if (success) {
      if (durationSeconds == null) {
        return t.glide.landed.metaSuccess(file: fileLabel, size: sizeLabel);
      }
      return t.glide.landed.metaSuccessWithDuration(file: fileLabel, size: sizeLabel, duration: durationSeconds!.toStringAsFixed(1));
    }
    return t.glide.landed.metaFailed(file: fileLabel, size: sizeLabel, reason: failureReason ?? t.glide.common.connectionLost);
  }

  Future<void> _primaryAction(BuildContext context) async {
    final ref = context.ref;
    if (!success) {
      // "Try again" (§3.7): only meaningful for a failed *send* - re-selects
      // the same files (still in selectedSendingFilesProvider, see
      // GlideSendingPage._navigateToResult) and starts a new session.
      if (!receiving) {
        final files = ref.read(selectedSendingFilesProvider);
        if (files.isNotEmpty) {
          await ref.notifier(sendProvider).startSession(target: otherDevice, files: files, background: false);
          return;
        }
      }
      context.global.dispatch(NavigateAction.popUntilRoot());
      return;
    }

    if (filePath == null || !context.mounted) {
      return;
    }
    if (receiving) {
      await openFile(context, FileType.other, filePath!);
    } else if (checkPlatformIsDesktop()) {
      await openFolder(folderPath: p.dirname(filePath!), fileName: p.basename(filePath!));
    } else {
      // No share-sheet dependency is available in this codebase; opening the
      // file lets the OS's own viewer offer a share/export action instead.
      await openFile(context, FileType.other, filePath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = !context.watch(animationProvider) || MediaQuery.of(context).disableAnimations;
    final isDesktop = MediaQuery.sizeOf(context).width >= 700;

    final leftType = receiving ? otherDevice.deviceType : thisDeviceType;
    final rightType = receiving ? thisDeviceType : otherDevice.deviceType;
    final leftModel = receiving ? otherDevice.deviceModel : thisDeviceModel;
    final rightModel = receiving ? thisDeviceModel : otherDevice.deviceModel;
    final leftLabel = receiving ? otherDeviceLabel : thisDeviceLabel;
    final rightLabel = receiving ? thisDeviceLabel : otherDeviceLabel;

    final primaryLabel = success ? (receiving ? t.general.open : t.glide.landed.showInFolder) : t.glide.landed.tryAgain;
    final secondaryLabel = success ? (receiving ? t.general.done : t.glide.landed.sendAnother) : t.glide.landed.backToHome;

    return Scaffold(
      backgroundColor: GT.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? GT.desktopMaxWidth : double.infinity),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(children: [_BackButton()]),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 56, 24, 0),
                          child: Column(
                            children: [
                              GlideResultRing(
                                kind: success ? GlideResultKind.success : GlideResultKind.failure,
                                reduceMotion: reduceMotion,
                              ),
                              const SizedBox(height: 22),
                              Text(_headline, style: GT.heroLarge, textAlign: TextAlign.center),
                              const SizedBox(height: 6),
                              Text(_meta, style: GT.secondary, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 26),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _RouteChip(type: leftType, deviceModel: leftModel, label: leftLabel),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: GlideIcon(GlideIconAsset.arrowRight, size: 16, color: success ? GT.success : GT.danger),
                              ),
                              _RouteChip(type: rightType, deviceModel: rightModel, label: rightLabel),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: Column(
                    children: [
                      GlidePrimaryButton(label: primaryLabel, onPressed: () => unawaited(_primaryAction(context))),
                      const SizedBox(height: 10),
                      GlideTextButton(
                        label: secondaryLabel,
                        onPressed: () => Routerino.context.pushRootImmediately(() => const GlideHomePage(appStart: false)),
                      ),
                    ],
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

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return GlideTopBarButton.back(
      onTap: () => context.global.dispatch(NavigateAction.popUntilRoot()),
      semanticLabel: t.general.back,
    );
  }
}

class _RouteChip extends StatelessWidget {
  final DeviceType type;
  final String? deviceModel;
  final String label;

  const _RouteChip({required this.type, this.deviceModel, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: GT.surface,
        border: Border.all(color: GT.border),
        borderRadius: BorderRadius.circular(GT.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlideIcon(deviceIconFor(type, deviceModel: deviceModel), size: 15, color: GT.textMuted),
          const SizedBox(width: 7),
          Text(label, style: GT.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
