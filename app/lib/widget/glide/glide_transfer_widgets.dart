// File/device/progress components (§2 of the design spec): file thumbnail,
// progress bar, result ring, device node, center badge, bottom sheet shell
// and the plain device/file list row.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:glide/config/glide_tokens.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/widget/glide/glide_icon.dart';
import 'package:glide/widget/glide/glide_tap_target.dart';
import 'package:localsend_isolates/model/device.dart';

/// laptop/phone/desktop mapping (§2 Device-type icon mapping). The
/// underlying protocol only distinguishes mobile/desktop/web/headless/server
/// -- `deviceType` alone cannot tell a laptop from a desktop -- so this looks
/// for a laptop hint in [deviceModel] (the free-text model string the
/// protocol also carries, e.g. a Mac's real model name) and otherwise falls
/// back to `desktop`, matching the spec's "Unknown -> desktop" rule.
GlideIconAsset deviceIconFor(DeviceType type, {String? deviceModel}) {
  if (type == DeviceType.mobile) {
    return GlideIconAsset.phone;
  }
  return _looksLikeLaptop(deviceModel) ? GlideIconAsset.laptop : GlideIconAsset.desktop;
}

/// Common laptop product-line names that show up in a device's model string
/// (this device's own, via `device_info_plus` on macOS, or a peer's, as
/// broadcast over the protocol).
const _laptopModelHints = ['macbook', 'laptop', 'notebook', 'thinkpad'];

bool _looksLikeLaptop(String? deviceModel) {
  if (deviceModel == null) {
    return false;
  }
  final lower = deviceModel.toLowerCase();
  return _laptopModelHints.any(lower.contains);
}

/// 40x40, radius.thumb, blueTint background (or surface+border when sitting
/// on a tinted card, e.g. the Incoming sheet's file card).
class GlideFileThumbnail extends StatelessWidget {
  final bool onTintedCard;
  final double size;

  const GlideFileThumbnail({this.onTintedCard = false, this.size = 40, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onTintedCard ? GT.surface : GT.blueTint,
        borderRadius: BorderRadius.circular(GT.radiusThumb),
        border: onTintedCard ? Border.all(color: GT.border) : null,
      ),
      alignment: Alignment.center,
      child: GlideIcon(GlideIconAsset.file, size: size / 2, color: GT.blue),
    );
  }
}

/// height 8, radius.pill, track background; fill blue with the fillShimmer
/// animation (opacity 0.6 -> 1 -> 0.6, 1600ms ease-in-out infinite).
class GlideProgressBar extends StatefulWidget {
  final double progress; // 0..1
  final bool reduceMotion;

  const GlideProgressBar({required this.progress, required this.reduceMotion, super.key});

  @override
  State<GlideProgressBar> createState() => _GlideProgressBarState();
}

class _GlideProgressBarState extends State<GlideProgressBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(color: GT.track, borderRadius: BorderRadius.circular(GT.radiusPill)),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widget.progress.clamp(0, 1),
        child: widget.reduceMotion
            ? DecoratedBox(
                decoration: BoxDecoration(color: GT.blue, borderRadius: BorderRadius.circular(GT.radiusPill)),
              )
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: 0.6 + (_controller.value * 0.4),
                    child: child,
                  );
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(color: GT.blue, borderRadius: BorderRadius.circular(GT.radiusPill)),
                ),
              ),
      ),
    );
  }
}

enum GlideResultKind { success, failure }

/// 96px result ring (Landed/Failed), animated with landBounce.
class GlideResultRing extends StatefulWidget {
  final GlideResultKind kind;
  final bool reduceMotion;

  const GlideResultRing({required this.kind, required this.reduceMotion, super.key});

  @override
  State<GlideResultRing> createState() => _GlideResultRingState();
}

