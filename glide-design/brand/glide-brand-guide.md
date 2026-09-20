# Glide visual identity

Two offset, curved file-like forms suggest a smooth handoff between devices. The broad silhouette and open diagonal gap preserve recognition as the mark gets smaller.

## Start here

- `logo/glide-logo.svg`: primary blue symbol and dark wordmark, transparent background, all vector paths.
- `logo/glide-logo.png`: transparent PNG at 1770 pixels wide.
- `logo/glide-logo-white.svg`: reversed logo for dark backgrounds.
- `logo/glide-logo-black.svg`: single-color logo.
- `logo/glide-symbol.svg`: standalone mark.
- `icons/glide-icon-1024.png`: full square, opaque source icon.
- `icons/glide-icon-rounded-1024.png`: rounded presentation/desktop icon with transparent corners.
- `icons/glide.ico`: Windows icon containing 16, 24, 32, 48, 64, 128 and 256 pixel images.
- `glide-brand-preview.png`: identity presentation.
- `glide-size-checks.png`: small-size and mask previews.

## Color and typography

| Role | Color |
| --- | --- |
| Glide Blue | #355CF5 |
| Ink | #11182F |
| White | #FFFFFF |
| Presentation background | #F4F6FB |

The wordmark is based on Segoe UI Bold with manually set spacing and converted to editable vector outlines. No font installation is needed to display the supplied SVGs. The package does not include font software. For ordinary application UI text, use the target platform's system font.

Use the blue/ink logo on light backgrounds and the white logo on dark or blue backgrounds. Retain the symbol's proportions and the open gap between its two forms. Avoid added outlines, rotation, or independent distortion of either form.

For standalone logo placement, leave at least one quarter of the visible symbol height as clear space around the logo. This is a recommended usage rule, not a platform requirement. App icon padding is already built into the supplied artwork.

The icon was visually checked at 16, 24, 32, 48, 64, 128 and 256 pixels. Prefer 24 pixels or larger when space allows; 16 pixels is supplied for favicons and small desktop surfaces. Check the full logo in its final context before shrinking it into dense UI.

## Platform assets and integration

### Windows

Use `icons/glide.ico` for modern Windows applications and shortcuts. The PNG-compressed ICO contains seven sizes. App integration and installer configuration have not been performed.

### Web

`web/` contains an SVG favicon, 180px Apple touch icon, 192px and 512px icons, and a starter web manifest. Set application-specific launch/scope settings when integrating the manifest. Its image paths are relative to the manifest. The square icons retain the main artwork within the central maskable area.

### Android

`layers/android/` contains editable foreground, background and monochrome SVGs, plus equivalent drawable XML and an adaptive-icon XML resource. Layers use a 108dp viewport. The visible foreground remains inside the central 66dp region. Circular and rounded-square crop previews were inspected.

Copy the drawable and mipmap resources into the corresponding application resource directories and connect the manifest icon entry to `@mipmap/glide`. Confirm resource compilation with the app's current Android toolchain and verify on devices. For older Android versions, generate density-specific legacy icons with Android Studio's Image Asset Studio using the supplied masters.

The 512px square PNG is suitable source artwork for a Google Play listing. Check current listing requirements at submission.

### Apple

`layers/apple/` contains separate unmasked background and transparent foreground artwork in SVG and 1024px PNG formats. The square 1024px icon is also included. These are source assets for Icon Composer/Xcode, not a validated Icon Composer project or an app asset catalog.

Import the layers into the current Apple toolchain and check the required sizes, effects, and default/dark/clear/tinted appearances for each supported platform. The included dark icon is a visual starting point; clear and tinted variants have not been built or tested in Icon Composer. Let the platform apply its own mask rather than using the rounded desktop preview as an Apple source layer.

## Verification

- Inspected the final brand board and icon previews.
- Checked monochrome and reversed artwork, small sizes and simulated circle/rounded-square masks.
- Checked SVG/XML parsing, PNG sizes/alpha, ICO entries, and foreground safe-area bounds.
- Native app builds, OS appearance effects and store submission checks remain part of application integration.

## Reference specifications

- [Apple app icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Android adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)
- [Google Play listing icons](https://developer.android.com/distribute/google-play/resources/icon-design-specifications)

Platform references checked September 19, 2026. See `design-process.md` for the image-generation prompts and vector construction notes.