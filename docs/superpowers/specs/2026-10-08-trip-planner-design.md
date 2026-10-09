# Phase 5 — On-device trip planner and saved trips (1.4.0)

**Date:** 2026-10-08
**Status:** Implemented on branch claude/trip-planner (device check pending)
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
- Speed: a search takes under 100 ms on the Android emulator, after the day's index is built. Building the index takes under 1 s, in a background isolate.
- A rider plans and saves "MUN Centre → Avalon Mall, leave now" in under 30 seconds in the device check.
- No plan is ever shown that needs a transfer of under 1 minute (§3.4).

## 2. What the rider sees

### 2.1 Where the planner lives
- **A Plan tab**, fourth in the bottom bar after Board, Map and Alerts.
- **Map:** a long-press anywhere opens a small sheet with "Plan from here" and "Plan to here". The planner opens with that end set to a pin.
- **Stop card** (map): a new button, "Plan a trip from here", sets From to that stop.

### 2.2 The Plan tab
- **Saved trips** sit at the top. Each card shows its name and up to 3 distinct departure times, earliest first, in the short form "8:12 · 10 · live, 8:24, 8:41" (the first bus with its route and a live mark; the others as times only, without AM or PM). Each time is when the bus leaves the rider's boarding stop, not when the rider sets out. Tapping a card fills the planner with its ends for "Leave now". A long-press, or the card's More button, offers Rename and Remove.
- **The planner** below:
  - **From** and **To**: each takes a stop number, a stop name, "My location" or "Pick on map". A swap button exchanges them. "My location" reads "Finding you…" while it waits for a fix, for at most 10 s; then "Couldn't find your location", and it can be tapped again.
  - **When**: Leave now / Leave by / Arrive by, with an exact-minute time picker and a date for later days. Both pickers are the app's own kit pickers, and the When control wraps at large text. Leave by and Arrive by start at half an hour from now, rounded up to the next 5 minutes, and move on with the clock until the rider picks a time (a picked time is kept when the mode changes).
  - **Results** appear as soon as both ends are set (no Plan button) and show 3–5 journeys. Each result card shows the leave and arrive times, the total minutes, the route badges in order (10 → 2), the walking minutes, and a live dot when a live time was used. A warning shows when a transfer is tight (§3.4).

### 2.3 Journey detail
- A timeline of legs: "Walk 3 min to MUN Centre (1150) · Route 10 at 8:12, 6 stops · Walk 2 min to stop 1600 · Route 2 at 8:31 · Arrive 8:47".
- **Show on map** draws the ride legs in route colours and the walk legs as dotted lines.
- The first ride leg offers **Follow** (the existing follow mode) and the **bell** (1.3.0 arrival alerts, same rules as on the Board). A follow started here counts to the trip's boarding stop as "your stop", not the Board's saved stop.
- **Save trip** (a star) saves From → To as a saved trip, named by its ends ("MUN Centre → Avalon Mall") and renameable. A toast says "Saved" or "Already saved" (the same two ends are never stored twice), or "You can save up to 10 trips" when the list is full.

### 2.4 Empty and error states
- **No journey:** the title is "No buses get you there at that time". The line under it depends on the mode:
  - Leave by (and Leave now), with nothing left that day: "The next bus that gets you there leaves tomorrow at …" (or "leaves on Sat, Oct 10 at …" when the chosen date is later), from the next day's first journey.
  - Arrive by, where no bus gets there in time: "The earliest you can get there is …", the earliest arrival that day, leaving no earlier than now.
  - Otherwise no line.
- **An end too far from any stop** (no stop within 800 m): the title "Too far from a bus stop" and the line "Pick a closer point for your start." or "…for your destination."
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
| State | `lib/state/trip_planner_providers.dart` | The day's index (built in a background isolate once the schedule loads, kept for 10 minutes), the current query and results, the tomorrow lookup, saved trips with their next departures. |
| UI | `lib/ui/trip_planner/` | Plan tab, place picker, results, journey detail, saved-trip cards, the map long-press sheet. Router: a fourth `StatefulShellBranch` at `/plan`, with `/plan/journey` for the detail (opened without a journey, it goes back to `/plan`). |

### 3.2 Walking
- Walking time is the straight-line distance × 1.3 (a street-detour margin) at 4.5 km/h, rounded up to the minute.
- An access or egress walk is at most 800 m. A transfer walk between two stops is at most 400 m.
- A transfer at the same stop needs no walk but at least 1 minute between arrival and departure.
- Metrobus's `transfers.txt` entries override these: a `min_transfer_time` replaces the computed one, and `transfer_type` 3 (not possible) removes the link. Each entry applies in its own direction only (from → to).
- No walking link or transfer is shorter than 60 s, whether computed or from `transfers.txt` (a stop at the same spot, or a short entry, is floored at 60 s).

