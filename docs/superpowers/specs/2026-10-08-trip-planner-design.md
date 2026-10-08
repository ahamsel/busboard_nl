# Phase 5 — On-device trip planner and saved trips (1.4.0)

**Date:** 2026-10-08
**Status:** Approved in brainstorming, pending written-spec review
**Parent spec:** [2026-10-04-harbour-phase3-design.md](2026-10-04-harbour-phase3-design.md). Its constraints still apply, and so do Phase 4's ([2026-10-06-arrival-alerts-design.md](2026-10-06-arrival-alerts-design.md)).

## 1. Intent

**What the rider gets**
- They plan a trip at an exact time: Leave now, Leave by 8:17, or Arrive by 9:00. The official Metrobus planner only offers 15-minute steps.
- They save a trip they take often ("Downtown → Avalon") and see its next departures, with live times, without entering it again.
- Two Reddit commenters on the 1.2 post asked for exactly these (2026-10-08).

**Constraints**
- Everything is worked out on the phone: no server, no paid maps or directions service, no address-search service, no account, no API keys. The only network use is the live GTFS-RT feed the app already reads.
- The app stays free, with no ads.
- Accessibility stays at least as good as today: every new control has a screen-reader label, and nothing overflows at 2× text.
- Places are stops (by number, name, near me or on the map) or a pin dropped on the map. Street addresses are out of scope, because searching them needs an online service.

**Success criteria**
- Correctness: for at least 200 random (origin stop, destination stop, departure time) queries on the real Metrobus schedule, the planner's earliest arrival equals a simple reference search's (§5). They must agree on every query.
- Speed: a search takes under 100 ms on the Android emulator, after the day's index is built. Building the index takes under 1 s, off the main thread.
- A rider plans and saves "MUN Centre → Avalon Mall, leave now" in under 30 seconds in the device check.
- No plan is ever shown that needs a transfer of under 1 minute (§3.4).

## 2. What the rider sees

### 2.1 Where the planner lives
- **A Plan tab**, fourth in the bottom bar after Board, Map and Alerts.
- **Map:** a long-press anywhere opens a small sheet with "Plan from here" and "Plan to here". The planner opens with that end set to a pin.
- **Stop card** (map): a new button, "Plan a trip from here", sets From to that stop.

### 2.2 The Plan tab
- **Saved trips** sit at the top. Each card shows its name and the next 2–3 departures, for example "8:12 · 10 · live, 8:24, 8:41". Tapping a card opens its plan for "Leave now". A long-press offers Rename and Remove.
- **The planner** below:
  - **From** and **To**: each takes a stop number, a stop name, "My location" or "Pick on map". A swap button exchanges them.
  - **When**: Leave now / Leave by / Arrive by, with an exact-minute time picker and a date for later days.
  - **Plan** shows 3–5 results. Each result card shows the leave and arrive times, the total minutes, the route badges in order (10 → 2), the walking minutes, and a live dot when a live time was used. A warning shows when a transfer is tight (§3.4).

### 2.3 Journey detail
- A timeline of legs: "Walk 3 min to MUN Centre (1150) · Route 10 at 8:12, 6 stops · Walk 2 min to stop 1600 · Route 2 at 8:31 · Arrive 8:47".
- **Show on map** draws the ride legs in route colours and the walk legs as dotted lines.
- The first ride leg offers **Follow** (the existing follow mode) and the **bell** (1.3.0 arrival alerts, same rules as on the Board).
- **Save trip** (a star) saves From → To as a saved trip, named by its ends ("MUN Centre → Avalon Mall") and renameable.

### 2.4 Empty and error states
- **No journey:** "No buses get you there at that time", with the next time service runs when there is one.
- **An end too far from any stop** (no stop within 800 m): "Too far from a bus stop. Pick a closer point."
- **Schedule still loading:** a short loading state, as on the Board.
- **Live feed unavailable:** plans use the timetable only, and no live dot shows.

## 3. How it's built

### 3.1 Components

