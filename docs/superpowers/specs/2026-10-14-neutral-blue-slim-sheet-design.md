# Neutral greys, a brighter blue, a slim home sheet, and Follow you can find

**Date:** 2026-10-14
**Status:** approved in conversation, awaiting written review
**Builds on:** `2026-10-12-visual-refresh-design.md` (motion, the picker, scroll edges and dark-mode layering stay; this spec replaces its colours and icon) and `2026-10-12-map-first-redesign-design.md` (the home sheet and cards).
**Branch:** `claude/visual-refresh-spec` (PR #20), so 1.5.0 ships as one coherent look.

## 1. Why

The developer tried the visual refresh on their iPhone and asked for three things:

1. **Colours.**
   - The green tint in light mode and the purple tint in dark mode are everywhere, and they don't like it.
   - Only real colours should carry colour: the brand, routes, live and detour states.
   - Everything else should be plain, neutral grey.
   - The brand goes back to the earlier BusBoard blue, brighter and livelier.
2. **More map.**
   - At rest the home sheet takes up to 55% of the screen.
   - It should shrink to a slim bar, with a natural way to pull it back up.
3. **Follow is hard to find.** Following a bus works, but nothing on screen says so.

**Out of scope:**
- motion;
- the picker;
- scroll edges;
- layout other than the home sheet's resting state;
- a theme picker in Settings.

## 2. Colours

### 2.1 Rules

- **Neutral surfaces.** Backgrounds, surfaces, lines, text and shadows are neutral greys with no hue tint. As a check, every neutral token's OKLCH chroma is at most 0.015. HSL saturation misjudges near-white and near-black greys, so it can't be the test.
- **The brand is the brightened Harbour blue.** It's a fill for primary buttons and selected states, with `onBrand` text on it. Blue text on a surface uses `brandInk`.
- **Status colours are unchanged:** live, warn, danger and soon.
- **The purple accent is retired.**
  - Every place that used `accent` or `accentSoft` (quick-pick chips, saved-place icons and similar) uses `brandInk` or `brandSoft` instead.
  - The `accent` and `accentSoft` tokens are removed, so nothing can bring the hue back.
- **Dark mode keeps its layering:** it gets lighter the higher it sits, with a faint top highlight on floating parts. The layers are neutral greys.
- **Neutral shadows and scrims.** They're black at the same strengths as now. They drop the ink-green tint they have in light mode.
- **Accessibility stays at least as good as now.** All body text pairs meet WCAG AA (4.5:1). Large text and non-text UI meet 3:1. `test/kit/contrast_test.dart` pins every pair.

### 2.2 Tokens (`BBColors`)

The tables list the values that change; anything not listed stays as it is.

| Token | Light | Dark |
|---|---|---|
| bg | `#F4F5F7` | `#121316` |
| surface | `#FFFFFF` | `#1F2024` |
| surfaceRaised | `#FFFFFF` | `#27292E` |
| surfaceField | `#FFFFFF` | `#2B2D32` |
| surfaceFloat | `#FFFFFF` | `#2A2C31` |
| surfaceSunken | `#EEF0F2` | `#18191C` |
| skeleton | `#E6E8EB` | `#33353B` |
| line | `#E3E5E8` | `#3A3D44` |
| highlight | none | white 8% (`#14FFFFFF`) |
| ink | `#16181C` | `#F2F3F5` |
| muted | `#5F646C` | `#A3A7AF` |
| brand | `#1272C9` | `#5EA2F0` |
| onBrand | `#FFFFFF` | `#08203A` |
| brandInk | `#0D5DA6` | `#8CC0F7` |
| brandSoft | `#E3EEFA` | `#16304A` |
| accent, accentSoft | removed | removed |

Contrast of the key pairs:
- White on `#1272C9` is 4.9:1.
- `#08203A` on `#5EA2F0` is 6.2:1.
- `#5F646C` on white is 6.1:1.

The field outline in light mode uses `line`. Fields stay identifiable by their label, placeholder and icon, as in Ruling 2 of the visual refresh.

### 2.3 Route colours

- The route palette is checked against the new brand. `route_palette_test` already requires every route line to be at least ΔE 0.08 away from brand, brandInk, live and warn.
- Route 10's hue goes from **ocean** back to **green**. Ocean sits next to the new blue; green was its hue before the refresh.
- Any other hue that now fails the test (sky and indigo are the likeliest) is moved just far enough to pass. Hues must stay at least ΔE 0.09 apart from each other in both map modes.
- Badge text keeps its own contrast rules.

### 2.4 Map styles

- Both map styles go neutral and are regenerated with `tool/build_map_styles.dart --recolour`.
- Water stays blue-grey and parks stay a muted green, so the map still reads as a map. They are the only coloured land features.

| Feature | Light | Dark |
|---|---|---|
| land | `#EEF0F2` | `#17181B` |
| water | `#C9D9E4` | `#0F1820` |
| park | `#DCE8DD` | `#172019` |
| road | `#FFFFFF` | `#26282C` |
| road casing | `#D9DCE0` | `#2F3237` |

In dark mode the sheet (`#1F2024`) sits a step above the land (`#17181B`). Its shadow and top highlight do the rest of the separating, as in the visual refresh.

### 2.5 Icon and splash

- **Background:** `#1272C9`. This applies to the adaptive icon background, both splash colours and the Android 12 splash icon background.
- **House colours, left to right:**
  - coral `#EF5B5B`;
  - gold `#F2B53A`;
  - green `#3FAE4F` (it replaces the blue house, which would vanish on blue);
  - electric purple `#B65CFF`.
- **Fixed parts:** the windows, wheels and pin dot are `#16181C`. The bus body and pin are white.
- **Centring:** the mark is centred on the canvas, moved by `translate(2 2.5)` in 100-unit space. Before, it sat about 2% left of centre and 2.5% high.
- **Generation:** `assets/brand/busboard_icon.svg` and `busboard_mark.svg` change. The PNGs and platform assets are regenerated through `tool/brand/render_brand_assets.sh`, `flutter_launcher_icons` and `flutter_native_splash`, as in visual refresh Task 11.
- **Feature graphic:** the Play feature graphic is still redone at release.

## 3. The slim home sheet

### 3.1 Resting state: the bar

- The home sheet's lowest stop is a slim bar with two rows:
  1. "Where to?", the existing search field, at least 48 pt tall.
  2. The **stop line**: one tappable row, at least 48 pt tall, describing your stop.
- The bar takes about 15% of the screen height. Its height comes from its content, which scales with text size, not from a fixed fraction.
- The map, its chips and its buttons get the rest of the screen.

### 3.2 The stop line, in every state

| State | Shows | Screen reader |
|---|---|---|
| Live next bus | `★ MUN Centre · [10] 4 min ●`, with the breathing live dot | "Your stop, MUN Centre. Route 10 in 4 minutes, live. Open board" |
| Scheduled next bus | `★ MUN Centre · [10] 4 min` (no dot) | "… in 4 minutes, scheduled. Open board" |
| "Now" | `[10] Now` in the soon colour | "… route 10 arriving now …" |
| No buses within 3 hours | `★ MUN Centre · No buses for a while` | same words |
| Night or before service | `★ MUN Centre · First bus 6:28 AM` | same words |
| Loading | stop name plus a shimmer where the time goes | "Your stop, MUN Centre. Loading" |
| Offline or feed error | `★ MUN Centre · Offline · updated 9:42` | same words |
| Alert affecting the stop | a gold ⚠ after the stop name | "… Detour affects this stop …" |
| No stop chosen | `Choose your stop ›` | "Choose your stop" |

- Tapping the line opens the stop's Board, as Open board does today. With no stop chosen it opens "Choose your stop".
- The time uses the rolling minutes from the visual refresh.
- With 2× text the line truncates the stop name first and never the time.

### 3.3 Detents

- The home sheet has three stops: **bar**, **half** (today's home half) and **full**.
- Flicks snap in the flick's direction.
- The home sheet still can't be swiped away.
- Pulled up, the sheet shows today's home content: saved places, alerts for you, your stop's next buses with Open board, saved trips and nearby stops.
- The bar is the header of the same sheet, so dragging it is one gesture all the way up.

### 3.4 Tucking away on map gestures

- A deliberate pan or pinch on the map lowers the sheet:
  - The **home** sheet drops to its **bar**.
  - **Stop, bus, options and trip cards** drop to their own lowest position, which keeps their header, next bus and actions in view.
- A deliberate gesture is one past the same distance that pauses the follow camera. Taps never trigger it.
- It never happens:
  - in follow mode (the follow card keeps its position);
  - on the tablet side panel;
  - while "choose on map" is active.
- With Reduce Motion on, the sheet jumps straight there.

### 3.5 Opening the app

- The app opens at the bar.
- If the Board was left open, it reopens at full, as it does today.
- A notification or deep link that opens a card behaves as it does today.

### 3.6 Finding the pull-up

- **A one-time hint.** The first time the bar shows, after the map is ready, the sheet lifts about 24 pt and settles back once.
  - With Reduce Motion on, it doesn't lift.
  - Once it has shown, a stored flag keeps it from showing again.
- **The grab handle is a button.** It reads "Show more" at the bar and "Show less" pulled up, and tapping it moves one stop.
- **The Board stays a tap away** through the stop line, for riders who came from the old Board tab.

### 3.7 Unchanged

- the tablet side panel layout;
- the follow card;
- each card's content;
- the Open board / Show map button in the stop sheet.

## 4. Follow, made discoverable

### 4.1 Live rows show a Follow button

- In a stop's departures, a row whose trip has a live bus (`followableVehicle != null`) shows a pill in its second line, replacing the plain "Bus 2134" text:
  - The pill is `brandSoft` with `brandInk` text: "🚌 Follow 2134".
  - Its touch target is at least 44×44 pt.
- Tapping the pill or the row follows the bus, as tapping the row does today.
- Screen reader label: "Follow bus 2134 on the map".
- At 2× text the pill wraps under the status line rather than truncating.

### 4.2 Scheduled rows explain themselves

- Tapping a row with no live bus shows a toast: "No bus on this trip yet. You can follow it once it's live."
- It's announced to screen readers, and the row stays where it is.
- Today the tap does nothing.

### 4.3 A one-time tip

- The first time a stop sheet shows a live row, a quiet line under the departures reads "Tap a live bus to follow it on the map", with a close button.
- It stops showing once the rider follows a bus or closes it. That's stored as a flag.

### 4.4 Unchanged

- Tapping a bus on the map, then Follow.
- "Follow bus" in a planned trip.
- The follow card and the "Following bus …" chip.

## 5. Testing

- **Contrast test:** extended to every pair in §2.2, in both modes. A neutrality check makes every neutral token's OKLCH chroma at most 0.015.
- **Route palette test:** passes against the new brand. Route 10 is green.
- **Brand assets test:** checks the new icon colours, the centring transform and that the splash is `#1272C9`. The old green background must be absent.
- **Slim sheet:**
  - the bar is the home sheet's resting position;
  - the stop line in every state from §3.2, including 2× text at 320 pt width;
  - tapping the line opens the Board;
  - the handle toggles and is announced;
  - the hint shows once and never under Reduce Motion;
  - a pan lowers the home sheet to the bar and a card to its own lowest position;
  - none of this happens in follow mode, on the tablet or during "choose on map";
  - the app opens at the bar, or at full with the Board left open.
- **Follow:**
  - a live row has the pill and its screen reader label;
  - tapping the pill follows the bus;
  - tapping a scheduled row shows and announces the toast;
  - the tip shows once and goes away after a follow or a close.
- **Goldens:** every golden is regenerated and looked at by eye. Add `home_bar_light` and `home_bar_dark`.
- **Simulator check, BusBoard iPhone 17 only:**
  - the icon and splash;
  - the bar;
  - pan-to-collapse;
  - Follow on a live row;
  - light and dark.

  The developer's iPhone check is theirs.

## 6. Done when

- Every test passes, including goldens, and `flutter analyze` is clean.
- The goldens have been reviewed by eye.
- An accessibility review has been run against this spec's screens with the design plugin's accessibility skill.
- The developer approves on their iPhone.
