# Visual refresh: Metrobus green, lively motion, our own picker

**Date:** 2026-10-12
**Status:** Draft for review
**Builds on:** [2026-10-12-map-first-redesign-design.md](2026-10-12-map-first-redesign-design.md). P1 is merged, and so are its polish, the Open board button and iPhone swipe-back (PRs #17, #18, #19). This refresh changes how the app looks and moves, not what it does. Every screen and flow stays as P1 left it.
**Ships in:** 1.5.0, together with P1: one new look, one set of store screenshots, one announcement.
**Mockups (local only, git-ignored):**
- `.superpowers/brainstorm/85703-1791850967/content/`: `metrobus-v2.html`, `bright-green.html`, `buttons.html`, `dark-depth.html`, `purple-bright.html`
- real-app screenshots from the colour spike: the scratchpad's `green-theme/`

## 1. Intent

**The goal.** People should *want* to open BusBoard instead of Google Maps. The app should feel lively, local and polished, with colour and motion that make it easier to read, not just prettier. It should look like its own product on both platforms: neither Android-looking nor iPhone-looking.

**Decisions made with the developer (2026-10-12)**
1. **Colours close to Metrobus's own**, made livelier. Metrobus's brand guide colours are blue `#4C466F` (Pantone 5265, a blue-violet), green `#81B34F` and gold `#A58F5F`.
   - **Main colour:** bright green `#3FAE4F`, matching the new icon.
   - **Secondary:** indigo (Metrobus's "blue", brightened).
   - **Alerts:** gold.
   - **Independence:** the app stays clearly independent. It uses *close* colours, never Metrobus's logo, swoosh or exact palette.
2. **Buttons are bright green with dark text** (style A). White text on that green fails contrast (2.9:1), while dark text passes (5.8:1).
3. **Dark mode is "Night Bus":** deep navy with glowing colours. Floating layers get **lighter the higher they sit**, with a faint top-edge highlight and deeper shadows. The map is a slightly greyer, cooler navy, so sheets, cards and map buttons separate clearly from it.
4. **No tinted fields.** Fields are plain surfaces with a thin outline.
5. **Our own time-and-day picker**, identical on both platforms, replacing Flutter's Material and Cupertino pickers.
6. **Motion throughout:** springy sheets, staggered lists, rolling minutes, a "Now" pulse, breathing live dots and native page transitions. All of it respects Reduce Motion.
7. **Scroll edges:** top bars condense and frost when content scrolls under them, and lists fade softly at the edges.
8. **Icon refresh, not a new logo:** the same row houses, bus and pin, on a bright green background, with the house colours retuned.

**Constraints (unchanged)**
- The app stays free: no ads, no account, no server.
- Nothing about the rider leaves the phone.
- Accessibility stays at least as good as today:
  - every text/background pair meets **WCAG AA** (4.5:1 for body text; 3:1 for large text and non-text UI such as icons, outlines and focus rings);
  - every control has a screen-reader label;
  - nothing overflows at 2× text.
- Reduce Motion (the OS setting, read through `MediaQuery.disableAnimations`) turns every non-essential animation off or makes it near-instant.
- No new dependencies unless a task justifies one (none is expected).

**Success criteria**
- Every token pair in §2 passes the contrast test in `test/kit/contrast_test.dart` (new).
- On the device check, the sheet, cards and floating buttons are clearly distinct from the map in dark mode (the developer judges this on their iPhone).
- No screen shows a Material or Cupertino date or time picker.
- With Reduce Motion on, a widget test finds no running animation longer than 100 ms on home, a stop sheet and options.
- The goldens are regenerated, and every one is reviewed by eye.

## 2. Colour

### 2.1 Tokens

`BBColors` in `lib/ui/kit/tokens.dart` gets these values and two new tokens, `accent` and `accentSoft`. The colour spike (local branch `spike/green-theme`, commit 9e1bb2c) already applied most of them; this table is authoritative.

| Token | Light | Dark (Night Bus) | Use |
|---|---|---|---|
| `bg` | `#F6FAF6` | `#0E1220` | page background behind pushed pages |
| `surface` | `#FFFFFF` | `#1D2540` | sheets, panels, pushed-page cards (dark: "level 1") |
| `surfaceRaised` *(new)* | `#FFFFFF` | `#252E4C` | cards inside a sheet (dark: "level 2") |
| `surfaceField` *(new)* | `#FFFFFF` | `#283152` | fields, segmented controls, chips on a sheet (dark: "level 3") |
| `surfaceFloat` *(new)* | `#FFFFFF` | `#262F4D` | buttons floating on the map (bell, gear, location, chips) |
| `surfaceSunken` | `#EEF4EF` | `#121828` | rare recessed areas only. **Never a field fill** |
| `skeleton` | `#E6EEE8` | `#2E3858` | loading placeholders |
| `line` | `#E1EAE3` | `#36406A` | hairlines, field outlines |
| `highlight` *(new)* | `#00000000` | `#1AFFFFFF` (10% white) | top-edge highlight on dark floating layers |
| `ink` | `#13261A` | `#EEF2FF` | text |
| `muted` | `#5F7366` | `#9AA4C4` | secondary text |
| `brand` | `#3FAE4F` | `#6FDB7C` | **fills only**: primary buttons, selected chips, your location, badges |
| `onBrand` | `#0F2414` | `#0B2010` | text and icons on `brand` |
| `brandInk` | `#237A33` | `#7FE08B` | **green text** on surfaces (links, "Plan a trip from here") |
| `brandSoft` | `#E1F4E2` | `#163A1C` | quiet buttons, selected-row tint |
| `accent` *(new)* | `#5B4FD1` | `#9D94F2` | secondary accent: saved-place icons, a few highlights |
| `accentSoft` *(new)* | `#E9E6FB` | `#26224A` | accent tints |
| `live` | `#2FB67C` | `#45D695` | the live dot |
| `liveInk` | `#1E7A4E` | `#45D695` | "live" text |
| `liveSoft` | `#DFF4EA` | `#123227` | live tints |
| `soon` | unchanged | unchanged | "Now" emphasis where it isn't brand |
| `warnBg` / `warnInk` | `#FCEFD2` / `#7A5200` | `#3A2E12` / `#F9D58A` | alerts, detours (gold) |
| `dangerBg` / `dangerInk` | unchanged | unchanged | errors |

**Rules**
- **Bright green is a fill, never text on white.** Green text on a surface uses `brandInk`.
- **Dark elevation:** the more something floats, the lighter it is. The order is map (style JSON), then `bg`, then `surface`, then `surfaceRaised`, then `surfaceField`. Floating map controls use `surfaceFloat`.
- **Dark top edges:** every dark floating layer gets the `highlight` as a 1 px top inner edge (`BoxShadow` inset, or a top border) and a deeper shadow (black, 45–55%).
- **Light depth:** light mode keeps white surfaces and expresses depth with soft green-tinted shadows (`#13261A` at 8–14%).

### 2.2 Fields
- **Light:** `BBTextField`, the "Where to?" box, the From/To rows, segmented controls and stepper fields use `surfaceField` with a 1.5 px `line` outline.
- **Focus:** a 2 px `brand` ring, which must meet 3:1 against its surroundings. Check it in light; if it fails, use `brandInk`.
- **Banned:** `surfaceSunken` as a field fill. A test greps the kit for it.

### 2.3 Route colours
`RoutePalette` (`lib/ui/kit/route_palette.dart`) is retuned so no route hue sits within a ΔE (OKLab) of 0.08 of `brand`, `live`, `accent` or `warn`.
- **Route 10:** today's green (`#2E9E62`) blends into the UI (seen in the spike). Move it, and route 23's lime, to distinct hues such as teal-blue and olive.
- **Shared stops:** the existing rule still holds. Routes that share stops differ (the `assigned` map).
- **Badge text:** route badges keep dark ink text, and each fill must give it 4.5:1 in both modes.
- **Test:** add `test/kit/route_palette_test.dart` for the ΔE and contrast rules.

### 2.4 Map styles
`assets/map/harbour_light.json` and `harbour_dark.json` are recoloured:
- **Light:** cool green-grey land, soft blue-green water, white roads. Close to what the spike did.
- **Dark:** a *greyer, cooler* navy than `bg`, so sheets (`surface`, `#1D2540`) are clearly lighter and bluer than the map. Target the map's land colour at about `#151A26` and roads at about `#232A3A`.

The route lines and bus markers already glow in dark. Keep their colours as `RoutePalette` dark.

## 3. Motion

### 3.1 Tokens
`BBMotion` grows from three durations and one curve into a small system:

| Token | Value | Use |
|---|---|---|
| `quick` | 120 ms, `easeOutCubic` | presses, toggles |
| `standard` | 220 ms, `easeOutCubic` | most fades and slides |
| `emphasis` | 360 ms, spring (damping ≈ 0.78, stiffness ≈ 260) | sheets snapping to detents, cards entering, picker sheet |
| `stagger` | 40 ms between items, max 8 items | list entrances |
| `pulse` | 1.6 s loop | the live dot breathing |
| `nowPulse` | one 600 ms scale 1 → 1.08 → 1 | a row becoming "Now" |

- **Reduce Motion:** `BBMotion.of(context, d)` already returns zero. Springs get a `BBMotion.spring(context)` that returns a critically damped, near-instant spring.
- **Loops off:** loops (`pulse`) don't run at all under Reduce Motion. The dot is solid.

### 3.2 Where motion appears
- **Sheets:** detent changes use the `emphasis` spring, with a slight overshoot. The tablet panel's content cross-fades when its sheet state changes.
- **Lists:** the rows of a stop's Board, trip options, saved trips, nearby stops and search results enter with a `stagger`. This runs on first build only, never on a live refresh.
- **Minutes:** when a row's minutes change (7 → 6), the number rolls vertically (`AnimatedSwitcher` with a slide and fade, `standard`). Rows that reorder animate their position.
- **"Now":** when a row first becomes "Now", it plays `nowPulse` once and its card gets a brief brand-coloured edge.
- **Live dot:** it breathes (`pulse`).
- **Presses:** they keep `BBPressable`'s scale and dim, with `quick`.
- **Skeletons:** they shimmer (a moving gradient) instead of staying static.
- **Page transitions:** native on each platform. iOS uses Cupertino slide with edge-swipe (fixed in #19); Android uses the Material/predictive back transition.
- **Toasts and banners:** they slide and fade in with `emphasis`.
- **Selections:** segmented controls and chips slide the selection pill between options (`standard`).
- **Map:** buses already glide. The location dot gets a soft ping ring (a `pulse` loop, off under Reduce Motion).

**Not in this spec:** a chip morphing into the bus on the map, and parallax. They're expensive and of small value.

## 4. Our own time and day picker

### 4.1 What it is
- **One sheet replaces both pickers.** `showBBWhenPicker(context, {required DateTime initial, required DateTime first, required DateTime last, required bool use24h}) → Future<DateTime?>` replaces `showBBTimePicker` and `showBBDatePicker` (`lib/ui/kit/bb_pickers.dart`). Options' Leave by / Arrive by opens it once for both day and time.
- **It's a BusBoard sheet,** the same on iOS and Android:
  - a modal bottom sheet (on tablets, a centred card), springing up with `emphasis` over a dimmed backdrop;
  - our colours, Figtree, our corner radius;
  - no Material or Cupertino widgets in its build.
- **Layout, top to bottom:**
  1. **Title:** "Leave by" or "Arrive by", with a Close button.
  2. **Day chips,** horizontally scrollable: "Today", "Tomorrow", then weekday names ("Thu", "Fri", …), up to `last`. The selected chip is a `brand` fill with `onBrand` text.
  3. **Time wheels:**
     - hour (00–23 with `use24h`, else 1–12 plus an AM/PM column) and minute (every minute, 00–59);
     - each wheel uses our own `ListWheelScrollView` styling: a selection band in `brandSoft` (dark: `brandSoft`), the centre value in `ink` at title size, and neighbours fading out;
     - each wheel snaps with a light haptic tick.
  4. **Quick picks:** chips for "In 15 min", "In 30 min", "In 1 hr" and two fixed times ("8:00", "17:00", shown in 12-hour form when `use24h` is false). A quick pick sets the day and time at once and scrolls the wheels to them.
  5. **Primary button:** "Set 13:20 today" (or "Set 8:00 Thursday"), a `brand` fill.
- **Times in the past:** a past time for today is allowed but shown with a muted "That's in the past" line, and the button reads "Use now instead". This matches today's planner behaviour.

### 4.2 Accessibility
- **Wheels:** each is a `Semantics` slider with `increase` and `decrease` actions and a value label ("13 hours", "20 minutes").
- **Day chips** are toggle buttons. The sheet announces the chosen time when it opens and when it's confirmed.
- **2× text:** the wheels' row height scales with the text, and the sheet scrolls if needed. Test it at 320×640.

## 5. Scroll edges
- **Pushed pages' top bars** (Alerts, Settings, Search): `BBTopBar` becomes scroll-aware.
  - At rest it's transparent over `bg`, with the large title.
  - Once content scrolls under it, it condenses (large title → inline title, `standard`) and gets a frosted backdrop: `BackdropFilter` blur 16 with `bg` at 80%, plus a hairline `line` bottom border.
- **Sheet headers** (the stop sheet's STOP/name/actions, the options header): when the sheet's list scrolls, a hairline appears under the header and the header gets a soft shadow.
- **Fades under floating things:** lists in sheets fade to transparent over their last 24 px, behind the bottom safe area. On home, the top 16 px of the sheet's scroll area fades under the header. Use `ShaderMask` with a linear gradient, and never on text-entry areas.
- **Reduce Motion** keeps the hairlines and blur but removes the condensing animation, which becomes an instant switch.

## 6. Icon and brand assets

### 6.1 The mark
`assets/brand/busboard_icon.svg` is recoloured, with the shapes unchanged:

| Part | Colour |
|---|---|
| Background | `#3FAE4F` |
| Houses, left to right | coral `#EF5B5B`, gold `#F2B53A`, blue `#2F6FE4`, violet `#8C5CF6` |
| Window, door and wheel ink | `#13261A` (windows at 45% as today) |
| Bus body and pin | `#FFFFFF` |

`assets/brand/busboard_mark.svg` is recoloured the same way.

### 6.2 Regenerated from it
- `assets/icon/app_icon.png`, `app_icon_foreground.png`, `app_icon_gplay.png`, `splash_logo.png` and `splash_logo_android12.png`, via the repo's existing render route (rsvg-convert or headless Chrome, as the earlier icon work did).
- In `pubspec.yaml`, set `adaptive_icon_background`, `flutter_native_splash.color` and `android_12.icon_background_color` to `#3FAE4F`. Then run `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`.
- The Play feature graphic and store screenshots are redone at release time (release checklist, not this plan), and so is the website's app icon (portfolio repo).

## 7. Scope
- **Every screen:** home, every sheet (home, stop, bus, follow, options, journey), search, Alerts, Settings, the tip, toasts, dialogs, empty and loading states.
- **Unchanged:** layout and behaviour, except where §3–§5 say so. The Figtree font. The app name.

## 8. Testing
- **`test/kit/contrast_test.dart`:**
  - every text/fill pair in §2.1 meets WCAG AA in both modes: `ink`, `muted`, `brandInk`, `liveInk` and `warnInk` on their surfaces, and `onBrand` on `brand`;
  - the focus ring meets 3:1.
- **`test/kit/route_palette_test.dart`:** the ΔE distance from UI colours and the badge-text contrast.
- **Picker tests** (`test/kit/when_picker_test.dart`):
  - day chips up to `last`;
  - wheels set the time, with every minute reachable;
  - the 12/24 h modes;
  - quick picks;
  - past-time handling;
  - semantics actions;
  - 2× text at 320×640;
  - no `MaterialLocalizations`, `TimePickerDialog` or `CupertinoDatePicker` in the tree.
- **Motion tests:** with `disableAnimations: true`, pumping one frame after an interaction settles home, a stop sheet and options (`tester.binding.hasScheduledFrame` is false within 100 ms). The live-dot loop isn't running.
- **Scroll-edge tests:** `BBTopBar` condenses and shows its hairline after scrolling 40 px; the sheet header shows its hairline after the list scrolls.
- **Goldens:** regenerate all screen and kit goldens in light and dark, and look at every PNG. Add dark goldens for home at peek with the map stub, to check the sheet's separation.
- **Device check (iOS simulator and the developer's iPhone):**
  - dark-mode separation;
  - motion feel;
  - the picker on both platforms;
  - Reduce Motion on;
  - VoiceOver on the picker;
  - the new app icon and splash screen.

## 9. Done when
- Every item in §2–§6 is in, the tests in §8 pass, `flutter analyze` is clean, and the goldens are reviewed.
- The developer has tried it on their iPhone and approved the look.
