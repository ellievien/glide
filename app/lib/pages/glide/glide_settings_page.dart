// Settings (§3.6): THIS DEVICE, VISIBILITY, TRANSFERS, ABOUT.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:glide/config/glide_tokens.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/model/persistence/device_visibility.dart';
import 'package:glide/pages/glide/glide_history_page.dart';
import 'package:glide/pages/glide/glide_rename_dialog.dart';
import 'package:glide/provider/device_info_provider.dart';
import 'package:glide/provider/device_visibility_provider.dart';
import 'package:glide/provider/settings_provider.dart';
import 'package:glide/provider/version_provider.dart';
import 'package:glide/util/native/directories.dart';
import 'package:glide/util/native/pick_directory_path.dart';
import 'package:glide/widget/glide/glide_components.dart';
import 'package:glide/widget/glide/glide_icon.dart';
import 'package:glide/widget/glide/glide_tap_target.dart';
import 'package:glide/widget/glide/glide_transfer_widgets.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class GlideSettingsPage extends StatelessWidget {
  const GlideSettingsPage({super.key});

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
                      Text(t.general.settings, style: GT.screenTitle),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: const [
                      _ThisDeviceSection(),
                      _VisibilitySection(),
                      _TransfersSection(),
                      _AboutSection(),
                      _Footer(),
                      SizedBox(height: 24),
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

class _ThisDeviceSection extends StatelessWidget {
  const _ThisDeviceSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      label: t.glide.settings.thisDevice,
      child: const _ThisDeviceCard(),
    );
  }
}

class _ThisDeviceCard extends StatelessWidget {
  const _ThisDeviceCard();

  @override
  Widget build(BuildContext context) {
    final alias = context.watch(settingsProvider.select((s) => s.alias));
    final deviceType = context.watch(deviceInfoProvider.select((s) => s.deviceType));
    final deviceModel = context.watch(deviceInfoProvider.select((s) => s.deviceModel));

    return GlideCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: GT.blueTint, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: GlideIcon(deviceIconFor(deviceType, deviceModel: deviceModel), size: 20, color: GT.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(alias, style: GT.rowTitleDense, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                GlideTapTarget(
                  visualSize: 30,
                  semanticLabel: t.glide.common.renameDevice,
                  onTap: () async => showDialog(context: context, builder: (_) => const GlideRenameDialog()),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    child: const GlideIcon(GlideIconAsset.pencil, size: 15, color: GT.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const GlideCardDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t.glide.settings.visibleAs, style: GT.secondary),
                Text(_platformSummary(deviceModel), style: GT.captionFaint),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _platformSummary(String? deviceModel) {
    if (kIsWeb) {
      return t.glide.settings.web;
    }
    final os = switch (defaultTargetPlatform) {
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.fuchsia => 'Fuchsia',
    };
    if (deviceModel != null && deviceModel.isNotEmpty) {
      return '$os · $deviceModel';
    }
    return os;
  }
}

class _VisibilitySection extends StatelessWidget {
  const _VisibilitySection();

  @override
  Widget build(BuildContext context) {
    final visibility = context.watch(deviceVisibilityProvider);

    return _Section(
      label: t.glide.settings.visibility,
      child: GlideCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final value in DeviceVisibility.values) ...[
              if (value != DeviceVisibility.values.first) const GlideCardDivider(),
              GlideRadioRow(
                label: value.label,
                selected: value == visibility,
                onTap: () => context.notifier(deviceVisibilityProvider).setVisibility(value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransfersSection extends StatelessWidget {
  const _TransfersSection();

  @override
  Widget build(BuildContext context) {
    final destination = context.watch(settingsProvider.select((s) => s.destination));
    final quickSave = context.watch(settingsProvider.select((s) => s.quickSave));
    final saveToHistory = context.watch(settingsProvider.select((s) => s.saveToHistory));
    final askBeforeAccepting = !quickSave;

    return _Section(
      label: t.glide.settings.transfers,
      child: GlideCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              onTap: () async {
                final path = await pickDirectoryPath();
                if (path != null) {
                  // ignore: use_build_context_synchronously
                  await context.notifier(settingsProvider).setDestination(path);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const GlideIcon(GlideIconAsset.folder, size: 18, color: GT.textMuted),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t.glide.settings.saveTo, style: GT.body)),
                    Flexible(
                      child: FutureBuilder<String>(
                        future: destination == null ? getDefaultDestinationDirectory() : Future.value(destination),
                        builder: (context, snapshot) {
                          final path = destination ?? snapshot.data;
                          final label = path == null ? '…' : p.basename(path);
                          return Text(label, style: GT.captionFaint, maxLines: 1, overflow: TextOverflow.ellipsis);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    const GlideIcon(GlideIconAsset.chevronRight, size: 14, color: GT.textFaint),
                  ],
                ),
              ),
            ),
            const GlideCardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(t.glide.settings.askBeforeAccepting, style: GT.body),
                  GlideToggle(
                    value: askBeforeAccepting,
                    semanticLabel: t.glide.settings.askBeforeAccepting,
                    onChanged: (value) => context.notifier(settingsProvider).setQuickSave(!value),
                  ),
                ],
              ),
            ),
            const GlideCardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // History's entry point here is hidden (falls back to plain
                  // text) when history-keeping is off (§3.5 "Entry point").
                  saveToHistory
                      ? GlideTextButtonLike(
                          label: t.glide.settings.keepTransferHistory,
                          onTap: () async => context.push(() => const GlideHistoryPage()),
                        )
                      : Text(t.glide.settings.keepTransferHistory, style: GT.body),
                  GlideToggle(
                    value: saveToHistory,
                    semanticLabel: t.glide.settings.keepTransferHistory,
                    onChanged: (value) => context.notifier(settingsProvider).setSaveToHistory(value),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label used where a settings row's text also opens something (here:
/// History, reachable from Settings per §3.5 "Entry point").
///
/// Sitting next to a toggle with the same text style as every other
/// non-interactive row label left this indistinguishable from plain text --
/// nothing hinted that it was the only way to reach the history list, so it
/// went unnoticed. A trailing chevron, matching the "Save to" row above,
/// signals that this label specifically opens something.
class GlideTextButtonLike extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const GlideTextButtonLike({required this.label, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: GT.body),
          const SizedBox(width: 4),
          const GlideIcon(GlideIconAsset.chevronRight, size: 12, color: GT.textFaint),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      label: t.glide.settings.about,
      child: GlideCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(GT.radiusAppIcon),
                    child: Image.asset('assets/brand/glide/glide-icon-rounded-1024.png', width: 30, height: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t.glide.settings.version, style: GT.body)),
                  Consumer(
                    builder: (context, ref) {
                      final version = ref.watch(versionProvider);
                      return version.maybeWhen(
                        data: (data) => Text(data.combinedString, style: GT.captionFaint),
                        orElse: () => const Text('…', style: GT.captionFaint),
                      );
                    },
                  ),
                ],
              ),
            ),
            const GlideCardDivider(),
            InkWell(
              onTap: () async => context.push(() => const LicensePage()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(child: Text(t.glide.settings.licenseNotices, style: GT.body)),
                    const GlideIcon(GlideIconAsset.chevronRight, size: 14, color: GT.textFaint),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(GT.screenPadding, 14, GT.screenPadding, 0),
      child: Text(
        t.glide.settings.footer,
        style: GT.captionFaint,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final Widget child;

  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlideSectionLabel(label),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: GT.screenPadding),
          child: child,
        ),
      ],
    );
  }
}
