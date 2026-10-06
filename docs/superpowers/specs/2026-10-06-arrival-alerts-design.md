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
- Battery and data stay small: one small request per 30 s while an alert runs, and never for more than 90 minutes.

**Success criteria**
- In a replay of a recorded rush hour of one stop's Metrobus predictions (§5), an alert for a live trip fires within ±1 min of "the bus's real departure − lead time" in at least 90% of cases, and never more than 3 min late.
- An alert fires exactly once.
- On the Android emulator with the phone locked and in forced Doze, the live countdown keeps updating and the alert arrives.
- On the iOS simulator with the app in the background, the scheduled alert arrives.

## 2. What the rider sees

### 2.1 Setting an alert
- Every upcoming arrival on the Board gets a bell button, and so does the follow card. Tapping the row still opens follow mode.
- The bell opens a small sheet: "Alert me when route 10 is **3 / 5 / 10 min** away", with the rider's last choice preselected, and a **Set alert** button.
  - A lead time the bus has already passed is disabled (a bus 4 min away offers only 3).
  - A bus under 3 min away has no bell; the row says "Arriving now" as today.
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
- **The bus gets ahead of the lead time** (it's 2 min away when the rider chose 5): the alert fires at once, with the real number.
- **The bus or the feed disappears for 2 minutes:**
  - the Android countdown says "Live tracking lost · using the timetable";
  - the alert falls back to the scheduled time.
- **The bus runs later:** the alert waits; it re-times itself until it fires.
- **Caps:** the watcher stops after 90 minutes whatever happens. Cancelling from the strip, the sheet or the notification stops everything.

## 3. How it's built

### 3.1 Units

| Unit | File | Job |
|---|---|---|
| `ArrivalAlert` | `lib/domain/alerts/arrival_alert.dart` | The alert as a value, with JSON: stop id and name, route, headsign, trip id, route-run, vehicle, scheduled time (absolute), lead minutes, set-at time. |
| `AlertTracker` | `lib/domain/alerts/alert_tracker.dart` | Pure logic, no plugins. It takes the alert, the latest predictions for the stop and the current time. It returns an `AlertStep`: minutes away, source (live, timetable or lost), whether to fire now, and whether it's finished. Every rule in §2.4 lives here. |
| `AlertStore` | `lib/data/alerts/alert_store.dart` | Keeps the one active alert in shared preferences; a stream for the UI; readable from the background isolate. |
| `AlertNotifier` | `lib/data/alerts/alert_notifier.dart` | A thin wrapper over `flutter_local_notifications`. Android channels: "Arrival alerts" (high importance) and "Live tracking" (low, silent, ongoing). iOS: schedule and cancel the one alert. |
| Android watcher | `lib/platform/alert_watcher.dart` | A `flutter_foreground_task` handler that every 30 s does the following: fetch the stop's predictions with `MetrobusMobileApi`, run `AlertTracker`, update the countdown, fire the alert, and stop itself when finished. |
| iPhone scheduler | `lib/platform/alert_scheduler.dart` | Schedules one notification at "predicted time − lead", replacing any earlier one, at each of these moments: when the alert is set, when the Board refreshes that stop, and when the app goes to the background. If that time has passed, it notifies at once. |
| Providers | `lib/state/alert_providers.dart` | The active alert, plus `set` and `cancel`. Picks the watcher on Android and the scheduler on iOS. |
| UI | `lib/ui/alerts/` | The bell button, the lead-time sheet, the "Alert set" strip, and the replace prompt. |

### 3.2 Finding the same bus again
On each check, `AlertTracker` looks for the alert's departure among the stop's predictions, in this order:
1. the same GTFS trip id (the Metrobus JSON endpoint supplies it);
2. the same route-run (e.g. "10-4");
3. the same vehicle on the same route;
4. the same route within ±2 min of the alert's scheduled time.

A row only counts as live when the endpoint's own realtime flag says so.

### 3.3 Backup alert on Android
Whenever an Android alert is set or re-timed, the app also schedules a backup notification for 2 minutes after the latest "predicted time − lead", so a live watcher always fires first. The watcher cancels the backup when it fires, and re-times it on each check. Some phones (e.g. Samsung, Xiaomi) kill background services to save battery; with the backup, the rider still gets an alert.

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
  - `tool/capture_stop_predictions.dart` records one stop's Metrobus JSON every 30 s.
  - A rush-hour recording at MUN Centre (1150) becomes a fixture.
  - A replay test plays it through `AlertTracker` for every trip and lead time. Its "real departure" is when the trip leaves the predictions or reaches zero. It checks the §1 success criteria.
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
- **The Metrobus stop endpoint may fail or be blocked.** Alerts use the timetable and say so.
- **iPhone estimates drift when a bus runs late after the rider leaves the app.** They're labelled as estimates, and opening the app re-times them.
