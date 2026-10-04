# Harbour Redesign — Design Spec

**Date:** 2026-10-04
**Status:** Approved in brainstorming, pending written-spec review
**Scope:** Full visual + interaction redesign of BusBoard NL (iOS + Android): new brand (logo, icon, splash), a custom platform-neutral component kit, all screens, and the live map (incl. a new "follow a bus" mode).

## 1. Goals and constraints

**Intended outcome.** One custom design that looks and behaves the same on iOS and Android, reads as neither "Android" nor "iOS", and is easy for St. John's riders to relate to and understand at a glance.

**Success criteria**
- No Material/Cupertino-looking UI is visible on either platform; screenshots of the same screen on the iOS simulator and Android emulator match (allowing for status bar/safe-area differences).
- Riders can identify their next bus within ~2 seconds: route number and minutes dominate every arrival row.
- Wording mirrors what riders see on the street: route numbers, the stop number on the pole, destination signs.
- Light and dark mode both pass WCAG AA contrast for text.
- The app is clearly an independent product, not Metrobus's.

**Constraints**
- The app stays free; no monetization (project mission).
- **"Info, not brand":** use Metrobus *information* (route/stop numbers, names, schedules, live data, which is public open data), never Metrobus *brand identity*: no logo or wordmark, no brand colours as primary colours, no bus-livery graphics, no fonts of theirs, nothing implying an official app. Metrobus's published brand standards define primary `#4C466F` (PMS 5265) and an alternate green `#81B34F` (PMS 7489) "most frequently associated with our mobile application icon". BusBoard must stay clearly distinct from both, which is why it uses **no green brand colour**. Green is used only as the semantic "live/on time" colour.
- Feature set is unchanged except for the new **follow mode** on the map and the board→map link into it.

**Out of scope**
- The live-map "bus jumps back / identity hands off to the next bus" bug. It's a separate task, diagnosed from a scheduled live capture on 2026-10-05 (`tool/capture_raw_gtfsrt.dart`, report at `test/fixtures/timetrack/DIAGNOSIS_2026-10-05.md`). It should land before Phase 3 ships, because follow mode depends on stable bus identity.
- Store screenshots (redo after Phase 3).
- New features beyond follow mode.

## 2. Visual direction ("Harbour")

Signage-first with a light local warmth: a cream paper background, white rounded cards, soft "jellybean row" route colours, a navy ink, big bold minute numerals, and a light floating bottom bar.

Reference mockups (local, not committed): `.superpowers/brainstorm/34226-1791086335/content/` (`visual-direction.html` option B, `app-screens-v2.html`, `map-layout.html`, `bottom-bar.html` option C, `logo-cool-house-v7.html` lilac).

## 3. Brand assets

### 3.1 App icon / logo ("B2 · Bus on the street")
On a **Harbour Blue `#3E7CB1`** square:
- four row houses left→right **red `#D63B3B`, yellow `#F2C94C`, lilac `#C3A6EE`, green `#6FCF97`**, each with a pitched roof and one window (`#1C2A3A` at 45% opacity);
- in front, a **cream `#F7F2EA` side-view bus**: rounded body, four navy windows plus a door window, two navy wheels with cream hubs. No stripes or livery;
- above, a **cream map pin** with a navy dot, sitting over the third (lilac) house.

The geometry is the 100×100 SVG from `logo-cool-house-v7.html` (lilac card). It becomes a clean master at `assets/brand/busboard_icon.svg`, plus a foreground-only variant (no background square) for the Android adaptive icon and the splash.

### 3.2 Generated assets
- iOS app icon: 1024×1024 PNG, no alpha, generated from the master.
- Android adaptive icon: foreground = artwork on transparent (inside the 66% safe zone); background colour `#3E7CB1`. Legacy/round icons generated too.
- Play Store icon (512) and feature graphic (1024×500): artwork on Harbour Blue with the "BusBoard NL" wordmark in Figtree ExtraBold, cream.
- Splash (`flutter_native_splash`): background `#3E7CB1`, foreground artwork centred, including the Android 12 splash API.
- `pubspec.yaml` `flutter_launcher_icons` / `flutter_native_splash` sections updated (`adaptive_icon_background: "#3E7CB1"`, `color: "#3E7CB1"`). The old `#0277BD` assets are removed.

