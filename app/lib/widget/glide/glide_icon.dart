// The Glide UI icon set (glide-design/icons/*.svg), §7 of the design spec.
// 16 shapes on a 24x24 grid, round caps/joins, single stroke color.
// Render via this widget only - never restyle the paths.
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum GlideIconAsset {
  laptop('laptop'),
  phone('phone'),
  desktop('desktop'),
  file('file'),
  folder('folder'),
  chevronLeft('chevron-left'),
  chevronRight('chevron-right'),
  close('close'),
  search('search'),
  check('check'),
  arrowRight('arrow-right'),
  arrowUpRight('arrow-up-right'),
  arrowDownLeft('arrow-down-left'),
  pencil('pencil'),
  sliders('sliders'),
  network('network')
  ;

  const GlideIconAsset(this.fileName);

  final String fileName;

  String get assetPath => 'assets/icons/glide/$fileName.svg';
}

/// A single Glide UI icon, tinted to [color].
///
/// [GlideIconAsset.sliders] bakes its own stroke color (it always sits on a
/// light top-bar button, per the spec) and keeps its white-filled knobs, so
/// [color] is ignored for it.
class GlideIcon extends StatelessWidget {
  final GlideIconAsset asset;
  final double size;
  final Color color;

  const GlideIcon(this.asset, {required this.size, required this.color, super.key});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset.assetPath,
      width: size,
      height: size,
      colorFilter: asset == GlideIconAsset.sliders ? null : ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
