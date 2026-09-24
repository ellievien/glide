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

const GITHUB_RELEASE_BASE = "https://github.com/ellievien/glide/releases/latest/download";

window.GLIDE_DOWNLOADS = [
  { platform: "ios", label: "App Store", url: "", version: "1.0.0", status: "coming-soon" },
  { platform: "macos", label: "Mac App Store", url: "", version: "1.0.0", status: "coming-soon" },
  { platform: "android", label: "Google Play", url: "", version: "1.0.0", status: "coming-soon" },
  { platform: "android", label: "APK (direct download)", url: `${GITHUB_RELEASE_BASE}/Glide-1.0.0-android-arm64v8.apk`, version: "1.0.0", status: "available" },
  { platform: "windows", label: "Installer (.exe)", url: `${GITHUB_RELEASE_BASE}/Glide-1.0.0-windows-x86-64.exe`, version: "1.0.0", status: "available" },
  { platform: "windows", label: "Portable (.zip)", url: `${GITHUB_RELEASE_BASE}/Glide-1.0.0-windows-x86-64.zip`, version: "1.0.0", status: "available" },
  { platform: "linux", label: "AppImage", url: `${GITHUB_RELEASE_BASE}/Glide-1.0.0-linux-x86-64.AppImage`, version: "1.0.0", status: "available" },
  { platform: "linux", label: ".deb package", url: `${GITHUB_RELEASE_BASE}/Glide-1.0.0-linux-x86-64.deb`, version: "1.0.0", status: "available" },
];