## 4. Design tokens (`BBTokens`)

All visual values live in a single `ThemeExtension<BBTokens>` (light + dark instances) under `lib/ui/kit/tokens.dart`. Widgets read tokens via `context.bb`; no raw hex values outside the tokens file.

### 4.1 Colour

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#F7F2EA` | `#0F1720` | page background |
| `surface` | `#FFFFFF` | `#18222E` | cards, nav bar, sheets |
| `surfaceSunken` | `#EFE7DA` | `#121B25` | segmented-control track, inputs |
| `line` | `#ECE4D8` | `#243140` | dividers, hairlines |
| `ink` | `#1C2A3A` | `#F2EDE4` | primary text |
| `muted` | `#5A6674` | `#8E9AA8` | secondary text |
| `brand` | `#3C79AE` | `#6FA6DA` | fills, active tab, primary button, your-stop ring (icon keeps `#3E7CB1`) |
| `onBrand` | `#FFFFFF` | `#0F1720` | text/icons on `brand` |
| `brandInk` | `#2C5F8E` | `#8DBBE6` | links and small brand-coloured text (AA on `bg`) |
| `brandSoft` | `#DCE8F4` | `#1D3348` | soft brand backgrounds, count chips |
| `live` | `#2BA36B` | `#4CC38A` | live dot only (not for small text) |
| `liveInk` | `#1B7048` | `#4CC38A` | "Live" labels and live pill text (AA on bg/surface/liveSoft) |
| `liveSoft` | `#DDF1E6` | `#16332A` | live pill background |
| `soon` | `#D9480F` | `#FF8A5B` | arrival ≤ 5 min |
| `warnBg` / `warnInk` | `#FDEBD3` / `#8A4B08` | `#3A2A14` / `#F5C27A` | detours, delays |
| `dangerBg` / `dangerInk` | `#FBD9D6` / `#9B1C1C` | `#3A1A1A` / `#F5A3A3` | no service, errors |

Any pairing used for text must meet WCAG AA (4.5:1, or 3:1 for text ≥ 18.66 px bold). `brand` on `bg` is **not** used for small text; that's what `brandInk` is for.

### 4.2 Route colours (`RoutePalette`)
Ten jellybean hues, each with `fill` (badge/pill, light), `fillDark` (badge/pill, dark), and `line` (route shape on map, both modes). Badge/pill text is always `#1C2A3A`.

| Hue | fill | fillDark | line |
|---|---|---|---|
| red | `#FFC9C2` | `#FFB3A8` | `#D63B3B` |
| orange | `#FFD9B8` | `#FFC28F` | `#E07A1F` |
| yellow | `#FBE7A6` | `#F5D97A` | `#C9A219` |
| lime | `#E2F0B0` | `#CFE58A` | `#7FA31F` |
| green | `#CFEEDB` | `#A6E3BF` | `#2E9E62` |
| teal | `#C4ECE8` | `#93DDD6` | `#1F8F86` |
| sky | `#CFE3FA` | `#A9CDF5` | `#3E7CB1` |
| indigo | `#D6DAFA` | `#B3BAF5` | `#4A57C9` |
| lilac | `#E3D6FA` | `#CDB6F5` | `#8656D1` |
| pink | `#FAD3E4` | `#F5B0CD` | `#C9417E` |

- Each current Metrobus route gets a hue in a hand-written table (`lib/ui/kit/route_palette.dart`), chosen so routes sharing corridors or terminals (e.g. MUN Centre, Avalon Mall, Downtown) get different hues. The implementation plan builds this table from `routes.txt`.
- Routes missing from the table get `hues[routeNumber % 10]`: deterministic and stable between launches.
- The **same route always has the same colour** on the board, map, stop picker and alerts.