| Unit | File | Responsibility |
|---|---|---|
| Transfers | `lib/data/gtfs/gtfs_parser.dart`, `gtfs_repository.dart` | Parse `transfers.txt` (not read today) into the repository. |
| Timetable index | `lib/domain/trip_planner/timetable_index.dart` | For one service day, built from `GtfsRepository`: patterns (each distinct stop sequence of a route) with their trips sorted by departure; for each stop, the patterns that serve it and its position in each; walking links between stops; the day's active service ids. Trips from the previous service day that run past midnight (times ≥ 24:00) are included, shifted by −24 h. |
| Search | `lib/domain/trip_planner/raptor.dart` | RAPTOR: round k finds the earliest arrival at every stop using at most k rides (k ≤ 4, so at most 3 transfers). Forward for Leave by; reverse (latest departure) for Arrive by. Returns the Pareto set over (arrival time, number of rides). |
| Journeys | `lib/domain/trip_planner/journey.dart` | Result types: a `Journey` is a list of `WalkLeg` (from, to, minutes) and `RideLeg` (route, trip, pattern, board stop, alight stop, departure, arrival, live flag). |
| Ends | `lib/domain/trip_planner/place.dart` | A `Place` is a stop or a pin. A pin's access legs are walks to every stop within 800 m. |
| Live overlay | `lib/domain/trip_planner/live_overlay.dart` | Replaces scheduled times with live per-stop times for ride legs departing within 60 min, using `TimeTrackApi.fetchLiveVehiclesResult` (the same source and freshness rules as alerts). |
| Ranking | `lib/domain/trip_planner/ranking.dart` | Picks 3–5 results: earliest arrival, fewest rides, least walking; drops near-duplicates. |
| Saved trips | `lib/data/trip_planner/saved_trip_store.dart` | Local storage of saved trips (`SharedPreferencesAsync`, like the alert store). |
| State | `lib/state/trip_planner_providers.dart` | The day's index (built in a background isolate once the schedule loads), the current query and results, saved trips with their next departures. |
| UI | `lib/ui/trip_planner/` | Plan tab, place picker, results, journey detail, saved-trip cards, the map long-press sheet. Router: a fourth `StatefulShellBranch` at `/plan`, with `/plan/journey` for the detail. |

### 3.2 Walking
- Walking time is the straight-line distance × 1.3 (a street-detour margin) at 4.5 km/h, rounded up to the minute.
- An access or egress walk is at most 800 m. A transfer walk between two stops is at most 400 m.
- A transfer at the same stop needs no walk but at least 1 minute between arrival and departure.
- Metrobus's `transfers.txt` entries override these: a `min_transfer_time` replaces the computed one, and `transfer_type` 3 (not possible) removes the link.

### 3.3 Search details
- **Leave by T** (Leave now is T = now): forward RAPTOR from the origin's access stops at T + their walk time.
- **Arrive by T:** reverse RAPTOR from the destination's egress stops at T − their walk time, giving each journey's latest departure.
- Rounds: 1 ride, then up to 3 transfers (4 rides). Walking links are relaxed after each round.
- The search runs on the day's index in a background isolate, so the UI thread never blocks.
- A query whose time is near midnight searches both service days that apply.

### 3.4 Live times and tight transfers
- After the search, ride legs departing within the next 60 minutes take their live per-stop departure and arrival times when the feed has them (same rules as alerts: a fresh fix under 5 min old and a known delay).
- A journey whose live times leave less than 1 minute for a transfer is not shown as is: the planner searches again from that transfer stop, and the result card shows a warning when the plan changed for that reason.
- Live times are refreshed while the results or a saved trip are on screen, every 30 s, as on the Board.

### 3.5 Saved trips
- A saved trip stores its two ends (stop id, or pin latitude and longitude with a label) and a name. No times, no history.
- Its card runs a Leave now search when the Plan tab is shown and refreshes live times every 30 s while visible.
- Up to 10 saved trips.

## 4. Privacy
- Searches run on the phone. A dropped pin is used only for that search and isn't stored unless the rider saves the trip.
- Saved trips stay on the phone.
- The privacy policy gets one line saying saved trips are stored only on the device.

## 5. Testing
- **Engine, on small synthetic networks:** a direct ride; a transfer at the same stop; a walking transfer; an arrive-by query; a trip across midnight; a holiday from `calendar_dates` with no service; the 1-minute transfer rule; a `transfers.txt` override; a pin end with several access stops.
- **Reference check on the real schedule** (`build/gtfs_current`, env `PLANNER_GTFS`, skipped when unset): a deliberately simple reference search (Dijkstra over every stop-time event, plus walking links) compared with RAPTOR's earliest arrival on at least 200 seeded random queries. They must agree on every query.
- **Speed:** the reference-check run also times each search and the index build, and fails over the limits in §1.
- **Live overlay:** replayed against the recorded GTFS-RT captures (`test/fixtures/timetrack/raw_gtfsrt_*.jsonl`, env-gated like the alert replay): late buses shift the times, and a missed transfer triggers the re-search and the warning.
- **Widgets:** the Plan tab, the place picker, results, the journey detail, saved trips (add, open, rename, remove), the map long-press sheet and the stop-card button, including at 2× text.
- **Device check** on the emulator and the iOS simulator before release.

## 6. Release
- Ships as 1.4.0, after 1.3.0 (alerts). On the App Store a new version can't be created while 1.3.0 waits for release, so either 1.3.0 is released first or 1.4.0 replaces it. That's decided when 1.4.0 is ready.
- The store texts, the support page and the privacy policy line are updated as part of the release.

## 7. Risks
- **Walking estimates:** straight-line walking with a 30% margin can be wrong across water, highways or hills. A later version could add on-device street data. The 800 m and 400 m caps limit the damage.
- **Schedule quality:** plans are only as good as the published timetable and the live feed's accuracy (about ±2 min, as measured for alerts).
- **Scope:** street-address search, fares, accessibility routing and multi-day plans are out of scope.
