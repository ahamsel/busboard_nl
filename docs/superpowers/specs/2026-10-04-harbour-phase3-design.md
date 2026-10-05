# Harbour Phase 3 — Kit polish and the live map

**Date:** 2026-10-04
**Status:** Approved in brainstorming, pending written-spec review
**Parent spec:** [2026-10-04-harbour-redesign-design.md](2026-10-04-harbour-redesign-design.md). This document **supersedes its §7 (Map) and §8 item 3**. Everything else in the parent spec, including its constraints, still applies.

## 1. Intent

**What the rider gets**
- Every detail feels like BusBoard's own design, never Google's Material, Apple's, or "made in Flutter". It's the same on iPhone and Android.
- On the map, a rider can pick one bus and follow it smoothly through its whole trip to their stop. The bus never freezes, lurches, goes backward or turns into a different bus.

**Constraints**
- Free and open-licensed parts only.
- No cloud project, no accounts and no API keys.
- Accessibility stays at least as good as today.
- Anything the phone itself draws stays native: keyboard, text selection, permission prompts, share sheets.

**Success criteria**
- No Material Rounded glyph, Material refresh circle or Material spinner is visible anywhere.
- The kit boundary guard's legacy allow-list is empty, meaning the map files no longer use Material.
- In a replay of the 2026-10-04 live capture through the new renderer:
  - no followed or unfollowed bus is drawn moving backward along its own trip;
  - no rendered speed exceeds what the GPS fixes imply;
  - the drawn bus advances in at least 95% of frames whenever the fixes on both sides of the frame show it moving.
- A followed bus is identified by its vehicle number on screen, and that number never changes while following.

**Prerequisite (done):** the "drifts back" bug. When Fleet View answered only some of the time, `routeRun` flapped and the engine reset buses onto the wrong pass. It's fixed by deciding route changes by route number (PR [#2](https://github.com/ahamSel/busboard_nl/pull/2)) and is also on this branch.

## 2. Phase 3a — kit polish

All changes are in `lib/ui/kit/`, so every screen picks them up at once.

### 2.1 Icons: Phosphor plus our own glyphs
- **Phosphor icons** (MIT). The two weights we use, Regular and Fill, are **vendored** as app fonts in `assets/fonts/phosphor/` (families `PhosphorRegular` and `PhosphorFill`). Their licence is registered in `registerAppLicenses()`, like Figtree's. The `phosphor_flutter` package isn't used: its latest release, 2.1.0, doesn't compile on Flutter 3.47, because `IconData` is now final.
  - The **regular** weight is the default.
  - The **fill** weight marks active and selected states: the active nav tab, a starred stop, a selected route chip.
  - `BBIcons` keeps its names (`board`, `map`, `alerts`, …), so screen code doesn't change. Only the glyph source moves from Material Rounded to Phosphor.
  - `BBIcons` are plain `const IconData` values with Phosphor's code points. Release builds keep `--tree-shake-icons`, so only the glyphs we use ship.
