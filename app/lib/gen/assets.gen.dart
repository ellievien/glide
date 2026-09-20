// dart format width=150

/// GENERATED CODE - DO NOT MODIFY BY HAND
/// *****************************************************
///  FlutterGen
/// *****************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: deprecated_member_use,directives_ordering,implicit_dynamic_list_literal,unnecessary_import

import 'package:flutter/widgets.dart';

class $AssetsBrandGen {
  const $AssetsBrandGen();

  /// Directory path: assets/brand/glide
  $AssetsBrandGlideGen get glide => const $AssetsBrandGlideGen();
}

class $AssetsIconsGen {
  const $AssetsIconsGen();

  /// Directory path: assets/icons/glide
  $AssetsIconsGlideGen get glide => const $AssetsIconsGlideGen();
}

class $AssetsBrandGlideGen {
  const $AssetsBrandGlideGen();

  /// File path: assets/brand/glide/glide-icon-32.png
  AssetGenImage get glideIcon32 => const AssetGenImage('assets/brand/glide/glide-icon-32.png');

  /// File path: assets/brand/glide/glide-icon-rounded-1024.png
  AssetGenImage get glideIconRounded1024 => const AssetGenImage('assets/brand/glide/glide-icon-rounded-1024.png');

  /// File path: assets/brand/glide/glide-logo.svg
  String get glideLogo => 'assets/brand/glide/glide-logo.svg';

  /// File path: assets/brand/glide/glide-symbol.svg
  String get glideSymbol => 'assets/brand/glide/glide-symbol.svg';

  /// File path: assets/brand/glide/glide.ico
  String get glide => 'assets/brand/glide/glide.ico';

  /// List of all assets
  List<dynamic> get values => [glideIcon32, glideIconRounded1024, glideLogo, glideSymbol, glide];
}

class $AssetsIconsGlideGen {
  const $AssetsIconsGlideGen();

  /// File path: assets/icons/glide/arrow-down-left.svg
  String get arrowDownLeft => 'assets/icons/glide/arrow-down-left.svg';

  /// File path: assets/icons/glide/arrow-right.svg
  String get arrowRight => 'assets/icons/glide/arrow-right.svg';

  /// File path: assets/icons/glide/arrow-up-right.svg
  String get arrowUpRight => 'assets/icons/glide/arrow-up-right.svg';

  /// File path: assets/icons/glide/check.svg
  String get check => 'assets/icons/glide/check.svg';

  /// File path: assets/icons/glide/chevron-left.svg
  String get chevronLeft => 'assets/icons/glide/chevron-left.svg';

  /// File path: assets/icons/glide/chevron-right.svg
  String get chevronRight => 'assets/icons/glide/chevron-right.svg';

  /// File path: assets/icons/glide/close.svg
  String get close => 'assets/icons/glide/close.svg';

  /// File path: assets/icons/glide/desktop.svg
  String get desktop => 'assets/icons/glide/desktop.svg';

  /// File path: assets/icons/glide/file.svg
  String get file => 'assets/icons/glide/file.svg';

  /// File path: assets/icons/glide/folder.svg
  String get folder => 'assets/icons/glide/folder.svg';

  /// File path: assets/icons/glide/laptop.svg
  String get laptop => 'assets/icons/glide/laptop.svg';

  /// File path: assets/icons/glide/network.svg
  String get network => 'assets/icons/glide/network.svg';

  /// File path: assets/icons/glide/pencil.svg
  String get pencil => 'assets/icons/glide/pencil.svg';

  /// File path: assets/icons/glide/phone.svg
  String get phone => 'assets/icons/glide/phone.svg';

  /// File path: assets/icons/glide/search.svg
  String get search => 'assets/icons/glide/search.svg';

  /// File path: assets/icons/glide/sliders.svg
  String get sliders => 'assets/icons/glide/sliders.svg';

  /// List of all assets
  List<String> get values => [
    arrowDownLeft,
    arrowRight,
    arrowUpRight,
    check,
    chevronLeft,
    chevronRight,
    close,
    desktop,
    file,
    folder,
    laptop,
    network,
    pencil,
    phone,
    search,
    sliders,
  ];
}

abstract final class Assets {
  static const $AssetsBrandGen brand = $AssetsBrandGen();
  static const $AssetsIconsGen icons = $AssetsIconsGen();
}

class AssetGenImage {
  const AssetGenImage(this._assetName, {this.size, this.flavors = const {}, this.animation});

  final String _assetName;

  final Size? size;
  final Set<String> flavors;
  final AssetGenImageAnimation? animation;

  Image image({
    Key? key,
    AssetBundle? bundle,
    ImageFrameBuilder? frameBuilder,
    ImageErrorWidgetBuilder? errorBuilder,
    String? semanticLabel,
    bool excludeFromSemantics = false,
    double? scale,
    double? width,
    double? height,
    Color? color,
    Animation<double>? opacity,
    BlendMode? colorBlendMode,
    BoxFit? fit,
    AlignmentGeometry alignment = Alignment.center,
    ImageRepeat repeat = ImageRepeat.noRepeat,
    Rect? centerSlice,
    bool matchTextDirection = false,
    bool gaplessPlayback = true,
    bool isAntiAlias = false,
    String? package,
    FilterQuality filterQuality = FilterQuality.medium,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    return Image.asset(
      _assetName,
      key: key,
      bundle: bundle,
      frameBuilder: frameBuilder,
      errorBuilder: errorBuilder,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      scale: scale,
      width: width,
      height: height,
      color: color,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      gaplessPlayback: gaplessPlayback,
      isAntiAlias: isAntiAlias,
      package: package,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }

  ImageProvider provider({AssetBundle? bundle, String? package}) {
    return AssetImage(_assetName, bundle: bundle, package: package);
  }

  String get path => _assetName;

  String get keyName => _assetName;
}

class AssetGenImageAnimation {
  const AssetGenImageAnimation({required this.isAnimation, required this.duration, required this.frames});

  final bool isAnimation;
  final Duration duration;
  final int frames;
}
