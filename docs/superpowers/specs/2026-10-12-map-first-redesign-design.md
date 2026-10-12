# Map-first redesign: one map, "Where to?", alerts that act

**Date:** 2026-10-12
**Status:** Draft for review
**Builds on:** [2026-10-08-trip-planner-design.md](2026-10-08-trip-planner-design.md) (planner engine, saved trips) and [2026-10-06-arrival-alerts-design.md](2026-10-06-arrival-alerts-design.md) (the arrival bell). Their engines stay; this redesign changes how the rider reaches them.
**Mockups:** `.superpowers/brainstorm/62414-1791832721/content/` (`home-layout.html`, `flow.html`; local only, git-ignored).

## 1. Intent

**The goal.** Riders in St. John's open BusBoard NL instead of Google Maps for anything Metrobus: checking when a bus comes, going somewhere new, and riding to their stop. Today the app wins the first moment (live arrivals, following a bus), but people go back to Google Maps to set a destination. That includes the developer.

**Why riders leave today**
- There are two separate moments, and the app splits them across tabs:
  - "When's my bus?" starts from a stop. BusBoard does this well.
  - "How do I get to X?" starts from a place. Google Maps puts "Where to?" first and knows addresses and businesses. BusBoard's planner is the fourth tab and only knows stops, your location and map pins.
- Service alerts are shown but never acted on:
  - The planner doesn't warn about a detoured leg.
  - Saved trips, Follow and the bell ignore alerts.
  - Nothing tells a rider their own route is detoured.
- There is no "get off at the next stop" alert, which is the main reason riders keep a trip app open on the bus.

**Decisions made with the developer (2026-10-12)**
1. The home screen is built around **"my bus, right now"**: your stop's next buses and your saved trips' next bus show with no taps, with "Where to?" directly above them.
2. **Layout: one map with a pull-up sheet**, like Google Maps and the Transit app. The bottom tab bar goes away. Alerts and Settings become floating buttons on the map.
3. **"Where to?" searches places, addresses, streets and stops from a built-in index** generated from OpenStreetMap and bundled in the app. It works offline, and no search leaves the phone.
4. **The flow in `flow.html` is approved:** home, search, trip options on the map, the "Go" mode with a get-off alert, and any stop's sheet acting as its Board.

**Constraints (unchanged from earlier phases)**
- The app stays free, with no ads, no account, no server, no paid map or search service and no API keys.
- Nothing about the rider leaves the phone. The only network calls are the Metrobus feeds and the map tiles the app already uses.
- Accessibility stays at least as good as today:
  - every control has a screen-reader label;
  - nothing overflows at 2× text;
  - the sheet can be moved with assistive tech, not only by dragging.
- Light and dark themes, 24-hour times, phones and tablets.
- Existing riders mustn't lose anything. Every feature the app has today is still reachable within two taps of the home screen.

**Success criteria (whole redesign)**
- Opening the app with a saved stop shows that stop's next buses with no taps, within 2 s of a cold start on the Android emulator, once the feed has answered.
- "Where to?" → type "costco" → pick Costco → see trip options takes at most 3 taps plus typing, on the device check.
- Every alert affecting a shown trip, saved trip or followed bus is visible on that trip or bus without opening the Alerts screen (tested with recorded alert fixtures).
- During Go, the get-off alert fires before the rider's stop in the device replay (§6.2), including with the phone locked.

## 2. Decomposition

This is too big for one plan, so it ships as four sub-projects. Each gets its own implementation plan, branch and PR, and the order makes each one useful on its own.

| # | Sub-project | Ships | Depends on |
|---|---|---|---|
| **P1** | **Map-first home and navigation**: the map becomes the only main screen, with the home sheet, stop sheet = Board, floating Alerts and Settings, and no tab bar. "Where to?" searches what the planner already knows (stops, saved places, map pin). | 1.5.0 | — |
| **P2** | **Place and address search**: the bundled OpenStreetMap index, the search screen and place results as trip ends. | 1.5.0 if ready, else 1.5.1 | P1 |
| **P3** | **Trips on the map and Go**: trip options drawn on the map, the Go mode that follows your bus, and the get-off alert, including on the lock screen. | 1.6.0 | P1 |
| **P4** | **Alerts that act**: alerts matched to trip legs, saved trips, the followed bus and the bell, plus optional notifications for your routes. | 1.6.0 | P1, P3 |