- **Custom glyphs** (`lib/ui/kit/glyphs/`, `CustomPainter`, drawn in the B2 logo's style):
  - `bus`: the logo's bus silhouette, front three-quarter view;
  - `stopPole`: a stop sign on a pole, as riders see it on the street;
  - `liveDot`: the "live" indicator, a solid dot with a soft ring and no animation.
  - Each glyph takes a size and colour like an icon, and gets a semantics label from its caller.
- The `BBIcons.*` set loses its `material.dart` import, so `Icons.` disappears from the kit entirely.

### 2.2 Pull-to-refresh and loading: route dots
- **`BBRefresh`** is a custom indicator that replaces Material's `RefreshIndicator`:
  - **Motion:** three dots in route-palette colours (red, yellow, green hues from `RoutePalette`) grow in turn as you pull. Past the threshold there's one `selectionClick` haptic. On release they hop in sequence until the refresh finishes.
  - **Reduce Motion:** the dots appear filled and stay still, with no hop.
  - **Accessibility:**
    - The scrollable gets a custom semantics action, **Refresh**, because screen-reader users can't pull.
    - While refreshing, a live region announces "Refreshing" once, then "Updated" once.
  - **API:** it keeps `onRefresh: Future<void> Function()`, so existing screens don't change.
- **`BBSkeleton`** shows placeholder rows for first loads:
  - Shapes: `arrivalRow`, `alertCard`, `stopCard`.
  - It replaces the spinner on the Board, Alerts and the stop picker's "Near me" list.
  - It's static, with no shimmer, which also makes it reduce-motion safe.
  - Semantics: a single "Loading" label for the group.
- **`BBLoading`** stays for small inline waits. It becomes a small version of the hopping dots, still with no Material spinner.

### 2.3 Sheets: floating card
**`BBSheet`** becomes an inset floating card:
- **Shape:** an 8 pt margin on both sides, radius 24 on every corner, and the shared shadow (a 1 px `line` border in dark mode).
- **Placement:** it sits **above the floating nav bar**, so tabs stay reachable. At full height it stops below the status bar and keeps its margins.
- **Detents:** peek / half / full, as today, with the same settle haptic and spring.
- **New: `header` slot.** The header stays pinned while the body scrolls, and dragging the header moves the sheet.
- **New: `BBSheetController.animateToDetent(detent)`.**
- **Dismissal:** tapping the map collapses the sheet to peek. Swiping down from peek closes it when `dismissible`.
- **Grab handle:** a 34 × 4 pill inside the card. For screen readers it's announced as "Sheet, adjustable", with actions *Expand*, *Collapse* and (when dismissible) *Close*.

### 2.4 Smaller kit items (defaults, carried over from Phase 2)
- `BBDialog` already follows the floating-card language (inset card, radius 24, the shared shadow), so it doesn't change.
- `BBToast` reserves space for the nav bar only when the bar is on screen. The tab shell provides a `BBNavBarScope`, and pushed screens such as Settings sit outside it. This fixes the Settings offset.
- Moving the map branch's bottom padding out of AppShell happens in 3b, together with the map rebuild: the new map lays out its own sheet above the bar. `BBScaffold(reserveNavBar)` is dropped, because no screen needs it.
- New kit pieces needed by the map: `BBChip` and `BBControlPill`. `BBChip` is a floating map chip with an optional leading glyph and trailing chevron; `BBControlPill` is a vertical stack of 44 pt icon buttons.

## 3. Phase 3b — the map

### 3.1 Map style: "Harbour quiet"
- **Files:** two style JSONs, `assets/map/harbour_light.json` and `assets/map/harbour_dark.json`. They're generated by `tool/build_map_styles.dart` from OpenFreeMap's upstream styles and committed. Tiles, glyphs and sprites still load from OpenFreeMap, with no key.
- **Light colours:** land `#EEF1F4`, water `#BFD6EA`, parks `#DCE8DC`, roads white with `#D5DCE3` casing, labels `#7A8794`.
- **Dark colours:** land `#141C25`, water `#0E2A40`, parks `#16261F`, roads `#24303C` / `#2E3B48`, labels `#7D8B99`.
- **Clutter removed:** POI icons, building outlines below zoom 16, minor road labels below zoom 15, and transit layers from the base map (we draw our own).
- **Theme:** the map follows the app theme, or the Settings → Map theme override.
- **Gestures:** rotation and tilt are off, so the map stays north-up and there's no compass. MapLibre's own "i" attribution button can't be removed through maplibre_gl 0.27 (Android forces it on), so it sits bottom-left, tinted `muted`, directly after a small kit text link, "© OpenStreetMap · OpenFreeMap", that is always visible above the sheet and opens the credits (the credit's text size is capped at 1.3×; the button follows the measured link width). *(Amended in 3b-2.)*

### 3.2 Layers (bottom to top)
1. **Route line** (follow mode only):
   - It shows the followed trip's shape in the route colour, 6 px, over a 30%-ink casing.
   - The part the bus has already driven is drawn at 40% opacity.
2. **Stops:**
   - Small white dots with an ink ring, hidden below zoom ~14.5.
   - Your stop is a brand-blue disc with a white star, visible at every zoom.
3. **Buses:** one **route badge** marker per bus.
   - **Badge:** the board's rounded badge (radius 6.5, route `fill`, route ink number, 2 px white outline), so a yellow 10 on the board is the yellow 10 on the map.
   - **Heading notch:** a small triangle in the route colour, rotated to the bus's heading.
   - **Rendering:** the badges are generated per route at runtime with `dart:ui`, registered with `addImage`, and drawn as a symbol layer with `icon-allow-overlap`. The notch is a second symbol layer using `icon-rotate`, aligned to the map.
   - **Followed bus:** drawn 1.35× larger with a 2.6 px outline. Other buses fade to 35% opacity.
   - **Followed bus:** `icon-size` 1.35, which scales the 2 px outline to 2.7 px; one bitmap per route. *(Amended in 3b-3: replaces the 2.6 px figure above.)*
   - **Stale bus** (no fix for over 90 s): grey badge.

