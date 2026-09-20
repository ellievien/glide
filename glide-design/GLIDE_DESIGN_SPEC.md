# Glide — UI implementation spec

This folder is the complete design hand-off for Glide's app UI. Nothing in it is implemented yet; the job is to build the app's UI so it matches this package.

**How to use this folder**

| Path | What it is | How to use it |
|---|---|---|
| `GLIDE_DESIGN_SPEC.md` | This document — tokens, components, every screen, states, motion | Read fully before writing code |
| `reference/01-home.html … 06-settings.html` | Pixel-exact reference for each screen (plain HTML + inline CSS, 390×844 mobile frame). Open in a browser; links between them work | **Source of truth for layout, sizes, colors, spacing.** When this document and a reference file disagree, the reference file wins |
| `icons/*.svg` | The 16-icon UI set (24×24, stroke = `currentColor`); `icons/_contact-sheet.html` previews them | Use these exact shapes; don't swap in another icon library |
| `brand/` | The Glide brand kit: logo/symbol/wordmark SVGs, app icons for every platform, brand guide | Use for the in-app logo, the center badge on Home, the About row, and every platform's app icon |

Product context: Glide is a cross-platform (Windows, macOS, Android, iOS, web) alternative to AirDrop. Devices on the same local network discover each other and send files directly, peer-to-peer — nothing goes through the cloud. The UI has one job: make "pick a device, send a file" feel instant and obvious.

---

## 1. Design tokens

Define these once in the project's theme/tokens layer (whatever the codebase uses) and reference them everywhere. Do not hardcode colors in screens.

### Colors

| Token | Value | Used for |
|---|---|---|
| `color.blue` | `#355CF5` | Brand blue — primary buttons, selected states, active icons, radar rings, links |
| `color.blueSoft` | `rgba(53,92,245,0.10)` | Status pill background |
| `color.blueTint` | `rgba(53,92,245,0.12)` | Icon-circle backgrounds |
| `color.ink` | `#11182F` | Primary text, dark icons |
| `color.textMuted` | `#5B6272` | Secondary text, neutral icons |
| `color.textFaint` | `#9AA0AE` | Section labels, timestamps, tertiary text, chevrons |
| `color.bg` | `#F4F6FB` | Screen background |
| `color.surface` | `#FFFFFF` | Cards, buttons, sheets, nodes |
| `color.border` | `rgba(17,24,47,0.08)` | Card/button hairline border, list dividers |
| `color.borderStrong` | `rgba(17,24,47,0.12)` | Outline-button border, sheet grabber |
| `color.neutralTint` | `rgba(17,24,47,0.05)` | Neutral icon-circle background (History rows, rename button) |
| `color.track` | `rgba(17,24,47,0.08)` | Progress-bar track |
| `color.success` | `#1FAE6E` | Delivered/received state |
| `color.successSoft` | `rgba(31,174,110,0.14)` | Success ring background |
| `color.danger` | `#E6484B` | Failed state, Decline |
| `color.dangerSoft` | `rgba(230,72,75,0.12)` | Failed icon-circle background |

No gradients anywhere. No other accent colors.

### Typography

Font: the platform's system UI font — `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif` on web; SF on Apple, Roboto on Android, Segoe UI on Windows. Do not load a webfont. Numbers that change (percent, speed, sizes, times) use tabular figures.

| Style | Size / weight / line-height | Where |
|---|---|---|
| `type.screenTitle` | 18 / 700 | Top-bar titles (History, Settings) |
| `type.barTitle` | 15 / 600 | Centered top-bar title when there are buttons on both sides (Sending) |
| `type.hero` | 20 / 700 / 1.3 | Home headline |
| `type.heroLarge` | 22 / 700 | Landed headline |
| `type.bigNumber` | 30 / 700, tabular | Progress percent |
| `type.rowTitle` | 15 / 600 (14 in dense lists) | Device/file names |
| `type.body` | 14 / 500 | Settings row labels |
| `type.secondary` | 13 / 400, `textMuted` | Subtitles, meta |
| `type.caption` | 12 / 400, `textMuted` or `textFaint` | Timestamps, helper text, footers |
| `type.sectionLabel` | 12 / 600, uppercase, letter-spacing 0.08em, `textFaint` | "TODAY", "VISIBILITY", … |
| `type.nodeLabel` | 11 / 600, `textMuted` | Label under a radar device node |
| `type.buttonPrimary` | 16 / 700 | Filled buttons |
| `type.buttonSecondary` | 15 / 600 | Outline and text buttons |
| `type.pill` | 13 / 600 | Status pills |