**Later, not in this spec:** home-screen widgets, iOS Live Activities and Android live notifications for your stop; the route diagram (one route's stops in order with its live buses, planned for 1.5 from Reddit feedback, which will open from a route badge in a stop or bus sheet); and optional in-app feedback questions.

This spec gives P1 in full (§3–§5) and the key decisions for P2–P4 (§6). Each of P2–P4 gets a short spec of its own before its plan.

## 3. P1: what the rider sees

### 3.1 Home
- The **map fills the screen**: live buses, stops when zoomed in, your location, and the route filter chip as today.
- **Floating controls** sit on the map's top right:
  - **Alerts** (bell icon with the active-alert count badge, as the tab has now) opens the Alerts screen.
  - **Settings** (gear) opens Settings.
  - **My location** recentres, as today.
- **The home sheet** sits over the map. It has three heights, peek, half and full, using the existing `BBSheet`. From top to bottom:
  1. **"Where to?"** field. Tapping it opens search (§3.3).
  2. **Saved places** chips: Home, Work and any starred places. Tapping one plans a trip there from your location (§3.4). There's a "+" chip when there are none yet.
  3. **Alerts for you**, a single line per alert, shown only when an active alert touches your stop or a route on your saved trips. Tapping it opens that alert.
  4. **Your stop**: today's My stop card (next 3 arrivals, live marks). Tapping a row follows that bus, as on today's stop card; tapping the header opens the stop sheet (§3.2). With no stop chosen, a "Choose your stop" row opens nearby stops.
  5. **Saved trips**: today's saved-trip cards with their next departures. Tapping one shows its trip options (§3.4).
  6. **Nearby stops**: today's Near me list, with route directions, in the same sheet.
- **At peek,** the sheet shows items 1–4 (or 1–3 and the top of 4 on small phones), so "my bus, right now" needs no taps. Opening the app always starts at peek.

### 3.2 A stop's sheet (replaces the Board screen)
- Tapping a stop on the map, a nearby stop, a stop in search, or a notification for that stop opens the **stop sheet** at half height. The map centres on the stop.
- It shows everything today's Board does:
  - name, number, Live/updated line and the stop's alerts;
  - all arrival rows with live marks, early/late and the bell;
  - pull to refresh.
- Plus three actions:
  - **★** sets it as your stop (replacing "Set as my stop");
  - **Plan from here** sets the trip start to it;
  - **Go from here**: leave by now from this stop, to a destination chosen in search.
- **Tapping a live arrival row follows that bus**, as on today's stop card.
- **Back / swipe down** returns to the home sheet. Android's back button and iOS's swipe-down do the same.
- Today's full-screen Board is removed, and its rows and refresh behaviour move into the sheet. `ArrivalBoardScreen`'s content is reused, not rewritten.

### 3.3 "Where to?" in P1
- **A full-height search screen** over the map: a text field, then results.
- In P1, results come from what exists today:
  - stops, by number or name;
  - "My location";
  - "Choose on map", which drops a pin by tapping the map;
  - saved places;
  - the last 10 destinations, stored on the phone.
- **Typing a 4-digit stop number** shows that stop first. Picking a stop offers two choices: **"Go here"** (plan a trip to it) or **"See its buses"** (open the stop sheet).
- **The start is "My location"** by default. A small "From" row on the trip options changes it to any of the same kinds of place.

### 3.4 Trip options in P1
- Picking a destination shows **trip options in the home sheet's place, at half height**, with the journeys drawn on the map using today's `journey_lines`.
- The sheet has:
  - a **From** row;
  - the **Leave now / Leave by / Arrive by** control, with today's pickers;
  - today's journey cards;
  - **★ Save trip**.
- Tapping a card opens **its steps in the sheet** (today's Journey detail content). From there, **Follow bus** and the bell work as today. **Go** arrives in P3; until then the steps show "Follow bus" as now.
- Back returns to the options, and back again returns home.

### 3.5 Saved places
- A **saved place** is a stop, a map pin, or (from P2) an address or point of interest, with a name and an optional icon: Home, Work, School or a star.
- It's added by:
  - ★ on a search result;
  - "Save as Home" or "Save as Work" on a result;
  - the "+" chip.
- It's edited or removed by a long-press on its chip.
- It's stored on the phone like saved trips (shared preferences, versioned JSON). Nothing is sent anywhere.
- **Saved trips stay.** A saved trip is a pair of places, so existing saved trips keep working unchanged.

### 3.6 What goes away and where it went
| Today | After P1 |
|---|---|
| Bottom bar (Board, Map, Alerts, Plan) | Gone. Home is the map. |
| Board tab, stop picker | The home sheet's Your stop and Nearby sections, plus search by stop number |
| Board screen | The stop sheet |
| Map tab | Home |
| Alerts tab | The bell button on the map; the Alerts screen pushes over the map |
| Plan tab | "Where to?" and trip options in the sheet; saved trips in the home sheet |
| Long-press "Plan from here / to here" | Kept |
| Settings buttons on Board / Plan | The gear on the map |

**Old links keep working**, so notifications and restored state don't break:
- `/board/:stopId` opens home with that stop's sheet;
- `/map` and `/plan` open home;
- `/alerts` opens the Alerts screen;
- `/plan/journey` falls back to home.

Arrival-alert notifications (`ArrivalAlert.boardRoute`) keep their payloads.

### 3.7 First launch after updating
- Before the first 1.5 launch, the bottom bar was where people found things. One dismissible tip appears on the home sheet: "Everything's on the map now: tap "Where to?" to plan, tap a stop for its buses, and the bell is your alerts." It's shown once, then stored as seen.

## 4. P1: how it's built

### 4.1 Navigation
- The `StatefulShellRoute` with four branches is **replaced by a single home route** (`/`) that shows `MapScreen` as the home screen.
- Extra routes:
  - `/stop/:stopId` (home with that stop's sheet);
  - `/search`;
  - `/alerts` and `/settings`, which push over the map;
  - redirects for the old paths (§3.6).
- `AppShell` and the tab bar are deleted. The alert count it computed moves into the bell button.
- **Sheet state is driven by a provider, not by routes**, so the map and its camera never rebuild. `mapSelectionProvider` already chooses the sheet's content (stop, bus, follow). It grows into a `homeSheetProvider` with these states:
  - `home`
  - `stop(stopId)`
  - `bus(vehicleId)`
  - `follow(vehicleId)`
  - `search`
  - `options(query)`
  - `journey(journey)`
- Routes like `/stop/:stopId` just set that state on arrival.

### 4.2 Reuse
- **Kept as they are:**
  - `BBSheet` and its detents;
  - `map_layers`, `journey_lines` and `follow_camera`;
  - the planner (`trip_planner_providers`, RAPTOR and the live overlay);
  - saved trips' storage;
  - `ArrivalsList` / `ArrivalRowTile`, the bell and Follow.
- **Moved into sheets:** the Board's content, the planner's controls and results, the journey steps and the near-me list. Their widgets are extracted from the screens they live in today, so the screens become thin wrappers or are deleted.
- **`map_screen.dart` is already 1,122 lines.** P1 splits it:
  - `home_screen.dart` (the map, the floating controls and the sheet host);
  - one file per sheet body (`home_sheet.dart`, `stop_sheet.dart`, `options_sheet.dart`, `journey_sheet.dart`, and the existing bus and follow cards);
  - `home_sheet_provider.dart`.
  No sheet body knows about the others.

### 4.3 Data
- **New `SavedPlace` model and storage**, next to saved trips: a versioned JSON list in shared preferences, holding a `Place` plus a name and an icon. `Place` stays sealed. P2 adds `AddressPlace` and `PoiPlace`.
- **Recent destinations:** the last 10 `Place`s, stored the same way.

### 4.4 Errors and edge cases
- **No location permission or fix:** "Where to?" still works, and the start defaults to "Choose a start" instead of "My location". The home sheet shows "Your stop" and saved trips as today.
- **No stop chosen and no location:** the home sheet shows "Choose your stop", which opens search with a stop-number hint.
- **Feed down:** the stop sheet shows schedule times and the existing "Couldn't load" and stale states. Nothing new.
- **Keyboard over the sheet:** search is a full-height screen, so the keyboard never covers a half-open sheet.
- **Tablets:** the sheet becomes a left side panel at widths of 700 dp or more, with the same content and states. The map fills the rest.

### 4.5 Testing
- **Widget tests:**
  - the home sheet at peek shows "Where to?", Your stop and the right alerts;
  - each old route lands in the right sheet state;
  - back moves stop → home and journey → options → home;
  - the bell's count matches the active alerts.
- **Provider tests** for `homeSheetProvider` transitions, and for saved places' storage, including the version migration.
- **Golden or screenshot checks** at 1× and 2× text in light and dark: home peek, the stop sheet and options, on a phone and a tablet.
- **Device check** on the Android emulator and the iOS simulator:
  - the first-launch tip;
  - a notification tap opens the stop sheet;
  - Follow from a stop sheet;
  - a saved trip from home to its options;
  - TalkBack and VoiceOver reach every control.
- All existing tests keep passing, or are moved with the widgets they test.

## 5. P1: done when
- The tab bar is gone, and every row of §3.6 works on both platforms.
- Opening the app with a stop chosen shows its next buses at peek with no taps.
- "Where to?" plans to a stop, a saved place or a map pin from your location, and a trip can be saved from its options.
- `flutter test` and `flutter analyze` are clean, and the device check in §4.5 passes.

## 6. P2–P4: decisions so far (each gets its own spec)

### 6.1 P2: place and address search
- **Source:**
  - OpenStreetMap data for the Metrobus area (St. John's, Mount Pearl, Paradise and a margin around them);
  - points of interest (shops, schools, health, government, parks, MUN buildings, transit-relevant places);
  - addresses (house number + street);
  - streets.
- **Pipeline:** a `tool/` script builds a compact index from an OSM extract (for example the Newfoundland extract from Geofabrik) and writes it to `assets/`, the way the GTFS bundle is built today. Each app release refreshes it. OSM's licence (ODbL) needs attribution in the app's About screen and the store listing.
- **Search on the phone:** prefix and fuzzy matching on normalised names ("st johns" = "St. John's"), ranked by kind, popularity and distance from you. Results appear within 50 ms of a keystroke.
- **Size budget:** the index adds at most 5 MB to the app download. Over budget, streets come first and the POI categories get trimmed.
- **Walking:** a trip end that isn't a stop connects to stops within walking distance, using straight-line distance × 1.3 at 4.8 km/h, as the planner does now. A real street-graph walk is out of scope for P2.

### 6.2 P3: trips on the map and Go
- **Go** starts from a journey's steps:
  - it follows the first leg's bus (today's Follow);
  - counts the stops left;
  - moves on to the next leg's bus at a transfer;
  - ends at the destination.
- **The get-off alert** fires when the followed bus is about to leave the stop before yours, judged from the feed's position and stop sequence. If the feed goes quiet, it falls back to the scheduled time, 1 minute before the stop.
  - **Android:** a foreground-service notification (the app already has one declared for arrival alerts).
  - **iOS:** a time-sensitive local notification, backed by background location updates while Go is on. This needs the "when in use, with background" permission and its review explanation, which is decided in P3's spec.
- **Replay testing:** the 2026-10-05 and 2026-10-10 GTFS-RT captures drive Go in tests, so the alert timing is checked against real bus movement.

### 6.3 P4: alerts that act
- **Matching:**
  - each active alert is matched to a trip leg (route, stop and time window) using `ServiceAlert.appliesTo`;
  - to saved trips, through their usual legs;
  - to the followed bus and the bell.
- **What riders see:**
  - a warning on the option or leg ("23 detoured, stop 1450 closed");
  - a line on the saved trip's card;
  - a banner in Go when a new alert hits the current trip.
- **Optional notifications for your routes:** off by default, switched on per saved trip or stop. They're checked when the app is opened or the feed refreshes in the background where the OS allows it. No server, so no true push. The P4 spec decides how often.
- **Planner effect:** a leg through a stop that an alert says is closed is still shown, but flagged and ranked after an unaffected option. The planner never silently drops it, because alert text isn't precise enough to trust.

## 7. Risks
- **Existing riders lose their bearings.** This is handled by the tip (§3.7), by keeping every feature within two taps (§1), and by the stop sheet looking like today's Board.
- **The sheet gets crowded.** At peek it only ever shows "Where to?", saved places, alerts for you and your stop; the rest is below the fold.
- **The size of `map_screen.dart` and of the change.** P1 splits it first and moves widgets rather than rewriting them, and its plan does the split as its own task with no behaviour change.
- **Background location on iOS for Go (P3)** is an App Review risk. It's decided in P3's spec, with a fallback to scheduled-time notifications.