### 3.3 Default layout
- **Map:** full screen, under the status bar.
- **Top-left `BBChip`:** "★ MUN Centre · 1150 ▾". Tapping it opens the stop picker.
- **Top-right `BBChip`:** "All routes ▾". Tapping it opens a floating card of route badges for multi-select, using the fill state for selected.
- **Right-hand `BBControlPill`:** my location.
- **Bottom `BBSheet`:** at peek it shows the selected stop's next 1–2 arrivals, and dragging it up shows the full list.
- **Tapping a stop:** opens its stop card, with arrivals, *Set as my stop* and *Open board*.
- **Tapping a bus:** opens its bus card, with route, destination, bus number, early/late, a **Follow** button, and a collapsed *Technical details* section (speed, heading, last GPS time). *(3b-2 ships the bus card without the Follow button; Plan 3b-3 adds it with follow mode.)*

### 3.4 Motion: drawn a few seconds behind, always smooth
`BusMotionEngine`'s live extrapolation is replaced by **delayed interpolation** along the route between real GPS fixes. This is pure Dart in `lib/domain/map/`, with no Flutter imports and an injected clock.
- **`BusTrackStore`:** one track per physical **vehicle ID**.
  - A track is an ordered list of fixes (GPS time, lat/lon, heading, speed, trip ID, shape ID, progress along the shape).
  - Progress is computed with **progress-hinted snapping**, `ShapeMatcher.snapNear` (prototyped on 2026-10-04):
    - **Known bus:** the hint is the previous progress plus speed × time.
    - **New bus or trip change:** the hint is the trip's next stop, or else the timetable position shifted by the reported delay.
    - Stops are placed along the shape in sequence order.
  - **Reset rule:** a route-number change starts a new track. A trip change continues the same track across the terminal.
  - Duplicate or out-of-order GPS timestamps are ignored.
  - **Reverse rule:** after a late feed switch the bus drives its next trip backward along the finished trip's shape. Once three fixes in a row on one trip and shape each lie more than 30 m behind the one before, all of them but the first, and the fixes after them, are stored without progress (the snap is kept for the next fix's window), so the renderer draws the raw GPS. Progress returns when a fix advances more than 30 m, or on a trip or shape change. *(Amended in 3b-4.)*
- **`DelayedTrackRenderer`:**
  - It draws each bus at **render time = now − D**.
  - **D** covers feed latency plus the fix interval, so render time never outruns the newest fix: the second-largest of the last ≤ 8 values of (next fix's fetch time − this fix's GPS time), plus 1 s, clamped to 8–30 s; with one fix, its age + 15 s. D moves toward its target at ≤ 0.1 s per second. It's ~25 s with today's feed (fixes arrive ~10 s old, every ~16 s). *(Amended 2026-10-05 in 3b-1 Task 5: the original median-interval + 2 s rule assumed zero latency, and the live replay stopped and jumped with it.)*
    - D is now the **largest** of those lags plus 1 s, clamped to **8–40 s**. On the 2026-10-05 rush hour it is p50 39 s and p90 40 s, about 9 s more than before. The feed's lag there was p90 39 s, and with a 30 s cap the dot ran out of data in 13% of frames. *(Amended in 3b-4.)*
  - **Position:** the renderer interpolates progress along the shape between the two fixes around the render time.
    - Progress is clamped so the drawn position never moves backward on the same trip. GPS that runs backward, for example in a detour, holds the bus still until the GPS passes that point again. A backstep over 150 m (a wrong-pass correction) is not held: a fix pair that far backward crosses geographically, and a hold that far behind is released after 15 s.
    - **A step along the shape must fit the map:** a forward step is drawn along the shape only if it is at most max(1.6 × the map distance between its two places, that distance + 200 m). A bigger step went round a loop or spur the bus skipped (route 14's 1.85 km spur, route 2's 500 m loop), so the pair glides across the map. The continuity limit uses the same test before it walks along the shape. *(Amended in 3b-4.)*
    - **Trip change:** the bus is interpolated across the terminal in plain geographic space.
    - **Off-route** (perpendicular distance over 150 m): it interpolates the raw GPS in a straight line.
    - **When the next fix is late:** it dead-reckons along the shape at the last pair's speed v, decaying: v·τ·(1 − e^(−t/τ)) metres after t seconds, with τ = 7 s, t capped at 20 s and the distance at 55 m. The cap sits under the 60 m jitter hold, so if the bus in fact stopped, the next fix is held rather than drawn as a step back. A last pair that fails the map-distance test above gives no speed. *(Amended in 3b-4: it was "extrapolates at the last segment's speed for at most 5 s, then holds", and the dot froze for 7.3% of the time its bus moved.)*
    - **Continuity limit:** the drawn bus moves toward that target at ≤ 30 m/s (along the shape when moving forward, else in a straight line), so a late fix, a first fix or a correction becomes a quick glide, never a jump. It snaps only on the first frame, after a render gap over 2 s, after a data gap (newest fix more than 60 s after the previous one), or when the track was re-created.
      - A data gap of at most 3 min on a track that was not re-created no longer snaps. It keeps the never-backward rules, so a target behind the mark is held, never snapped back. The limiter catches up at up to 60 m/s until the dot reaches its target. Re-created tracks and gaps over 3 min still snap. *(Amended in 3b-4.)*