### 4.3 Typography
- **Figtree** (SIL OFL), bundled under `assets/fonts/` in weights 400/500/600/700/800 and declared in `pubspec.yaml`. Never fetched at runtime. (The current theme names "Inter", which was never bundled, so today the app silently falls back to the system font.)
- Scale (size/weight): `display` 28/800 (−0.02em), `title` 22/800, `headline` 17/700, `body` 15/500, `label` 13/700, `caption` 12/500.
- `minutes` 26/800 with `FontFeature.tabularFigures()` (no jitter as numbers change); `minutesUnit` 11/600 `muted`.
- Respects the system text-scale factor. Layouts are verified at 1.0, 1.3 and 2.0.

### 4.4 Space, shape, depth, motion
- Spacing scale (4-pt): 4, 8, 12, 16, 20, 24, 32. Screen side padding 16.
- Radii: `pill` 8, `badge` 12, `card` 16, `sheet`/`bar` 24 (full pill for the nav bar's active tab).
- One shadow: `0 4 16 rgba(28,42,58,0.14)` light; dark mode uses a 1 px `line` border instead of a shadow.
- Motion: `standard` 200 ms easeOutCubic; sheets use a spring (critically damped, ~300 ms). With `MediaQuery.disableAnimations` everything snaps instantly.

## 5. Component kit (`lib/ui/kit/`)

**Rule:** Material/Cupertino widgets may be used **only inside `lib/ui/kit/`** as implementation plumbing. Screen code (`lib/ui/<feature>/`) uses kit widgets only. `MaterialApp.router` stays in `app.dart` as invisible infrastructure (routing, text selection, localizations, accessibility).

| Component | Purpose / notes |
|---|---|
| `BBTheme` | Builds `ThemeData` (with M3 visuals neutralised) plus `BBTokens` light/dark |
| `BBScaffold` | Page shell: `bg`, safe areas, bottom inset for the floating nav bar |
| `BBNavBar` | White floating pill bar (dark: `surface` + `line` border), active tab = full pill in `brand` with `onBrand` text, inactive = `muted`. Optional count badge (Alerts). Light haptic on change |
| `BBSheet` | Draggable sheet with detents (peek / half / full), spring snap, grab handle, haptic on snap. Used by the map and the bus/stop details |
| `BBCard` | `surface`, radius 16, padding 10–12, optional tap with a subtle press-scale (no ripple) |
| `BBButton` | `primary` (brand fill) and `quiet` (text in `brandInk`). Height 44, radius 14, press-scale |
| `BBPill` | Small label (status, alert type, route), tone variants (neutral/brand/warn/danger/route) |
| `RouteBadge` | 40×40 (board) / compact pill (lists, map), route `fill`, navy number |
| `BBSegmented` | Two-to-three option switch on a `surfaceSunken` track |
| `BBTextField` | Search/input on `surface`, radius 14, leading icon |
| `BBSwitch` | Custom toggle in brand colours |
| `BBToast` | Replaces `SnackBar`: floating, above the nav bar, auto-dismiss |
| `BBDialog` | Replaces `AlertDialog`: centred card, `BBButton`s |
| `BBRefresh` | Pull-to-refresh with a brand-coloured indicator |
| `BBIcon` set | One consistent rounded icon set (outline + filled), the same on both platforms |

### 5.1 Platform-neutral behaviour
- **Scrolling:** one global `ScrollBehavior` with `BouncingScrollPhysics` on both platforms and no Material glow/stretch.
- **Page transitions:** one shared transition (fade + 4% slide-up, 200 ms) on both platforms, while system back works on each: iOS edge-swipe back and Android (predictive) back.
- **No ripples/ink splashes**: interactive kit widgets use a press-scale (0.98) + opacity.
- **Haptics:** `selectionClick` on tab change, segmented change and sheet snap, on both platforms.
- **Status bar / system nav bar:** icon brightness follows the theme; edge-to-edge on Android.

## 6. Screens

### 6.1 Shell (`lib/ui/shell/app_shell.dart`)
`BBNavBar` with Board / Map / Alerts (Alerts shows the active-alert count). Content scrolls under the floating bar with bottom padding so the last item is never hidden. Router structure in `lib/routing/router.dart` is unchanged. Settings is still pushed over the shell.

### 6.2 Board (`lib/ui/board/`)
- **Header:** stop-number pill (`STOP 1150`: `ink` background, `bg` text, radius 6), **Change** link (`brandInk`) → stop picker, settings icon; stop name in `display`; live status line: green dot + "Live · updated just now" / "Updated 2 min ago" / "Offline · showing schedule".
- **Alert banner** (warn tone) when an active alert affects this stop or its routes → tap opens the alert.
- **Arrival rows** (`BBCard`): `RouteBadge` · destination (`headline`, one line, ellipsis) · status line (`● Live · Bus 2134`, `Scheduled`, `1 min early`, `2 min late`) · minutes (`minutes` style; `soon` colour when ≤ 5).
- `BBRefresh` pull to refresh.
- **New:** tapping a row **with a live vehicle** switches to the Map tab in follow mode for that vehicle. Rows without a live vehicle aren't tappable.

### 6.3 Stop picker (`lib/ui/stop_picker/`)
Title "Choose a stop"; `BBTextField` "Stop name or number on the pole"; `BBSegmented` *Near me | Stop number*; stop cards: name, `Stop 1150 · 80 m`, route pills for routes serving the stop; primary `BBButton` where a confirm step exists today.

### 6.4 Alerts (`lib/ui/alerts/`)
Service-status card (green dot + "Weekday service running" + updated time); "Active now" section with a count chip; then upcoming; alert cards with type pill (Detour = warn, No service = danger), route pills in route colours, description, and validity ("Until Nov 1, 12:44 PM"). Footer: **"Data from Metrobus open data · BusBoard is independent"** (replaces "Official Metrobus GTFS-Realtime" at `alerts_screen.dart:109`).

### 6.5 Settings (`lib/ui/settings/`)
- **Appearance:** app theme (System / Light / Dark) **and map theme** (Match app / Light / Dark), moved here from the map's theme sheet (still backed by `mapThemeMode` in `providers.dart`).
- Refresh interval (existing).
- **About:** "BusBoard NL is an independent app and is not affiliated with Metrobus Transit.", data credit ("Schedules and live data: Metrobus open data (GTFS, GTFS-Realtime)"), map credit (OpenFreeMap, © OpenStreetMap contributors), version.

## 7. Map (`lib/ui/map/`)

### 7.1 Map style
Two style JSONs, `assets/map/harbour_light.json` and `harbour_dark.json`, derived from OpenFreeMap Positron / Dark with recoloured layers (land ≈ `#EFE9DF`, water ≈ `#BFD9EA`, roads white, labels `muted`; the dark equivalents use the dark tokens). Tiles, glyphs and sprites still load from OpenFreeMap, and the attribution control stays visible. Loaded through `styleString`. They are generated by a recolour script, `tool/build_map_styles.dart`, from the upstream styles, so they can be regenerated.

### 7.2 Layers
- **Buses:** two symbol layers per bus:
  1. a small navy **direction notch** icon rotated by heading (`icon-rotate`, map-aligned);
  2. an upright **route pill** icon (route `fill`, navy outline, route number), generated per route at runtime with `dart:ui` and registered via `addImage`.
- **Stops:** hidden below zoom ~14.5. From there up, small cream dots with a navy ring. The **selected stop** has a larger `brand` ring and is visible at all zooms.
- **Route shape (follow mode only):** the followed trip's shape, drawn in the route's `line` colour, 5 px, under the buses.

### 7.3 Default layout
Full-screen map under the status bar. Top-left chip: `📍 MUN Centre · 1150 ▾` (opens the stop picker). Top-right chip: route filter (`All routes ▾`). Right side: a floating control pill with **my location** only (map theme moves to Settings). Bottom: a `BBSheet` in **peek** showing the selected stop's next 1–2 arrivals; dragging to half/full shows the full list. The nav bar floats above the sheet.

### 7.4 Follow mode
- **Entry:** tap a bus on the map, or a live arrival row on the Board.
- **State:** the followed vehicle ID (keyed the same way as `BusMotionEngine` states), held in a map-scoped provider.
- **Visuals:** the followed route's shape is highlighted; other buses fade to ~35% opacity; the camera eases to the bus each tick. If the user pans or zooms by gesture, auto-follow pauses and a **Recenter** chip appears.
- **Sheet:** header = `RouteBadge` · destination · "Following Bus 2134 · live" · ETA to your stop (`soon` colour ≤ 5 min). Body = a **stop timeline** from the bus's current position to your stop: past segment dimmed, current position marked, upcoming stops with ETAs (scheduled + current delay), your stop emphasised. If your stop isn't on this trip, the timeline shows the next ~6 stops.
- **Details:** "Last GPS update 12 s ago" is always visible. Speed / heading / GPS fix (currently shown in `bus_bottom_sheet.dart`) move into a collapsed **Technical details** section.
- **Exit:** ✕ in the sheet, tapping an empty map area, or the bus leaving the feed. In that last case a `BBToast` says "Bus 2134 is no longer reporting".

## 8. Phasing

Each phase is shippable on its own.

1. **Foundation:** tokens, `RoutePalette`, Figtree, kit components, `BBTheme`, platform-neutral behaviour, icon/splash/store-icon assets, legal wording (alerts footer + About).
2. **Screens:** shell/nav bar, Board (incl. the board→map link, wired once follow mode exists; until then rows aren't tappable), Stop picker, Alerts, Settings (incl. the map-theme move).
3. **Map:** Harbour map styles, new bus/stop layers, chips + control pill, peek sheet, follow mode with timeline, the new bus details sheet. *Requires the identity bug fix first.*

## 9. Testing and verification
- **Kit:** a widget test per component (states, tap, semantics labels) plus **golden tests in light and dark** at text scale 1.0 and 2.0.
- **Guard test:** fails if any file under `lib/ui/` outside `lib/ui/kit/` references Material/Cupertino widget classes (allow-list: `Theme`/`MaterialApp` plumbing in `app.dart`).
- **Contrast test:** checks every text/background token pair against WCAG AA.
- **Route palette test:** every route in the GTFS fixture resolves to a colour, and it's stable for the same route number.
- **Existing tests:** update `widget_test.dart`, `bus_bottom_sheet_test.dart` and `service_alert_card_test.dart` for the new widgets. Domain and data tests are untouched.
- **Manual parity check (each phase):** run on the **iOS simulator** and an **Android emulator**; screenshot each changed screen in light/dark and at large text; compare side by side. (No Android AVD exists yet. Creating one needs a ~1–2 GB system-image download and will be confirmed with the user first.)
- **Accessibility:** VoiceOver/TalkBack labels on arrival rows ("Route 29 Signal Hill Road, live, 4 minutes"), touch targets ≥ 44 pt.

## 10. Risks and open items
- **Follow-mode correctness depends on the identity bug.** Phase 3 must not ship before the fix (see §1).
- **The ETA timeline needs per-stop progress.** It uses GTFS stop_times plus the current delay. If the motion engine's progress isn't reliable near terminals (possibly related to the bug), the timeline falls back to scheduled times plus delay, without the position marker.
- **Map style upkeep:** the derived style JSONs are pinned copies. If OpenFreeMap changes its schema they need refreshing, so keep the recolour script in `tool/` so they can be regenerated.
- **Logo legal check:** the design avoids Metrobus marks and colours by construction. This is not legal advice; the user may want a professional check before store submission.