### Radii, shadows, spacing

| Token | Value |
|---|---|
| `radius.card` | 20 |
| `radius.button` | 16 |
| `radius.iconButton` | 12 |
| `radius.thumb` (file thumbnail square) | 12 |
| `radius.chip` (moving file chip) | 10 |
| `radius.appIcon` (30px About icon) | 8 |
| `radius.sheet` (top corners) | 28 |
| `radius.pill` / circles | 999 |
| `shadow.card` | `0 1px 2px rgba(17,24,47,0.04), 0 8px 20px rgba(17,24,47,0.05)` |
| `shadow.iconButton` | `0 1px 2px rgba(17,24,47,0.05)` |
| `shadow.primary` | `0 10px 24px rgba(53,92,245,0.32)` |
| `shadow.node` | `0 4px 14px rgba(17,24,47,0.08)` |
| `shadow.badge` (Home center) | `0 8px 24px rgba(53,92,245,0.18)` |
| `shadow.chip` (moving file chip) | `0 4px 14px rgba(53,92,245,0.30)` |
| `shadow.sheet` | `0 -8px 30px rgba(17,24,47,0.10)` |
| Screen side padding | 24 |
| Top-bar top padding | 20 (26 on Home) |
| Card padding | 16 |
| List row vertical padding | 13–14 |
| Gap between cards | 12 |
| Section label padding | 22 top, 6 bottom |

Reference frame is 390×844 (mobile). See §8 for desktop.

---

## 2. Components

Build these once and reuse them; every screen is composed from them.

**Top bar** — 36×36 icon buttons: `surface` background, `border` hairline, `radius.iconButton`, `shadow.iconButton`, 18px icon (16 for close). Back button icon is `chevron-left` in `ink`; other buttons `textMuted`. Left: back or logo. Center/left: title. Right: optional action.

**Card** — `surface`, `border`, `shadow.card`, `radius.card`, padding 16. Rows inside a card are separated by a 1px `border` divider inset 16px from each side.

**List row (device / file)** — icon circle 44 (`blueTint` background, 22px `blue` icon) · title `rowTitle` · subtitle `secondary` with 2px top margin · trailing `chevron-right` 16px `textFaint`. Dense variant (History): 36 circle, 14px icon, title 14/600, subtitle 12.

**Status pill** — `blueSoft` background, `blue` text `type.pill`, padding 7 14 7 10, `radius.pill`. Leading 8px `blue` dot with a 4px halo `rgba(53,92,245,0.16)`, 8px gap.

**Primary button** — height 56, `blue` background, white `buttonPrimary`, `radius.button`, `shadow.primary`. Optional leading 18px white icon with 10px gap. Pressed: scale 0.98, 120ms. Disabled: 40% opacity, no shadow.

**Outline button** — height 52, `surface`, `borderStrong` 1px, `ink` `buttonSecondary`, `radius.button`. Destructive variant: text `danger`.

**Text button** — `buttonSecondary`, `textMuted`, padding 12, no background.

**Toggle** — 42×24, `radius.pill`. On: `blue` track, 18px white thumb at right, 3px inset. Off: `borderStrong`-colored track (`rgba(17,24,47,0.12)`), thumb at left. Animate thumb 160ms ease-out.

**Radio** — 18px circle, 2px border. Selected: `blue` border + 8px `blue` dot. Unselected: border `rgba(17,24,47,0.16)`, empty. Selected row label `ink`, others `textMuted`.

**Section label** — `type.sectionLabel`, padding 22 24 6.

**Progress bar** — height 8, `radius.pill`, `track` background; fill `blue`, same radius, with the `fillShimmer` animation (§6).

**File thumbnail** — 40×40, `radius.thumb`, `blueTint` background (or `surface` + `border` when sitting on a tinted card), 20px `file` icon in `blue`.