- **Other effects:**
  - **ETAs aren't delayed.** Countdowns on the board and in the follow card still come from live predictions, so only the dot runs a few seconds behind.
  - **Code removed:** `BusMotionEngine` and its special cases (stop anchor, Kalman progress filter, blend origins, backward counters) are deleted, along with the GTFS-RT adapter's misuse of `gtfsStopSequenceMinsFromStop` as the delay.
  - **Provider changes:** `busMotionEngineProvider` is replaced by `routeGeometryProvider`, `busTrackStoreProvider` and `busTrackRendererProvider`; `busTrackingStreamProvider` keeps its name and type but now polls into the store. The map's existing frame ticker calls `renderAll` once per frame. *(Amended in 3b-1 Task 6.)*

### 3.5 Follow mode
- **Entry:**
  - Tapping a **live** arrival row on the Board switches to the Map tab and follows that row's vehicle. Rows without a live vehicle can't be tapped.
  - Or press **Follow** on a bus card.
- **State:** `followProvider` holds a vehicle ID, never a route or trip. It is app-wide (the Board starts a follow from another tab); only the map acts on it. *(Amended in 3b-3: was a map-scoped `followedVehicleIdProvider`.)*
- **Taps while following:** while following, taps on other buses and stops are ignored; a tap on empty map collapses the card. *(Amended in 3b-3.)*
- **Route filter:** the followed bus is always drawn, even when the route filter excludes its route. *(Amended in 3b-3.)*
- **Camera:** it keeps the bus and your stop in view, with padding for the sheet and chips, and zooms in as the bus approaches. The close-in move keeps the same padding: it centres the bus and your stop in the window left between the chips and the sheet. *(Amended in 3b-3 final review.)*
  - If you pan or zoom by gesture, following pauses and a "Back to bus 2573" `BBChip` appears.
  - Camera moves respect Reduce Motion: they jump instead of animating.
  - The Back to bus chip sits just above the map credit link (which occupies the band above the peeking sheet). *(Amended in 3b-3.)*
- **Top chip:** "● Following bus 2573".
- **Card (sheet at peek):**
  - header: route badge · "to <headsign>" · "Bus 2573 · 1 min late" · minutes to your stop, from live predictions (`soon` colour at 5 min or less);
  - "2 stops to MUN Centre";
  - a stop strip showing driven, the bus's position, upcoming stops and your stop;
  - buttons: *Stop following* and *See all stops*.
- **See all stops (half or full):** a timeline from the bus to the end of its trip, with ETAs (scheduled + current delay) and your stop emphasised. If your stop isn't on this trip, it shows the next ~6 stops.
- **Ending:**
  - **Arrival:** when the bus reaches your stop, the card shows "Arrived at MUN Centre", follows for 10 s more, then ends.
  - **Past your stop or trip ended:** following ends with a `BBToast`.
  - **Trip change before arrival:** the feed rolls trip IDs over on the timetable clock, early (340–750 m before the terminal) or late (up to 14 min). A new trip ID before arrival is checked in this order: *(Amended in 3b-3 final review.)*
    1. while the live fix is still on the old trip's shape (within the off-route distance, and no more than 50 m behind the bus), following stays on the old trip: progress comes from that fix, the old stops are kept, and the usual arrival / passed / trip-ended rules decide the ending (a stop crossed between two such fixes counts as reached). The route line and the camera stay on the old trip. This lasts at most 3 min. If the held trip runs out (an out-and-back turnaround), step 2 is tried before it ends;
    2. otherwise, if your stop is ahead of the bus on the new trip (no more than 150 m behind it), following moves to the new trip;
    3. otherwise the trip has ended.
    It is still the same vehicle: following never switches vehicle, but it may switch trip.
  - **Not found:** a bus that never appears in the map feed within 60 s ends the follow with a toast. *(Amended in 3b-3.)*
  - **Ending toasts:** stop following and an arrival end the follow without a toast. *(Amended in 3b-3.)*
  - **Feed gap:** the marker turns grey and shows "Last seen 1 min ago". After 5 min, following ends with a toast.
  - **App paused:** after the app comes back from the background, lost contact and not found are not judged until the first poll newer than the snapshot held at resume; the 60 s not-found window restarts at that poll. *(Amended in 3b-3 final review.)*
  - Following never switches to a different vehicle.
