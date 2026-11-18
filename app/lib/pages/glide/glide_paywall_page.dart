// Paywall: trial status, what the Full Version includes, and the way to buy / restore / enter a license key.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:glide/config/glide_tokens.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/provider/license_provider.dart';
import 'package:glide/widget/glide/glide_components.dart';
import 'package:glide/widget/glide/glide_icon.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

/// Short status line for settings, banner and paywall.
String licenseStatusText(LicenseState license) {
  if (license.isUnlocked) {
    return t.glide.license.statusUnlocked;
  }
  if (!license.trialUsed) {
    return t.glide.license.statusTrialNotStarted;
  }
  if (!license.trialActive) {
    return t.glide.license.statusTrialEnded;
  }
  final remaining = license.trialRemaining;
  if (remaining.inHours >= 24) {
    return t.glide.license.statusTrialDays(n: (remaining.inHours / 24).ceil());
  }
  if (remaining.inHours >= 1) {
    return t.glide.license.statusTrialHours(n: remaining.inHours);
  }
  return t.glide.license.statusTrialMinutes;
}

String? _noticeText(LicenseNotice? notice) {
  return switch (notice) {
    null => null,
    LicenseNotice.storeUnavailable => t.glide.license.storeUnavailable,
    LicenseNotice.productsUnavailable => t.glide.license.productsUnavailable,
    LicenseNotice.purchaseFailed => t.glide.license.purchaseFailed,
    LicenseNotice.nothingToRestore => t.glide.license.nothingToRestore,
    LicenseNotice.restored => t.glide.license.restored,
    LicenseNotice.invalidKey => t.glide.license.keyInvalid,
  };
}

class GlidePaywallPage extends StatefulWidget {
  const GlidePaywallPage({super.key});

  static bool _open = false;

  /// Opens the paywall unless it is already on screen.
  static Future<void> open() async {
    if (_open) {
      return;
    }
    _open = true;
    try {
      await Routerino.context.push(() => const GlidePaywallPage());
    } finally {
      _open = false;
    }
  }

  @override
  State<GlidePaywallPage> createState() => _GlidePaywallPageState();
}

class _GlidePaywallPageState extends State<GlidePaywallPage> with Refena {
  final _keyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    ref.notifier(licenseProvider).clearNotice();
    ref.notifier(licenseProvider).refresh();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _openCheckout() async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(glideStripeCheckoutUrl), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.glide.license.browserFailed)));
    }
  }

  Future<void> _submitKey() async {
    final ok = await ref.notifier(licenseProvider).submitLicenseKey(_keyController.text);
    if (ok) {
      _keyController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final license = ref.watch(licenseProvider);
    final notifier = ref.notifier(licenseProvider);
    final isApple = notifier.isApple;
    // An invalid key is shown on the text field itself.
    final notice = license.notice == LicenseNotice.invalidKey ? null : _noticeText(license.notice);

    final headline = license.isUnlocked
        ? t.glide.license.headlineUnlocked
        : license.trialActive
        ? t.glide.license.headlineTrial
        : license.trialUsed
        ? t.glide.license.headlineEnded
        : t.glide.license.headlineNotStarted;

    return Scaffold(
      backgroundColor: GT.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: GT.desktopMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, GT.topBarPaddingTop, 20, 0),
                  child: Row(
                    children: [
                      GlideTopBarButton.back(onTap: () => Navigator.of(context).pop(), semanticLabel: t.general.back),
                      const SizedBox(width: 12),
                      Text(t.glide.license.title, style: GT.screenTitle),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(GT.screenPadding, 24, GT.screenPadding, 24),
                    children: [
                      GlideCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(headline, style: GT.hero),
                            const SizedBox(height: 6),
                            Text(licenseStatusText(license), style: GT.secondary),
                            const SizedBox(height: 16),
                            const GlideCardDivider(),
                            const SizedBox(height: 14),
                            _Included(label: t.glide.license.includedSending),
                            const SizedBox(height: 10),
                            _Included(label: t.glide.license.includedReceiving),
                            const SizedBox(height: 10),
                            _Included(label: t.glide.license.includedOnce),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (!license.isUnlocked) ...[
                        if (isApple) ..._appleActions(license, notifier) else ..._otherActions(license),
                      ],
                      if (notice != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          notice,
                          style: GT.caption.copyWith(color: GT.blue),
                          textAlign: TextAlign.center,
                        ),
                      ],
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

  List<Widget> _appleActions(LicenseState license, LicenseNotifier notifier) {
    final buyLabel = license.fullPrice == null ? t.glide.license.buyFixed : t.glide.license.buyWithPrice(price: license.fullPrice!);
    return [
      // Before the trial has ever been started the trial is the primary action.
      if (!license.trialUsed) ...[
        GlidePrimaryButton(label: t.glide.license.startTrial, onPressed: license.busy ? null : () => unawaited(notifier.startTrial())),
        const SizedBox(height: 12),
        GlideOutlineButton(label: buyLabel, onPressed: license.busy ? () {} : () => unawaited(notifier.buyFull())),
      ] else
        GlidePrimaryButton(label: buyLabel, onPressed: license.busy ? null : () => unawaited(notifier.buyFull())),
      const SizedBox(height: 8),
      GlideTextButton(label: t.glide.license.restore, onPressed: () => unawaited(notifier.restorePurchases())),
    ];
  }

  List<Widget> _otherActions(LicenseState license) {
    return [
      GlidePrimaryButton(label: t.glide.license.buyFixed, onPressed: () => unawaited(_openCheckout())),
      const SizedBox(height: 24),
      GlideSectionLabel(t.glide.license.enterKey),
      Text(t.glide.license.keyHint, style: GT.caption),
      const SizedBox(height: 10),
      TextField(
        controller: _keyController,
        style: GT.body,
        minLines: 1,
        maxLines: 3,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) {
          if (license.notice != null) {
            ref.notifier(licenseProvider).clearNotice();
          }
        },
        decoration: InputDecoration(
          filled: true,
          fillColor: GT.surface,
          hintText: t.glide.license.keyField,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(GT.radiusButton), borderSide: BorderSide.none),
          errorText: license.notice == LicenseNotice.invalidKey ? t.glide.license.keyInvalid : null,
        ),
        onSubmitted: (_) => unawaited(_submitKey()),
      ),
      const SizedBox(height: 12),
      GlideOutlineButton(label: t.glide.license.keyUnlock, onPressed: () => unawaited(_submitKey())),
    ];
  }
}

class _Included extends StatelessWidget {
  final String label;

  const _Included({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const GlideIcon(GlideIconAsset.check, size: 16, color: GT.success),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: GT.body)),
      ],
    );
  }
}
