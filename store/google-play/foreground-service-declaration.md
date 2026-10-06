# Foreground service declaration (1.3.0)

Play Console → Policy and programs → App content → Foreground service permissions. 1.3.0 adds one foreground service, of type `specialUse`. Its subtype (in `AndroidManifest.xml`): "A live transit arrival alert the user starts; it ends when the bus arrives (90 min max)".

## Foreground service type
Special use

## Describe the app functionality that uses this foreground service type
BusBoard NL shows live Metrobus arrivals in St. John's, NL. On a stop's arrival board, the user taps the bell on an arrival and chooses how many minutes ahead they want to know (3, 5 or 10 min), then taps Set alert. From then until the bus arrives, a foreground service checks Metrobus's public real-time feed every 30 seconds and shows an ongoing notification with the bus's live countdown and a Cancel alert action. When the bus is the chosen number of minutes away, the app posts the alert. The service stops by itself when the bus is due, when the user cancels, or after 90 minutes at the most. It never starts without the user setting an alert, and it doesn't start at boot. Only one alert runs at a time. The service doesn't use location, and nothing leaves the device except the feed requests.

## Describe the user impact if the task is deferred or interrupted by the system
The user relies on the alert to leave for their stop in time. If the service starts late or is paused, it stops following the bus's live position, and a bus that runs early would reach the stop before the alert fires, so the user misses the bus. As a fallback, the app also schedules one backup notification shortly after the planned alert time. It can't follow a bus that runs early or late, so the live alert is what makes the feature useful.

## Video
The video shows:
1. Opening a stop's board.
2. Tapping the bell on a live arrival.
3. Choosing the minutes and tapping Set alert.
4. The ongoing countdown notification with its Cancel alert action.
5. The alert arriving.

## Use case
If the pre-set list has nothing closer, pick "Other" and use the description above.