### 3.3 Search details
- **Leave by T** (Leave now is T = now): forward RAPTOR from the origin's access stops at T + their walk time.
- **Arrive by T:** reverse RAPTOR from the destination's egress stops at T − their walk time, giving each journey's latest departure. Rebuilding a journey from its latest departure can get off a bus later than needed (a longer ride, then a longer walk), so each departure found is then searched forward as well: the fastest way from that departure that still arrives by T is shown, and the slower copy is dropped.
- Rounds: 1 ride, then up to 3 transfers (4 rides). Walking links are relaxed after each round.
- The day's index is built in a background isolate (`Isolate.run`), so building it never blocks the UI thread. The search itself runs on the main isolate; it took under 10 ms for one search pass on the real schedule in the test run (worst of 200), which is why it needs no isolate.
- **Midnight:** today's index includes yesterday's trips that run past midnight (times ≥ 24:00), shifted by −24 h, so a query at 00:10 finds them. Tomorrow's index is used only for the "next bus" line: on Leave by (and Leave now) with no journey left today, the provider searches tomorrow from 00:00 and offers its first bus. Arrive by never looks at tomorrow.
- The search runs again a few times to fill the list: after each pass it moves the time 1 minute past the earliest departure found (Leave by) or 1 minute before the earliest arrival found (Arrive by), up to 4 passes, and the ranking picks from all of them.
- **Ranking:** 3–5 results, always sorted by departure. For Leave by, the earliest arrival is picked first, then the fewest rides, then the least walking, then the earliest departures. For Arrive by, the same picks turn round: the latest departure that still arrives in time comes first, ties go to the later departure, and the rest fill by latest departure.

### 3.4 Live times and tight transfers
- After the search, ride legs departing within the next 60 minutes take their live per-stop departure and arrival times when the feed has them (same rules as alerts: a fresh fix under 5 min old and a known delay). The times are exactly what the feed predicts, with no margin added, as on the Board and the map. A leg with only one end live whose times then contradict each other (the bus would arrive before it leaves) stays on its timetable times.
- A connection is broken when the live times leave under 1 minute between two rides, when a ride leaves before the walk before it ends, when a ride would end before it starts, or when the journey would have to start before now (or before the chosen Leave by time), counting the walk to the first stop. A broken journey is not shown as is: the planner searches again from the ride before the broken one, without the broken trip. The new journey is checked the same way, with at most 3 re-plans per journey; one that is still broken then is dropped. The result card shows a warning when the plan changed for that reason.
- **Late buses (look-back):** for Leave now and Leave by, with the feed up, the planner also searches from 15 minutes before the earliest start (up to 4 passes, each a minute after the earliest start found), so a bus the timetable says has gone but that is running late can still be offered. These journeys are only checked against the live times, never re-planned: one is kept when, with live times, it starts at or after the earliest start and breaks nothing. They are ranked together with the rest. The look-back is skipped when the earliest start is more than 75 minutes away (the 60-minute live horizon plus the 15-minute look-back), where no live times can apply.
- **Arrive by** never offers a journey that would have to start before now (the walk to the first stop counts), including, when asked before midnight for the next day, last night's late bus that has already left. When nothing still in reach gets there in time, the line is "The earliest you can get there is …", counted from now. A journey the live times take past the deadline is dropped; when that leaves none, the planner makes a live-checked Leave now plan from now: any of its journeys that do arrive in time (a late bus the look-back found) are shown; otherwise the line names its earliest arrival (and there is no line when it finds nothing either).
- The final list is ranked again (no repeats, at most 5, by departure). When two options are the same, the one not changed for live times is kept.
- Plans never wait for the feed: the timetable results show at once, and the plan is made again when the feed answers.
- The journey detail re-checks itself on each refresh: its legs take the live times (with the Live mark), and when they break what is still ahead it says "This trip no longer works with live times. Go back for updated options." (a screen-reader live region). Rides that have already left don't count: the rider may be on the bus, past a change that was tight, and the start-before-now check applies only until the first ride leaves. A rider already walking to the first stop set out at the planned start, so the start counts as broken only when the live times moved it earlier than planned and that earlier start has passed. Each refresh also hands the first ride's row to the arrival alert, as the Board does, so an alert set from the detail is re-timed on iPhone.
- Live times are refreshed while the results or a saved trip are on screen, every 30 s, as on the Board.

### 3.5 Saved trips
- A saved trip stores its two ends (stop id, or pin latitude and longitude with a label) and a name. No times, no history. A "My location" end is stored as a pin labelled "Near <closest stop>" (and the name uses that label, "Near MUN Centre → Avalon Mall"), since it is where the phone was when saved, not wherever it is later.
- Its card runs a Leave now search when the Plan tab is shown and refreshes live times every 30 s while visible. When nothing runs later today it reads "No more buses today".
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
