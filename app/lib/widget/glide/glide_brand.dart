// Brand marks from glide-design/brand/, used verbatim (never recolored or
// redrawn - see §7 of the design spec).
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The full "Glide" wordmark (glide-design/brand/logo/glide-logo.svg).
/// Used in the Home top bar at 24px tall.
class GlideWordmark extends StatelessWidget {
  final double height;

  const GlideWordmark({required this.height, super.key});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/brand/glide/glide-logo.svg',
      height: height,
      semanticsLabel: 'Glide',
    );
  }
}

/// The Glide symbol mark (glide-design/brand/logo/glide-symbol.svg).
/// Used in the Home center badge and the Incoming sheet's backdrop mark.
class GlideSymbol extends StatelessWidget {
  final double width;
  final double opacity;

  const GlideSymbol({required this.width, this.opacity = 1, super.key});

  @override
  Widget build(BuildContext context) {
    final svg = SvgPicture.asset(
      'assets/brand/glide/glide-symbol.svg',
      width: width,
      semanticsLabel: 'Glide',
    );
    return opacity == 1 ? svg : Opacity(opacity: opacity, child: svg);
  }
}