**Device node (Home radar)** — 44px circle: `surface`, `border`, `shadow.node`, 18px `blue` device-type icon. `nodeLabel` 6px below, centered. The whole node is one tappable control labeled "Send to {device name}". Pressed: scale 0.94, 120ms.

**Center badge (Home)** — 96px circle, `surface`, `shadow.badge`, containing `brand/logo/glide-symbol.svg` at 38px wide.

**Bottom sheet** — `surface`, top corners `radius.sheet`, `shadow.sheet`, padding 14 24 28. Grabber 40×4, `borderStrong`, centered, 24px below it before content.

**Result ring (Landed / Failed)** — 96px circle, `successSoft` (or `dangerSoft`), 34px `file` icon in `success` (`danger`). 30px badge circle at bottom-right (−2px, −2px), `success` (`danger`) fill, 3px `bg`-colored border, 14px white `check` at stroke 3 (or a white "!" for failed).

**Device-type icon mapping** — laptop → `icons/laptop.svg`, phone/tablet → `icons/phone.svg`, desktop → `icons/desktop.svg`. Unknown → `desktop`.

---

## 3. Screens

Every screen: `bg` background, `ink` text, side padding 24, safe-area aware. Reference file named for each.

### 3.1 Home — `reference/01-home.html`

The discovery screen. A radar with this device at the center and nearby devices as nodes around it (the pattern Snapdrop uses).

Layout, top to bottom:

1. **Top bar** (padding 26 24 0): `brand/logo/glide-logo.svg` at 24px tall on the left; 36px `sliders` icon button on the right → opens Settings.
2. **Headline block** (padding 30 30 0, centered): `hero` "Open Glide on other devices to send files"; `secondary` 8px below, line-height 1.5, "Devices on the same network appear here automatically — nothing goes through the cloud."
3. **Radar** — fills all remaining vertical space; everything is centered on its midpoint:
   - 5 static rings, 1px `blue` borders, diameters 90 / 170 / 250 / 330 / 410, opacities 0.16 / 0.13 / 0.11 / 0.09 / 0.07 (inner → outer). The outer ring bleeds past the screen edge; that's intended.
   - 2 **ping rings**: 1.5px `blue` border, 410px, running `radarPing` (§6) — the second one offset by half a cycle so a pulse is always mid-flight.
   - **Center badge** (component above), z-index above rings.
   - **Device nodes**, one per discovered device, z-index above rings. Reference positions for 3 devices, as (dx, dy) from center: (−141, −100) laptop "MacBook Pro", (+141, −100) phone "Pixel 9", (0, +158) desktop "Windows PC".
   - **Dynamic placement rule** for any count *n*: place nodes at radius 160 from center, evenly spaced by angle, starting at 90° (straight down) and going clockwise; alternate the radius 160 / 172 on successive nodes so labels don't collide; never place a node within 70px of the center badge; cap at 8 visible nodes — a 9th+ device is represented by one extra node showing "+N" that opens a plain device list. Nodes animate in with `nodeAppear` (§6) when a device is discovered and fade out over 200ms when it leaves.
   - Label under each node is the device's short name (drop the owner prefix if it's long: "Ced's MacBook Pro" → "MacBook Pro").
   - Tapping a node goes to **Sending** for that device (file picker first if no file is queued; see §3.2).
4. **Identity block** (padding 0 24 36, centered, gap 14):
   - Row: `caption`-size text "You are known as" + a chip (`surface`, `border`, `shadow.iconButton`, `radius.pill`, padding 5 6 5 14, 13/600 `ink`) containing this device's name and a 24px round `neutralTint` button with a 12px `pencil` icon → rename (same action as Settings › This device). The row wraps to two lines if the name is long.
   - Below: status pill "Discoverable by {visibility}" where visibility is the current Settings › Visibility value in lowercase ("everyone nearby", "contacts only"). Hidden → pill reads "Hidden from nearby devices" with the dot in `textFaint`. Tapping the pill opens Settings › Visibility.

**States**
- *Empty (no devices yet)*: rings, pings and center badge only; no nodes. Subtext becomes "No one nearby yet — keep Glide open on the other device too."
- *Offline / no local-network permission*: rings at 50% opacity, pings stopped; center badge shows a 34px `network` icon in `textFaint` instead of the symbol; headline "Turn on Wi-Fi or Hotspot to find devices nearby"; subtext is a `blue` text link "Open Settings" (system network settings, or the permission prompt on iOS/Android). No nodes.
- *Hidden visibility*: radar still works for sending; the pill reflects it as above.