- **Screen readers:** the card has a live region that announces only changes in stops remaining (at most once per stop). Every control has a label and an action.

### 3.6 Map-screen cleanup
- `map_screen.dart`, `bus_bottom_sheet.dart` and `stop_bottom_sheet.dart` are rebuilt on the kit.
- They lose every Material widget they use today: FAB, FilterChip, `showModalBottomSheet`, ListTile, SnackBar and `Icons.*`.
- They're split by responsibility under `lib/ui/map/`:
  - `map_screen.dart`: layout;
  - `map_layers.dart`: style and layers;
  - `follow_controller.dart`: camera and follow state;
  - `bus_card.dart`, `stop_card.dart`, `follow_card.dart`.
- The kit guard's `_legacyAllowList` becomes empty.
- Debug snackbars are removed. Debug logging stays behind `kDebugMode`.

## 4. Testing and verification
- **Kit (3a):**
  - widget tests for `BBRefresh` (threshold haptic, Refresh semantics action, reduce-motion state), `BBSkeleton`, `BBSheet` (header drag, `animateToDetent`, handle actions, collapse on map tap), `BBChip` and `BBControlPill`;
  - regenerated goldens, light/dark at text ×1.0 and ×2.0;
  - the screen overflow guard (320 and 360 pt at ×2.0) is extended to the map cards.
- **Motion (3b), pure Dart:**
  - **Unit tests:** interpolation between fixes, the never-backward clamp, off-route fallback, terminal crossing, capped extrapolation, choosing D, duplicate and out-of-order fixes, and `snapNear` on an out-and-back shape.
  - **Replay tests** on committed fixtures:
    - `route_run_flap_2026-10-04`, already on this branch;
    - a 22-bus slice of the 2026-10-04 capture;
    - a rush-hour slice from the 2026-10-05 capture.
    - two more 10-minute rush-hour slices, `rush_1204` and `rush_1330` (the route 14 spur, route 2's loop, a gap snap back, a runaway). The replay test exempts only glides the renderer draws off the shape by design (trip change, pass correction, reverse run, spur step, off route) from its projected-backward check, and it allows 60 m/s while catching up after a short data gap. *(Amended in 3b-4.)*
  - **Probe:** `test/map/probe_rush_hour_test.dart` replays a full local capture and reports far episodes, snaps, frozen and starved time, and lag. It is skipped without the capture. *(Amended in 3b-4.)*
    - They assert the §1 success criteria, measured inside the renderer and not by projecting drawn points onto the shape (that is fooled by routes that reuse a road).
- **Follow mode:**
  - widget tests for entry from a Board row, pause on pan, the Back chip, the end-of-trip and arrival endings, the stale marker, and live-region announcements;
  - a test that the followed vehicle ID never changes over a replay.
- **Parity:** iOS simulator and Android emulator, light and dark, large text, live data.

## 5. Phasing
- **3a, kit polish:** §2. It ships on its own and every screen benefits.
- **3b, the map:** §3, after 3a. Within it, the order is:
  1. motion (store + renderer behind the existing map, verified by replay);
  2. map style and layers;
  3. cards and chips;
  4. follow mode.
- **Phase 4, on-device arrival alerts (not in this spec):**
  - **Android:** a live "Route 10 · 2 stops · 4 min" ongoing notification while following, via a foreground service. It needs a Play declaration.
  - **iOS:** a scheduled local "should arrive in ~5 min" reminder, labelled as an estimate, set when the app goes to the background.
  - It needs no cloud. It gets its own short design once Phase 3 has shipped.

## 6. Risks
- **The ~12 s delay** may surprise riders who compare the dot with the bus in the street. The follow card always shows "Last GPS update 12 s ago" in its technical details, and countdowns stay live.
- **OpenFreeMap availability:** it's a donation-funded free service. If the tiles fail, the map shows the kit error state and the Board keeps working. The style generator also lets us retarget another OpenMapTiles-schema source later.
- **Fleet View is currently "Forbidden"** from some networks. Nothing in Phase 3 depends on it, and the route-number reset rule makes its flapping harmless.
- **Phosphor fonts:** they're vendored, so upgrades are manual (copy the new TTFs and code points). Icon tree-shaking keeps release size in check.