class _GlideResultRingState extends State<GlideResultRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      _controller.value = 1;
    } else {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) {
          unawaited(_controller.forward());
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final success = widget.kind == GlideResultKind.success;
    final ringColor = success ? GT.successSoft : GT.dangerSoft;
    final iconColor = success ? GT.success : GT.danger;

    final ring = Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(color: ringColor, shape: BoxShape.circle),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          GlideIcon(GlideIconAsset.file, size: 34, color: iconColor),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
                border: Border.all(color: GT.bg, width: 3),
              ),
              alignment: Alignment.center,
              child: success
                  ? GlideIcon(GlideIconAsset.check, size: 14, color: GT.surface)
                  : const Text(
                      '!',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: GT.surface, height: 1),
                    ),
            ),
          ),
        ],
      ),
    );

    if (widget.reduceMotion) {
      return ring;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final double scale;
        final double opacity;
        if (t <= 0.55) {
          scale = _lerp(0.6, 1.08, t / 0.55);
        } else if (t <= 0.80) {
          scale = _lerp(1.08, 0.96, (t - 0.55) / 0.25);
        } else {
          scale = _lerp(0.96, 1.0, (t - 0.80) / 0.20);
        }
        opacity = t < 0.05 ? _lerp(0, 1, t / 0.05) : 1;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: ring,
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

/// 44px device node on the Home radar: surface/border/shadow.node, 18px blue
/// device icon, a nodeLabel below. The whole node is one tappable control.
/// Runs the `nodeAppear` entrance once and fades out over 200ms when
/// [visible] turns false (the caller keeps it mounted until then).
class GlideDeviceNode extends StatefulWidget {
  final DeviceType deviceType;
  final String? deviceModel;
  final String label;
  final VoidCallback onTap;
  final bool visible;
  final bool reduceMotion;

  /// Overrides the default "Send to {label}" accessibility label - used
  /// when a file is already queued, e.g. "Send photo.png to Pixel 9" (§3.1,
  /// "OS share sheet -> Home with file queued").
  final String? semanticLabel;

  const GlideDeviceNode({
    required this.deviceType,
    this.deviceModel,
    required this.label,
    required this.onTap,
    required this.visible,
    required this.reduceMotion,
    this.semanticLabel,
    super.key,
  });

  @override
  State<GlideDeviceNode> createState() => _GlideDeviceNodeState();
}

class _GlideDeviceNodeState extends State<GlideDeviceNode> with SingleTickerProviderStateMixin {
  late final AnimationController _appear = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      _appear.value = 1;
    } else {
      unawaited(_appear.forward());
    }
  }

  @override
  void dispose() {
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = Semantics(
      button: true,
      label: widget.semanticLabel ?? t.glide.common.sendTo(device: widget.label),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: ExcludeSemantics(
          child: AnimatedScale(
            scale: _pressed ? 0.94 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: GT.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: GT.border),
                    boxShadow: GT.shadowNode,
                  ),
                  alignment: Alignment.center,
                  child: GlideIcon(deviceIconFor(widget.deviceType, deviceModel: widget.deviceModel), size: 18, color: GT.blue),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 90,
                  child: Text(
                    widget.label,
                    style: GT.nodeLabel,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final appearAnimated = widget.reduceMotion
        ? node
        : AnimatedBuilder(
            animation: _appear,
            builder: (context, child) {
              // Curves.easeOutBack overshoots past 1.0 before settling,
              // approximating the spec's cubic-bezier(0.34, 1.56, 0.64, 1).
              final scale = 0.6 + 0.4 * Curves.easeOutBack.transform(_appear.value);
              return Opacity(
                opacity: _appear.value.clamp(0, 1),
                child: Transform.scale(scale: scale, child: child),
              );
            },
            child: node,
          );

    return AnimatedOpacity(
      opacity: widget.visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeIn,
      child: appearAnimated,
    );
  }
}

/// 96px circle center badge (Home). Shows the Glide symbol, or a
/// `network` icon in `textFaint` when offline (§3.1 Offline state).
class GlideCenterBadge extends StatelessWidget {
  final bool offline;
  final Widget symbol;

  const GlideCenterBadge({required this.offline, required this.symbol, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: const BoxDecoration(color: GT.surface, shape: BoxShape.circle, boxShadow: GT.shadowBadge),
      alignment: Alignment.center,
      child: offline ? GlideIcon(GlideIconAsset.network, size: 34, color: GT.textFaint) : symbol,
    );
  }
}

/// surface, top corners radius.sheet, shadow.sheet, padding 14 24 28, with
/// the 40x4 grabber centered 24px above the content.
class GlideBottomSheetShell extends StatelessWidget {
  final Widget child;

  const GlideBottomSheetShell({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: GT.surface,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(GT.radiusSheet), topRight: Radius.circular(GT.radiusSheet)),
        boxShadow: GT.shadowSheet,
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: GT.borderStrong, borderRadius: BorderRadius.circular(GT.radiusPill)),
            ),
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

/// The plain device/file list row (icon circle 44, title, subtitle,
/// trailing chevron). Used by the "+N" overflow device list.
class GlideListRow extends StatelessWidget {
  final GlideIconAsset icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const GlideListRow({required this.icon, required this.title, this.subtitle, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title, $subtitle',
      child: InkWell(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: GT.rowPaddingVertical),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: GT.blueTint, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: GlideIcon(icon, size: 22, color: GT.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: GT.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: GT.secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GlideIcon(GlideIconAsset.chevronRight, size: 16, color: GT.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 56px device circle used on the Sending screen's hero, and the smaller
/// route chips on Landed/Failed.
class GlideDeviceCircle extends StatelessWidget {
  final DeviceType deviceType;
  final String? deviceModel;
  final double size;
  final Color iconColor;

  const GlideDeviceCircle({required this.deviceType, this.deviceModel, this.size = 56, this.iconColor = GT.textMuted, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: GT.surface,
        shape: BoxShape.circle,
        border: Border.all(color: GT.border),
        boxShadow: GT.shadowIconButton,
      ),
      alignment: Alignment.center,
      child: GlideIcon(
        deviceIconFor(deviceType, deviceModel: deviceModel),
        size: size * (24 / 56),
        color: iconColor,
      ),
    );
  }
}

/// A minimum-hit-target wrapper for a whole row-like widget (e.g. the "You
/// are known as" chip's pencil button already uses [GlideTapTarget]
/// directly; this is exported for screens that need the same treatment for
/// arbitrary small controls).
Widget minHitTarget({required double size, required VoidCallback? onTap, required String label, required Widget child}) {
  return GlideTapTarget(visualSize: size, onTap: onTap, semanticLabel: label, child: child);
}