### 3.2 Sending — `reference/02-sending.html`

The transfer-in-progress screen. Motion is the hero here: the file visibly "glides" from this device to the other one.

1. **Top bar**: back button (left) · `barTitle` "Sending to {device}" (center) · 36px `close` button (right, cancels).
2. **Hero** (height 260, margin 8 24 0), coordinates within a 342×260 box:
   - Dashed path: `M40,140 Q171,60 302,140`, stroke `rgba(53,92,245,0.35)`, width 2, dash `1 9`, round caps.
   - Two 56px device circles (`surface`, `border`, `shadow.iconButton`, 24px `textMuted` device icon) at (12,112) [this device] and (274,112) [target]; `caption` labels centered 8px below each ("This Mac", "Pixel 9").
   - **File chip** 66×30, `radius.chip`, `surface`, 1.5px `blue` border, `shadow.chip`, containing a 12px `blue` `file` icon + the file extension (".zip") 10/600 `ink`. It travels along the path via the `glideMove` animation (§6).
   - **Echo chip**: identical but border `rgba(17,24,47,0.10)`, no shadow, label `textMuted`, scaled 0.82, running the same animation 260ms behind.
3. **File card** (margin 4 24 0): file thumbnail 40 (`blueTint`) · name 14/600 · size 12 `textMuted`.
4. **Progress block** (margin 20 24 0): `bigNumber` percent on the left, `secondary` "~3s left" on the right (baseline-aligned); progress bar 10px below; `secondary` "42.8 MB/s average" 8px below (tabular).
5. **Bottom**: outline button "Cancel transfer" (padding-bottom 28).

Multi-file sends: the chip label shows the current file's extension and the file card cycles through files; percent/time are for the whole batch.

**Flow**: enters from Home (node tap → OS file/share picker → this screen) or from the OS share sheet with files already attached. On completion → Landed. On error → Failed. Cancel → back to Home.

**Receiving progress** is this same screen mirrored: title "Receiving from {device}", the target device is on the left and this device on the right, and the chip travels right → left. Cancel button reads "Stop receiving".

### 3.3 Landed — `reference/03-landed.html`

Success screen shown for a completed send (and, with the text swapped, a completed receive).

1. **Top bar**: back button only.
2. **Result block** (padding 56 24 0, centered): result ring (success) animated with `landBounce` (§6); `heroLarge` "Landed on {device}" 22px below; `secondary` "{file} · {size} · in {duration}" 6px below.
3. **Route chips** (26px below, centered, gap 10): two chips (`surface`, `border`, `radius.pill`, padding 8 14, 15px `textMuted` device icon + `caption` name) joined by a 16px `arrow-right` in `success`.
4. **Bottom** (padding 0 24 28, gap 10): primary "Show in folder" (opens the OS file location / share sheet on mobile) · text button "Send another" → Home.

Received variant: headline "Landed from {device}", chips reversed, primary button "Open" (opens the file), text button "Done" → Home.

### 3.4 Incoming request — `reference/04-receiving.html`

Modal bottom sheet over a dimmed Home (on desktop: a centered dialog, §8). Appears when another device wants to send and "Ask before accepting" is on.

- Behind the sheet: `bg` screen with `brand/logo/glide-symbol.svg` at 20px tall, 55% opacity, at (24, 30). The real Home stays behind it, dimmed.
- **Sheet** (height 584, i.e. ~69% of the frame): grabber → sender row (56px `blueTint` circle with 24px `blue` device icon · name 16/600 · "wants to send you a file" `secondary`) → file card 22px below (`bg`-colored card: `rgba(17,24,47,0.06)` border, `radius.card`, padding 16; thumbnail 40 `surface` + `border`; name 14/600; "{size} · {count} photos" 12 `textMuted`) → trust line 18px below (16px `network` icon in `textFaint` + `caption` "Only devices on your network can see this") → buttons pinned to the bottom (gap 10): primary "Accept" · outline-destructive "Decline".
- Accept → Receiving progress (§3.2 mirrored) → Landed (received variant). Decline → sheet slides down, Home returns.
- Sheet enters with `sheetUp` (§6). If "Ask before accepting" is off, skip this screen and go straight to Receiving progress.

