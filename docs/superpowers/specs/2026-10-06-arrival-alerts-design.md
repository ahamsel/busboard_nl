# Phase 4 — On-device arrival alerts

**Date:** 2026-10-06
**Status:** Approved in brainstorming, pending written-spec review
**Parent spec:** [2026-10-04-harbour-phase3-design.md](2026-10-04-harbour-phase3-design.md), whose §5 named this phase. Its constraints still apply.

## 1. Intent

**What the rider gets**
- A heads-up when their bus is a few minutes away, so they can wait inside until it's time to go.
- They set it from the arrival they care about, in one or two taps.

**Constraints**
- Everything is worked out on the phone: no server, no push service, no account, no API keys, nothing sent anywhere but the Metrobus requests the app already makes.
- The app stays free, with no ads.
- Accessibility stays at least as good as today: every new control has a screen-reader label, and nothing overflows at 2× text.
- Battery and data stay small: two small GTFS-RT feeds (vehicle positions and trip updates, about 37 KB together) every 30 s while an alert runs, at most about 6.5 MB over the 90-minute cap.

**Success criteria**
- In a replay of a recorded rush hour of Metrobus's GTFS-RT feeds (§5), measured against the bus's GPS passage at the stop ("passage − lead time"):
  - at least 70% of attempted alerts fire within ±2 min;
  - at most 20% fire more than 2 min late;
  - an alert that never fires counts as a failure;
  - at least 50 alerts are scored.
- The 1-minute early margin (§2.4) was tuned on the 10-05 capture; it is confirmed on a second capture before release.
- An alert fires exactly once.
- On the Android emulator with the phone locked and in forced Doze, the live countdown keeps updating and the alert arrives.
- On the iOS simulator with the app in the background, the scheduled alert arrives.

## 2. What the rider sees

### 2.1 Setting an alert
- Every upcoming arrival on the Board gets a bell button, and so does the follow card. Tapping the row still opens follow mode.
- The bell opens a small sheet: "Alert me when route 10 is **3 / 5 / 10 min** away", with the rider's last choice preselected, and a **Set alert** button.
  - A lead time the bus has already passed is disabled (a bus 4 min away offers only 3).
  - The bell starts at 4 min. Under 4 min there's no bell, because a 3-min alert on a 3-min bus would fire at once; the row says "Arriving now" as today.
  - A bus more than 60 min away has no bell.
- The first time, a line in the sheet explains why the phone will ask for notification permission. If the rider declines, the sheet says alerts need notifications and offers the system settings.
- Once set:
  - that row's bell shows filled;
  - a slim strip at the top of the Board reads "Alert set · Route 10 · 5 min before · Cancel".
- One alert at a time. Setting another asks "Replace your alert for route 10?".

### 2.2 While it runs
- **Android:** an ongoing, silent notification: "Route 10 to MUN-CNA-MI · about 12 min · live", with a **Cancel alert** action. Tapping it opens that stop's Board.
- **iPhone:** nothing is shown until the alert. iOS gives an app no way to keep watching without a server.

### 2.3 The alert
- **Android, live:** "Route 10 is about 5 min away · MUN Centre (stop 1150)". The ongoing countdown keeps running until the bus is due, then disappears.
- **iPhone:** "Route 10 should be about 5 min away (estimate from 8:02). Open BusBoard for the latest."
- **A timetable-only trip** (no live bus yet), on both platforms: "Route 10 is scheduled in about 5 min · no live tracking for this trip".

