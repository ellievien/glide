// Glide downloads — THE ONLY FILE TO EDIT when a new release goes out.
//
// Each entry:
//   platform: "ios" | "macos" | "android" | "windows" | "linux"
//   label:    button text, e.g. "App Store", "Installer (.exe)"
//   url:      direct download / store URL. Leave "" until it's real.
//   version:  version string shown next to the button, e.g. "1.0.0". Optional.
//   status:   "available" | "coming-soon"
//             "coming-soon" always renders a disabled "Coming soon" button,
//             even if a url is set — flip to "available" once the url is live.
//
// Add or remove entries freely; the page (index.html) never needs to change.

window.GLIDE_DOWNLOADS = [
  { platform: "ios", label: "App Store", url: "", version: "1.0.0", status: "coming-soon" },
  { platform: "macos", label: "Mac App Store", url: "", version: "1.0.0", status: "coming-soon" },
  { platform: "android", label: "Google Play", url: "", version: "1.0.0", status: "coming-soon" },
  { platform: "android", label: "APK (direct download)", url: "", version: "1.0.0", status: "coming-soon" },
  { platform: "windows", label: "Installer (.exe)", url: "", version: "1.0.0", status: "coming-soon" },
  { platform: "windows", label: "Portable (.zip)", url: "", version: "1.0.0", status: "coming-soon" },
  { platform: "linux", label: "AppImage", url: "", version: "1.0.0", status: "coming-soon" },
  { platform: "linux", label: ".deb package", url: "", version: "1.0.0", status: "coming-soon" },
];