### 3.5 History — `reference/05-history.html`

1. **Top bar**: back · `screenTitle` "History" · 36px `search` button (right).
2. Grouped by day with section labels ("TODAY", "YESTERDAY", then dates).
3. **Rows** (dense list row, padding 13 0, `border` divider): 36px circle with `arrow-up-right` for sent / `arrow-down-left` for received (circle `neutralTint`, icon `textMuted`) · filename 14/600 · "to {device} · {size}" / "from {device} · {size}" 12 `textMuted` · right column: time 12 `textFaint` and a 6px status dot 6px below (`success`).
   - **Failed row**: circle `dangerSoft`, icon `danger`, subtitle "Failed · tap to retry" in `danger`, status dot `danger`. Tapping retries (→ Sending).
   - Tapping a successful row opens the file (received) or shows it in its folder (sent).
4. Empty state: 36px `arrow-up-right` circle centered with "No transfers yet" 14/600 and "Files you send and receive will show up here." `secondary`.
5. Search filters by filename and device name, inline, no separate screen.
6. Only shown when Settings › "Keep transfer history" is on; otherwise the entry point is hidden.

Entry point: a "History" item is reachable from Settings and from a long-press/secondary action on Home's top bar (platform-appropriate — e.g. a tab on mobile, a sidebar item on desktop; pick what matches the codebase's navigation).

### 3.6 Settings — `reference/06-settings.html`

Top bar: back · `screenTitle` "Settings". Four sections, each a section label + card:

- **THIS DEVICE** — row: 40px `blueTint` circle with 20px `blue` device icon · device name 14/600 · 30px transparent `pencil` button (`textMuted`) → inline rename. Divider. Row: "Visible as" 13 `textMuted` (left) · "{OS} · {chip/arch}" 13 `textFaint` (right).
- **VISIBILITY** — radio list: "Everyone nearby" · "Contacts only" · "Hidden". Selected row label 14/500 `ink`; others `textMuted`. Dividers between rows. This value drives the Home pill.
- **TRANSFERS** — row: 18px `folder` icon `textMuted` · "Save to" 14/500 · "Downloads/Glide" 13 `textFaint` · `chevron-right` 14 `textFaint` → folder picker. Row: "Ask before accepting" + toggle (default on). Row: "Keep transfer history" + toggle (default on).
- **ABOUT** — row: `brand/icons/glide-icon-rounded-1024.png` at 30×30, `radius.appIcon` · "Version" 14/500 · "{version}" 13 `textFaint`.
- Footer 14px below the last card: `caption` in `textFaint`, line-height 1.5: "Glide moves files directly between devices over your local network — nothing is uploaded to the cloud."

### 3.7 Failed transfer (no reference file — derive from Landed)

Same layout as Landed: result ring in the danger variant (badge shows a white "!" instead of the check), headline "Transfer failed", meta line "{file} · {size} · {short reason}" (e.g. "connection lost", "declined on Pixel 9", "not enough space"), route chips with the arrow in `danger`, primary "Try again" (→ Sending), text button "Back to Home". Use the same `landBounce` entrance.

---

## 4. Navigation map

```
Home ──(tap device node → file picker)──▶ Sending ──▶ Landed ──("Send another")──▶ Home
  │                                          │  └──▶ Failed ──("Try again")──▶ Sending
  │                                          └──(cancel)──▶ Home
  ├──(settings button / pill / pencil)──▶ Settings ──▶ History
  └──(incoming request)──▶ Incoming sheet ──(Accept)──▶ Receiving progress ──▶ Landed (received)
                                            └──(Decline)──▶ Home
OS share sheet ──▶ Home with file queued (nodes now say "Send {file} to …") ──▶ Sending
```

Back always returns to the previous screen; Landed/Failed's back goes to Home.

---

## 5. Copy

Use these strings verbatim (adapt device names, file names, numbers).

