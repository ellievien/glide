(function () {
  "use strict";

  // Small, on-brand stroke icons (same style as app/assets/icons/glide) used
  // as decorative platform badges — not vendor logos, so no trademark/asset
  // syncing needed when the icon set changes.
  var ICONS = {
    phone:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="7" y="2" width="10" height="20" rx="2.5"/><line x1="11" y1="18.5" x2="13" y2="18.5"/></svg>',
    laptop:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="12" rx="1.5"/><path d="M2 19h20"/></svg>',
    desktop:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="12" rx="1.5"/><line x1="8" y1="20" x2="16" y2="20"/><line x1="12" y1="16" x2="12" y2="20"/></svg>',
    terminal:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 9l3 3-3 3"/><path d="M13 15h4"/></svg>',
  };

  var PLATFORM_META = {
    ios: { name: "iOS", icon: ICONS.phone },
    macos: { name: "macOS", icon: ICONS.laptop },
    android: { name: "Android", icon: ICONS.phone },
    windows: { name: "Windows", icon: ICONS.desktop },
    linux: { name: "Linux", icon: ICONS.terminal },
  };

  var PLATFORM_ORDER = ["ios", "macos", "android", "windows", "linux"];

  function escapeHtml(str) {
    return String(str).replace(/[&<>"']/g, function (c) {
      return (
        { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
      );
    });
  }

  // iPadOS 13+ identifies as "MacIntel" with no distinguishing UA token, so
  // touch support is the only reliable signal to route it to the iOS/App
  // Store bucket instead of macOS.
  function detectPlatform() {
    var ua = navigator.userAgent || "";
    var plat = navigator.platform || "";
    var touch = (navigator.maxTouchPoints || 0) > 1;

    if (/iPhone|iPod/.test(ua)) return "ios";
    if (/iPad/.test(ua) || (plat === "MacIntel" && touch)) return "ios";
    if (/Android/.test(ua)) return "android";
    if (/Win/.test(plat) || /Windows/.test(ua)) return "windows";
    if (/Mac/.test(plat)) return "macos";
    if (/Linux/.test(plat) || /Linux/.test(ua)) return "linux";
    return null;
  }

  function groupDownloads(list) {
    var map = {};
    PLATFORM_ORDER.forEach(function (p) {
      map[p] = [];
    });
    (list || []).forEach(function (item) {
      if (map[item.platform]) map[item.platform].push(item);
    });
    return map;
  }

  function renderOption(item) {
    var available = item.status === "available" && item.url;
    var versionTag = item.version
      ? '<span class="version">v' + escapeHtml(item.version) + "</span>"
      : "";

    if (available) {
      return (
        '<a class="download-btn" href="' +
        escapeHtml(item.url) +
        '" rel="noopener"><span>' +
        escapeHtml(item.label) +
        "</span>" +
        versionTag +
        "</a>"
      );
    }

    return (
      '<span class="download-btn is-disabled" aria-disabled="true"><span>' +
      escapeHtml(item.label) +
      '</span><span class="coming-soon">Coming soon</span></span>'
    );
  }

  function renderDownloads(grouped) {
    var grid = document.getElementById("downloads-grid");
    if (!grid) return;

    var html = "";
    PLATFORM_ORDER.forEach(function (platform) {
      var items = grouped[platform];
      if (!items || !items.length) return;
      var meta = PLATFORM_META[platform];

      html +=
        '<article class="download-card" id="download-' +
        platform +
        '"><div class="download-card-icon" aria-hidden="true">' +
        meta.icon +
        "</div><h3>" +
        meta.name +
        '</h3><div class="download-options">' +
        items.map(renderOption).join("") +
        "</div></article>";
    });

    grid.innerHTML = html;
  }

  function renderHero(grouped) {
    var btn = document.getElementById("hero-primary-btn");
    if (!btn) return;

    var platform = detectPlatform();
    var items = platform ? grouped[platform] : null;

    if (!items || !items.length) {
      btn.textContent = "See all platforms";
      btn.href = "#downloads";
      btn.classList.remove("is-disabled");
      return;
    }

    var meta = PLATFORM_META[platform];
    var best = items.filter(function (i) {
      return i.status === "available" && i.url;
    })[0];

    if (best) {
      btn.href = best.url;
      btn.textContent = "Download for " + meta.name;
      btn.setAttribute("rel", "noopener");
      btn.classList.remove("is-disabled");
    } else {
      btn.href = "#download-" + platform;
      btn.textContent = "Coming soon for " + meta.name;
      btn.classList.add("is-disabled");
    }
  }

  function init() {
    var grouped = groupDownloads(window.GLIDE_DOWNLOADS);
    renderDownloads(grouped);
    renderHero(grouped);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