### 2.4 When things change
- **Alerts fire about a minute before the chosen lead**, because live predictions run about a minute late. The alert still says the lead ("about 5 min away"); the Android countdown shows the raw prediction, as the Board does.
- **The bus gets ahead of the lead time** (it's 2 min away when the rider chose 5): the alert fires at once, with the real number.
- **The bus or the feed disappears for 2 minutes:**
  - the Android countdown says "Live tracking lost · using the timetable";
  - the alert falls back to the scheduled time, or the last live estimate if that was later (buses rarely get earlier, and a gap in a late bus's tracking must not fire early).
- **The bus runs later:** the alert waits; it re-times itself until it fires.
- **Caps:** the watcher stops after 90 minutes whatever happens. Cancelling from the strip, the sheet or the notification stops everything.

## 3. How it's built

### 3.1 Units

| Unit | File | Job |
|---|---|---|
| `ArrivalAlert` | `lib/domain/alerts/arrival_alert.dart` | The alert as a value, with JSON: stop id and name, route, headsign, trip id, route-run, vehicle, scheduled time (absolute), lead minutes, set-at time. |
| `AlertTracker` | `lib/domain/alerts/alert_tracker.dart` | Pure logic, no plugins. It takes the alert, the latest live departures for it and the current time. It returns an `AlertStep`: minutes away, source (live, timetable or lost), whether to fire now, and whether it's finished. Every rule in §2.4 lives here. |
| `AlertStore` | `lib/data/alerts/alert_store.dart` | Keeps the one active alert in shared preferences; a stream for the UI; readable from the background isolate. |
| `AlertNotifier` | `lib/data/alerts/alert_notifier.dart` | A thin wrapper over `flutter_local_notifications`. Android channels: "Arrival alerts" (high importance) and "Live tracking" (low, silent, ongoing). iOS: schedule and cancel the one alert. |
| GTFS-RT source | `lib/domain/arrival_alerts/gtfs_rt_source.dart` | Pure. `liveResultForAlert` turns the GTFS-RT feeds (`TimeTrackApi.fetchLiveVehiclesResult`) into the one live departure `AlertTracker` reads: the vehicle on the alert's trip (via `buildTripIndex`), dropped when its fix is over 5 min old or it has no delay data. It is timed by the trip update's own time at the alert's stop (§3.2); when the update does not list the stop, as the Board times it (scheduled − schedule difference). A failed feed is a failed result. |
| Android watcher | `lib/platform/alert_watcher.dart` | A `flutter_foreground_task` handler that every 30 s does the following: fetch the GTFS-RT feeds with `TimeTrackApi` and turn them into the alert's live departure with `liveResultForAlert`, run `AlertTracker`, update the countdown, fire the alert, and stop itself when finished. (Metrobus's stop endpoint, `MetrobusMobileApi`, answers 403 Forbidden as of 2026-10-05, so the watcher does not use it.) |
| iPhone scheduler | `lib/platform/alert_scheduler.dart` | Schedules one notification at the alert time ("predicted time − lead", less the 1-minute margin of §2.4), replacing any earlier one, at each of these moments: when the alert is set, when the Board refreshes that stop, and when the app goes to the background. If that time has passed, it notifies at once. |
| Providers | `lib/state/alert_providers.dart` | The active alert, plus `set` and `cancel`. Picks the watcher on Android and the scheduler on iOS. At launch and on resume, a stored alert that has not fired gets its Android watcher back if a reboot, force-stop or battery saver ended it. |
| UI | `lib/ui/alerts/` | The bell button, the lead-time sheet, the "Alert set" strip, and the replace prompt. |

### 3.2 Finding the same bus again
On each check, `AlertTracker` looks for the alert's departure among the live departures, in this order:
1. the same GTFS trip id (the GTFS-RT feed supplies it; when the trip is listed twice, the realtime row, then the visit nearest the alert's scheduled time);
2. the same route-run (e.g. "10-4");
3. the same vehicle on the same route;
4. the same route within ±2 min of the alert's scheduled time.

The live departure's time on Android is the feed's own prediction for the alert's stop: the trip update's stop-time update for the alert's stop id (its departure time, else its arrival time, else the scheduled time plus its delay). A trip that visits the stop twice uses the visit nearest the alert's scheduled time. When the update does not list the stop, the time falls back to scheduled − the vehicle's schedule difference, as the Board shows it. The iPhone has only the Board's rows, so it uses the Board's time.

A row only counts as live when its realtime flag says so. The GTFS-RT source sets it only for a vehicle on the trip with a fix under 5 min old and a known delay, so feed ghosts and vehicles with no delay data fall back to the timetable. Steps 2–4 are for a source without trip ids; the GTFS-RT source always has one.

### 3.3 Backup alert on Android
Whenever an Android alert is set or re-timed, the app also schedules a backup notification for 2 minutes after the latest alert time ("predicted time − lead", less the 1-minute margin), so a live watcher always fires first. Since it comes 2 minutes late, it says the bus is about lead − 2 min away (at least 1): as an estimate from the last live sighting for a live alert, in the timetable wording otherwise. The watcher cancels the backup when it fires, and re-times it on each check. Some phones (e.g. Samsung, Xiaomi) kill background services to save battery; with the backup, the rider still gets an alert. The backup never writes `firedAt`, so when the app opens at or after the backup time (alert time + 2 min) and finds a stored alert that has not fired, it counts as fired at that time and no watcher is restarted for it; otherwise a restarted watcher would see the alert time long past and fire a second time.

### 3.4 Platform setup
- **Android:**
  - Permissions: `POST_NOTIFICATIONS` (Android 13+), `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_SPECIAL_USE`.
  - The service is declared with `foregroundServiceType="specialUse"` and the subtype "A live transit arrival alert the user starts; it ends when the bus arrives (90 min max)".
  - `specialUse` over `dataSync`: `dataSync` is meant for transfers, and Android 15 caps it.
  - Play Console needs the foreground-service declaration and a short video.
- **iOS:** only the notification permission. There are no background modes, so App Review has nothing extra to question.
- **New packages:**
  - `flutter_local_notifications`;
  - `flutter_foreground_task`;
  - `timezone` (iOS schedules use UTC instants, so no time-zone lookup package is needed).

## 4. Out of scope
- Several alerts at once.
- Saved, repeating commute alerts.
- A Lock Screen Live Activity on iPhone.
- Anything that needs a server or push.

## 5. Testing
- **`AlertTracker` unit tests:**
  - each rung of §3.2;
  - firing once;
  - firing early when the bus jumps ahead;
  - the 2-minute fallback;
  - the 90-minute cap;
  - timetable-only trips;
  - a later bus re-timing the alert.
- **Replay:**
  - `tool/capture_gtfsrt_alerts.dart` records the two GTFS-RT feeds (vehicle positions and trip updates) every 30 s.
  - A rush-hour recording is replayed through the watcher's own path: each poll's feeds go to `TimeTrackApi.fetchLiveVehiclesResult()`, then `liveResultForAlert`, then `AlertTracker`, at one poll per 30 s.
  - Alerts are set for every trip in the trip-updates feed, at up to three of its stops, for each lead time the prediction still allows.
  - A stop's "real departure" is the bus's GPS passage: the point of its recorded track nearest the stop, from the vehicle fixes, on its last visit before the stop left the trip's predictions. A trip with no fix within 60 m of the stop is not scored.
  - It checks the §1 success criteria against that passage. The stop-drop-off departure (the first poll where the stop leaves the trip's predictions) is printed for reference only. Synthetic GTFS-RT polls test the replay itself.
- **iPhone scheduler tests** (with a fake notifier): the scheduled time, replacement on a newer prediction and on going to the background, and notifying at once when the time has passed.
- **Widget tests:**
  - the bell's states (live, timetable-only, too late, too far);
  - the sheet's disabled lead times;
  - the strip, the replace prompt and the permission-denied state;
  - no overflow at 320 pt and 2× text;
  - screen-reader labels (e.g. "Alert me before route 10 arrives").
- **Devices:**
  - **Android emulator:** set, lock and watch, use **Cancel alert**, and force Doze (`adb shell dumpsys deviceidle force-idle`).
  - **iOS simulator:** the scheduled alert arrives while the app is in the background.
  - **One real morning bus on the user's phone**, recorded for the third LinkedIn post.

## 6. Release
- Version 1.3.0, with store notes on both stores.
- Play Console:
  - the foreground-service declaration, with its video recorded on the emulator;
  - the Data safety form is unchanged (nothing is collected).
- The privacy policy gains one line: alerts are worked out on the phone, and nothing about them leaves it.

## 7. Risks
- **Google may reject the `specialUse` description.** Fall back to `dataSync`. Failing that, ship scheduled-only alerts on Android, with the backup alert as the only alert.
- **Battery-saving phones may still kill the watcher.** The backup alert covers it.
- **The GTFS-RT feed may stall or show ghosts.** Alerts use the timetable and say so. (The Metrobus stop endpoint has answered 403 Forbidden since 2026-10-05; alerts no longer use it.)
- **Feed accuracy.** Even with the feed's per-stop times and the margin, about 70% of alerts land within ±2 min of the bus's real passage (73% on the 10-05 capture; 64% for the 10-min lead). An arrival estimate from the bus's own GPS track is the next step, out of scope here.
- **iPhone estimates drift when a bus runs late after the rider leaves the app.** They're labelled as estimates, and opening the app re-times them.
