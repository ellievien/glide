import 'package:flutter/material.dart';

/// Wraps a small visual (e.g. a 24px pencil button) so it keeps its exact
/// layout footprint (needed for pixel-exact positioning) while still
/// exposing a minimum 44x44 tap/hit target, per §9.4 of the design spec.
///
/// The extra hit area is invisible and centered on the visual; it does not
/// change where the visual is painted or how much space it reserves in the
/// surrounding layout.
class GlideTapTarget extends StatelessWidget {
  static const double minSize = 44;

  final double visualSize;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool button;
  final Widget child;

  const GlideTapTarget({
    required this.visualSize,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.button = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hitSize = visualSize < minSize ? minSize : visualSize;
    return Semantics(
      button: button,
      label: semanticLabel,
      enabled: onTap != null,
      child: SizedBox(
        width: visualSize,
        height: visualSize,
        child: OverflowBox(
          minWidth: hitSize,
          minHeight: hitSize,
          maxWidth: hitSize,
          maxHeight: hitSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            excludeFromSemantics: true,
            child: Center(
              child: ExcludeSemantics(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