| Where | String |
|---|---|
| Home headline | Open Glide on other devices to send files |
| Home subtext | Devices on the same network appear here automatically — nothing goes through the cloud. |
| Home empty subtext | No one nearby yet — keep Glide open on the other device too. |
| Home offline headline / link | Turn on Wi-Fi or Hotspot to find devices nearby / Open Settings |
| Home identity | You are known as {device name} |
| Home pill | Discoverable by everyone nearby · Discoverable by contacts only · Hidden from nearby devices |
| Sending title / cancel | Sending to {device} / Cancel transfer |
| Receiving title / cancel | Receiving from {device} / Stop receiving |
| Progress | {n}% · ~{t}s left · {speed} MB/s average |
| Landed | Landed on {device} · {file} · {size} · in {t}s · Show in folder · Send another |
| Landed (received) | Landed from {device} · Open · Done |
| Failed | Transfer failed · Try again · Back to Home |
| Incoming | {device} wants to send you a file · Only devices on your network can see this · Accept · Decline |
| History | History · TODAY · YESTERDAY · to {device} · {size} · from {device} · {size} · Failed · tap to retry · No transfers yet |
| Settings | Settings · THIS DEVICE · Visible as · VISIBILITY · Everyone nearby · Contacts only · Hidden · TRANSFERS · Save to · Ask before accepting · Keep transfer history · ABOUT · Version |
| Settings footer | Glide moves files directly between devices over your local network — nothing is uploaded to the cloud. |

Tone: short, plain, no exclamation marks, no emoji. "Landed" is Glide's word for delivered — keep it.

---

## 6. Motion

Rules: micro-interactions 100–200ms; screen transitions 300–500ms; entering elements ease-out, leaving elements ease-in, moving elements ease-in-out. Each screen has exactly one "loud" animation (listed first below); everything else is quiet. Honor the OS reduced-motion setting: stop the looping animations (`radarPing`, `glideMove`, `fillShimmer`) and replace them with static states; keep only opacity fades ≤200ms.

| Name | Where | Spec |
|---|---|---|
| `radarPing` (loud, Home) | 2 ping rings | 3400ms, ease-out, infinite. 0%: scale 0.22, opacity 0.45 → 70%: opacity 0.10 → 100%: scale 1.0, opacity 0. Second ring has `animation-delay: −1700ms` (starts mid-cycle). |
| `nodeAppear` | Home device node on discovery | 320ms, cubic-bezier(0.34, 1.56, 0.64, 1): scale 0.6 → 1, opacity 0 → 1. |
| `glideMove` (loud, Sending) | File chip along the path | 2600ms, cubic-bezier(0.22, 0.61, 0.16, 1), infinite, along `M40,140 Q171,60 302,140` (CSS `offset-path` on web; a bezier path animation natively). 0%: distance 0%, opacity 0 · 6%: opacity 1 · 46%: distance 100%, opacity 1 · 54%: opacity 0 · 100%: distance 100%, opacity 0. Echo chip: same animation, `animation-delay: −260ms`, scale 0.82. Chip keeps its rotation (does not rotate with the path). |
| `fillShimmer` | Progress-bar fill | 1600ms, ease-in-out, infinite: opacity 0.6 → 1 → 0.6. |
| `landBounce` (loud, Landed/Failed) | Result ring | 560ms, cubic-bezier(0.34, 1.56, 0.64, 1), 80ms delay, fill both. 0%: scale 0.6, opacity 0 · 55%: scale 1.08, opacity 1 · 80%: scale 0.96 · 100%: scale 1. |
| `sheetUp` (loud, Incoming) | Bottom sheet | 350ms ease-out, translateY 100% → 0, with the backdrop fading to 40% ink over the same time. Dismiss: 250ms ease-in reversed. |
| Screen push | Home → Sending, Settings, History | 300ms ease-out; back 250ms ease-in. Use the platform's native push if the framework provides one. |
| Sending → Landed | Crossfade | 300ms; the Landed ring then runs `landBounce`. |
| Toggle / radio / pressed states | | 120–160ms ease-out. |

---

## 7. Icons and brand assets

**UI icons** — `icons/*.svg`, 16 shapes on a 24×24 grid, round caps and joins, `stroke: currentColor`, `fill: none`. Stroke widths are baked in per icon (1.75 for objects, 2 for chevrons/actions, 2.5 for the history arrows, 3 for the check). Render them at 12–24px as listed per component; never restyle the paths. `sliders.svg` has white-filled knobs that assume a white/light button behind it.

