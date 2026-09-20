// Reusable Glide UI components (§2 of the design spec). Screens compose
// these; nothing here hardcodes a screen-specific value.
import 'package:flutter/material.dart';
import 'package:glide/config/glide_tokens.dart';
import 'package:glide/widget/glide/glide_icon.dart';
import 'package:glide/widget/glide/glide_tap_target.dart';

/// A 36x36 top-bar icon button: surface background, border hairline,
/// radius.iconButton, shadow.iconButton. Back buttons use `ink`, other
/// buttons use `textMuted` (both overridable, e.g. close uses 16px icon).
class GlideTopBarButton extends StatelessWidget {
  final GlideIconAsset icon;
  final VoidCallback? onTap;
  final String semanticLabel;
  final Color color;
  final double iconSize;

  const GlideTopBarButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.color = GT.textMuted,
    this.iconSize = 18,
    super.key,
  });

  const GlideTopBarButton.back({required this.onTap, required this.semanticLabel, super.key})
    : icon = GlideIconAsset.chevronLeft,
      color = GT.ink,
      iconSize = 18;

  @override
  Widget build(BuildContext context) {
    return GlideTapTarget(
      visualSize: 36,
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: GT.surface,
          borderRadius: BorderRadius.circular(GT.radiusIconButton),
          border: Border.all(color: GT.border),
          boxShadow: GT.shadowIconButton,
        ),
        alignment: Alignment.center,
        child: GlideIcon(icon, size: iconSize, color: color),
      ),
    );
  }
}

/// A card: surface, border, shadow.card, radius.card.
class GlideCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GlideCard({required this.child, this.padding = const EdgeInsets.all(GT.cardPadding), super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GT.surface,
        borderRadius: BorderRadius.circular(GT.radiusCard),
        border: Border.all(color: GT.border),
        boxShadow: GT.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A 1px divider inset 16px from each side, used between rows inside a
/// [GlideCard].
class GlideCardDivider extends StatelessWidget {
  const GlideCardDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, thickness: 1, color: GT.border),
    );
  }
}

/// "TODAY", "VISIBILITY", etc.
class GlideSectionLabel extends StatelessWidget {
  final String label;

  const GlideSectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(GT.screenPadding, 22, GT.screenPadding, 6),
      child: Text(label.toUpperCase(), style: GT.sectionLabel),
    );
  }
}

/// blueSoft pill with a leading dot+halo, used for the Home discoverability
/// status and read-only elsewhere.
class GlideStatusPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color dotColor;

  const GlideStatusPill({required this.label, this.onTap, this.dotColor = GT.blue, super.key});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
      decoration: BoxDecoration(color: GT.blueSoft, borderRadius: BorderRadius.circular(GT.radiusPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.16), blurRadius: 0, spreadRadius: 4)],
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: GT.pill.copyWith(color: GT.blue)),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GT.radiusPill),
        child: ExcludeSemantics(child: content),
      ),
    );
  }
}

/// height 56, blue background, radius.button, shadow.primary. Optional
/// leading icon. Pressed: scale 0.98 in 120ms. Disabled: 40% opacity, no
/// shadow.
class GlidePrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final GlideIconAsset? icon;

  const GlidePrimaryButton({required this.label, required this.onPressed, this.icon, super.key});

  @override
  State<GlidePrimaryButton> createState() => _GlidePrimaryButtonState();
}

class _GlidePrimaryButtonState extends State<GlidePrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      label: widget.label,
      enabled: enabled,
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.4,
            duration: const Duration(milliseconds: 120),
            child: Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: GT.blue,
                borderRadius: BorderRadius.circular(GT.radiusButton),
                boxShadow: enabled ? GT.shadowPrimary : null,
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    GlideIcon(widget.icon!, size: 18, color: GT.surface),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      style: GT.buttonPrimary,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// height 52, surface, borderStrong 1px, radius.button. Destructive variant:
/// text `danger`.
class GlideOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  const GlideOutlineButton({required this.label, required this.onPressed, this.destructive = false, super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(GT.radiusButton),
        child: ExcludeSemantics(
          child: Container(
            height: 52,
            width: double.infinity,
            decoration: BoxDecoration(
              color: GT.surface,
              border: Border.all(color: GT.borderStrong),
              borderRadius: BorderRadius.circular(GT.radiusButton),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: GT.buttonSecondary.copyWith(color: destructive ? GT.danger : GT.ink),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// buttonSecondary, textMuted, padding 12, no background.
class GlideTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const GlideTextButton({required this.label, required this.onPressed, super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(GT.radiusButton),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              label,
              style: GT.buttonSecondary.copyWith(color: GT.textMuted),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

/// 42x24 toggle. On: blue track, thumb right. Off: borderStrong track,
/// thumb left. Thumb animates 160ms ease-out.
class GlideToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  const GlideToggle({required this.value, required this.onChanged, this.semanticLabel, super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: semanticLabel,
      enabled: onChanged != null,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 42,
            height: 24,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? GT.blue : GT.borderStrong,
              borderRadius: BorderRadius.circular(GT.radiusPill),
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 18,
              height: 18,
              decoration: const BoxDecoration(color: GT.surface, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// 18px circle radio. Selected: blue border + 8px blue dot.
class GlideRadioDot extends StatelessWidget {
  final bool selected;

  const GlideRadioDot({required this.selected, super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? GT.blue : const Color(0x2911182F), width: 2),
      ),
      alignment: Alignment.center,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 140),
        opacity: selected ? 1 : 0,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: GT.blue, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// A full radio row (used by Settings > Visibility): radio dot, label,
/// selected label is `ink`, others `textMuted`.
class GlideRadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const GlideRadioRow({required this.label, required this.selected, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: GT.rowPaddingVertical),
            child: Row(
              children: [
                GlideRadioDot(selected: selected),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: GT.body.copyWith(color: selected ? GT.ink : GT.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
