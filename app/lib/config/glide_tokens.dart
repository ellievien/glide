// The Glide design system's tokens: colors, typography, radii, shadows and
// spacing, exactly as specified in glide-design/GLIDE_DESIGN_SPEC.md (§1).
//
// This is the *new* app UI (Home/Sending/Landed/Receiving/History/Settings)
// described in that spec. It is deliberately light-only (the spec is not
// designed for dark mode) and does not participate in the legacy
// LocalSend-era theming in `config/theme.dart` (color modes, dynamic colors,
// dark mode) which still powers the screens outside of this spec.
//
// Keep every color/radius/shadow/spacing value used by a Glide screen or
// component in this file and reference it from there - never hardcode a
// value inline in a screen.
library;

import 'package:flutter/material.dart';

/// Design tokens for the Glide UI. Short name ("GT") because these constants
/// are referenced constantly throughout the Glide screens/components.
abstract final class GT {
  GT._();

  // ---------------------------------------------------------------------
  // Colors (§1 Colors)
  // ---------------------------------------------------------------------

  static const Color blue = Color(0xFF355CF5);
  static const Color blueSoft = Color(0x1A355CF5); // rgba(53,92,245,0.10)
  static const Color blueTint = Color(0x1F355CF5); // rgba(53,92,245,0.12)
  static const Color ink = Color(0xFF11182F);
  static const Color textMuted = Color(0xFF5B6272);
  static const Color textFaint = Color(0xFF9AA0AE);
  static const Color bg = Color(0xFFF4F6FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0x1411182F); // rgba(17,24,47,0.08)
  static const Color borderStrong = Color(0x1F11182F); // rgba(17,24,47,0.12)
  static const Color neutralTint = Color(0x0D11182F); // rgba(17,24,47,0.05)
  static const Color track = Color(0x1411182F); // rgba(17,24,47,0.08)
  static const Color success = Color(0xFF1FAE6E);
  static const Color successSoft = Color(0x241FAE6E); // rgba(31,174,110,0.14)
  static const Color danger = Color(0xFFE6484B);
  static const Color dangerSoft = Color(0x1FE6484B); // rgba(230,72,75,0.12)

  // ---------------------------------------------------------------------
  // Typography (§1 Typography)
  // ---------------------------------------------------------------------

  static const _tabular = [FontFeature.tabularFigures()];

  static const TextStyle screenTitle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink);
  static const TextStyle barTitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink);
  static const TextStyle hero = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3, color: ink);
  static const TextStyle heroLarge = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ink);
  static const TextStyle bigNumber = TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: ink, fontFeatures: _tabular);
  static const TextStyle rowTitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink);
  static const TextStyle rowTitleDense = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink);
  static const TextStyle body = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: ink);
  static const TextStyle secondary = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: textMuted);
  static const TextStyle caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: textMuted);
  static const TextStyle captionFaint = TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: textFaint);
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: textFaint,
    letterSpacing: 0.96, // 0.08em of 12px
  );
  static const TextStyle nodeLabel = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textMuted);
  static const TextStyle buttonPrimary = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: surface);
  static const TextStyle buttonSecondary = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink);
  static const TextStyle pill = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: blue);

  /// Numbers that change (percent, speed, sizes, times) use tabular figures.
  static TextStyle tabular(TextStyle style) => style.copyWith(fontFeatures: _tabular);

  // ---------------------------------------------------------------------
  // Radii, shadows, spacing (§1 Radii, shadows, spacing)
  // ---------------------------------------------------------------------

  static const double radiusCard = 20;
  static const double radiusButton = 16;
  static const double radiusIconButton = 12;
  static const double radiusThumb = 12;
  static const double radiusChip = 10;
  static const double radiusAppIcon = 8;
  static const double radiusSheet = 28;
  static const double radiusPill = 999;

  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x0A11182F), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D11182F), blurRadius: 20, offset: Offset(0, 8)),
  ];
  static const List<BoxShadow> shadowIconButton = [BoxShadow(color: Color(0x0D11182F), blurRadius: 2, offset: Offset(0, 1))];
  static const List<BoxShadow> shadowPrimary = [BoxShadow(color: Color(0x52355CF5), blurRadius: 24, offset: Offset(0, 10))];
  static const List<BoxShadow> shadowNode = [BoxShadow(color: Color(0x1411182F), blurRadius: 14, offset: Offset(0, 4))];
  static const List<BoxShadow> shadowBadge = [BoxShadow(color: Color(0x2E355CF5), blurRadius: 24, offset: Offset(0, 8))];
  static const List<BoxShadow> shadowChip = [BoxShadow(color: Color(0x4D355CF5), blurRadius: 14, offset: Offset(0, 4))];
  static const List<BoxShadow> shadowSheet = [BoxShadow(color: Color(0x1A11182F), blurRadius: 30, offset: Offset(0, -8))];

  static const double screenPadding = 24;
  static const double topBarPaddingTop = 20;
  static const double topBarPaddingTopHome = 26;
  static const double cardPadding = 16;
  static const double rowPaddingVertical = 13.5;
  static const double cardGap = 12;

  /// Reference frame is 390x844 (mobile). Tablet/desktop centers the
  /// primary flow (Home, Sending, Landed, Failed) in a column this wide;
  /// History/Settings may grow to [desktopWideMaxWidth] (§8).
  static const double desktopMaxWidth = 480;
  static const double desktopWideMaxWidth = 640;
}