| Icon | Used for |
|---|---|
| `laptop`, `phone`, `desktop` | Device types everywhere |
| `file` | File thumbnails, chips, result rings |
| `folder` | Settings › Save to |
| `chevron-left` | Back |
| `chevron-right` | Row disclosure |
| `close` | Cancel (Sending top bar) |
| `search` | History |
| `check` | Landed badge |
| `arrow-right` | Primary "Send" affordances, Landed route chips |
| `arrow-up-right` / `arrow-down-left` | History sent / received |
| `pencil` | Rename device |
| `sliders` | Settings entry on Home |
| `network` | Trust line on Incoming, offline state on Home |

**Brand** — `brand/glide-brand-guide.md` is the authority on logo usage and clear space. In-app usage:

| Asset | Where |
|---|---|
| `brand/logo/glide-logo.svg` | Home top bar (24px tall). `glide-logo-white.svg` on dark surfaces if any are ever added |
| `brand/logo/glide-symbol.svg` | Home center badge (38px wide), Incoming backdrop mark (20px tall, 55%) |
| `brand/icons/glide-icon-rounded-1024.png` | Settings › About row (30px, radius 8) |
| `brand/icons/glide.ico`, `glide-icon-*.png` | Windows app icon / installer |
| `brand/layers/android/` | Android adaptive icon (background / foreground / monochrome) — drop into the res folders as-is |
| `brand/layers/apple/` | iOS / macOS app icon layers |
| `brand/web/` | PWA manifest, favicon, touch icons |

Don't redraw or recolor the logo, and don't add the AirDrop-style concentric-circle motif to the *logo* — the radar belongs to the Home screen only.

---

## 8. Platform and layout adaptation

- **Mobile (390–430 wide)**: exactly the reference. Respect safe areas (add them to the top-bar and bottom paddings).
- **Tablet / desktop windows**: keep the same components and sizes; center Home, Sending, Landed and Failed in a 480px-wide column; History and Settings may grow to 640px. The radar's rings may scale up to 1.3× on large windows; node radius scales with them. Incoming request becomes a centered dialog card (`radius.card` 28, max-width 420, same content) over a 40% ink backdrop. Minimum window 400×680.
- **Desktop-only affordances** (only if the codebase already has them): drag-and-drop a file onto a device node = send to that device; drop anywhere on the radar = pick the device next.
- **Dark mode**: not designed. Ship light only; don't invent a dark theme.

---

## 9. Implementation rules

1. **Look at the codebase first.** Find the existing screens, navigation, theming and state patterns and build with them. Don't switch frameworks or add a UI kit for this; the components in §2 are small enough to build directly. If the app has no UI yet, create the screens in the structure the framework recommends.
2. **Tokens in one place** (§1). Components in one place (§2). Screens compose them.
3. **Bind to real data.** Device list, names, visibility, progress, speed, history and settings all come from the app's actual services/state — no hardcoded "Pixel 9". Reference values are placeholders. The radar placement rule in §3.1 must work for 0…N devices.
4. **Accessibility**: every tappable thing is a real button/link with a label (device nodes: "Send to {name}"; toggles announce their state); minimum hit target 44×44 even where the visual is smaller (the 24px pencil, 30px rename, 36px top-bar buttons get an invisible larger hit area); text scales with the OS setting without breaking the layout; color is never the only signal (failed rows also say "Failed").
5. **Motion** exactly as §6, with reduced-motion handling. Prefer the platform's native animation APIs; on web use CSS keyframes (`offset-path` for the chip).
6. **Don't add** gradients, emoji, extra colors, custom fonts, drop-shadow-heavy cards, or any screen/element not in this spec. If something needed for the app to work isn't specified (e.g. a permission prompt, an update banner), build the simplest version using the tokens and components here and list it in the summary.
7. **Verify** by running the app and comparing each screen side by side with `reference/*.html` opened in a browser. Fix what differs.
8. **Don't ask questions.** Make reasonable decisions where the spec is silent, and finish with a short list of every decision you made and anything you couldn't do.
