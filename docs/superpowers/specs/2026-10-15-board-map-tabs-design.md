# Two tabs: Board and Map

**Date:** 2026-10-15
**Status:** design approved in conversation; awaiting written review
**Builds on:**
- `2026-10-12-map-first-redesign-design.md` (the map home, sheets, cards and follow);
- `2026-10-14-neutral-blue-slim-sheet-design.md` (the slim bar, colours and Follow pill).

This spec replaces only the parts named below.

**Branch:** `claude/visual-refresh-spec` (PR #20). It ships in 1.5.0.

## 1. Why

The app is called BusBoard. Many riders only want "when's my bus at my stop?", and for them the map gets in the way. Reddit feedback kept coming back to the Board. Two equal tabs bring back a map-free Board while keeping the map-first view for planning, following and exploring.

## 2. Navigation

### 2.1 Tab bar

- A bottom tab bar with two tabs, **Board** and **Map**, sits on every phone screen of the home.
- **Size:** 56 pt tall plus the bottom safe area.
- **Look:**
  - **Background:** `surface` with a `line` hairline on top.
  - **Labels and icons:** inactive ones are `muted`; the active one is `brandInk`, sitting on a `brandSoft` pill behind the icon.
  - **Icons:** Board uses the existing `BBIcons.board`; Map uses `BBIcons.map`.
- Each tab is a button with a selected state. Screen readers read "Board, tab 1 of 2, selected".
- Switching tabs crossfades with the standard motion duration. Under Reduce Motion it's instant.

### 2.2 Opening the app

- The app opens on the **tab used last**, stored as a flag `home_tab.v1` with the value `board` or `map`.
- On first launch it opens on **Board**.
- The old "Board left open" restore (`board_open.v1`) is replaced by this. On upgrade, if `board_open.v1` names a stop, open on the Board tab with that stop selected, then clear the old key.

### 2.3 Switching tabs from elsewhere

**To the Board tab:**
- tapping the stop line on the Map tab's slim bar;
- "Open board" on any stop card (home sheet or map stop card);
- an arrival-alert notification or a `/board/:stopId` link.

Each one selects that stop on the Board.

**To the Map tab:**
- tapping a Follow pill (the bus is followed on the map);
- picking a destination from "Where to?" on the Board (the trip options open in the Map tab's sheet);
- "Plan a trip from here" on the Board.

The stop sheet's **"Open board" / "Show map" toggle is removed**:
- On a map stop card the button is always "Open board", which switches tabs.
- `sheetAtFullProvider` and its tests go, unless something else still needs them.

### 2.4 Back (Android)

- **On the Map tab:** back steps down one level at a time, as now:
  1. card;
  2. pulled-up sheet;
  3. follow.
- **At the top level of either tab:** back leaves the app.
- **Back never switches tabs.**
- **Over the Board tab:** pushed pages (search, alerts, settings) pop as now.

## 3. Board tab

From top to bottom, under the status bar:

1. **Header row:** the title "Board" (display style), with the bell (alert badge) and gear on the right. These are the same widgets and positions as on the Map tab.
2. **"Where to?"** search field. It opens search, and a destination opens the trip options on the Map tab.
3. **Stop chips:** one scrollable row.
   - The chips, in order:
     1. **★ Your stop** (`selectedStopId`), named by stop.
     2. **Saved places that are stops.**
     3. **Up to 3 recently viewed stops**, from a new store `recent_stops.v1`. Viewing a stop on the Board or a stop card adds it; duplicates are dropped.
     4. **📍 Near me**, the nearest stop by GPS.
     5. **＋**, which opens the stop search (`/search?pickStop=1`).
   - The selected chip uses the `brand` fill. Each chip is a button with a selected state.
4. **The selected stop's board:**
   - **Header:** name, stop number, live state and last update, plus star and refresh.
   - **Alerts** affecting this stop come first, as on the stop sheet.
   - **Departures:** the existing `ArrivalRowTile` rows, with the Follow pill, the toast on scheduled rows, alert bells, rolling minutes and the Now pulse.
   - **"Plan a trip from here."**
   - Pull to refresh.
   - The follow tip from the neutral-blue spec §4.3 also shows here.

Empty and edge states:

- **No stop chosen and no saved stops:** "Choose your stop", followed by the nearby stops list as on today's home. With no location, it offers search instead.
- **Near me with location denied:** the chip opens an explanation and a button to search instead.
- **Loading, error and offline:** the same states and wording as the stop sheet.

**Tablet:** the board is a centred column at most 640 pt wide. The Map tab keeps its side panel.

The Board tab reuses the stop sheet's body. It's the same widget given a scroll view and a header, not a copy.

## 4. Map tab

- The Map tab is today's map home, unchanged except as follows.
- The slim bar's stop line and the Open board buttons switch to the Board tab (§2.3).
- The tab bar sits below the sheet. The sheet's peek, half and full positions and the tuck-away measure from above the tab bar.
- The route filter chip, My location, follow and trip options stay Map-only.

## 5. Alerts

- The bell with its badge is in the same top-right spot on both tabs and opens the Service alerts page.
- **Alerts in context:**
  - The Board shows alerts for the selected stop at the top of its list.
  - The Map shows the ⚠ on the stop line and the alert row in the pulled-up sheet, as now.

## 6. Testing

- **Tab bar:**
  - it renders on both tabs;
  - switching works;
  - screen-reader labels;
  - Reduce Motion makes the switch instant;
  - the last tab persists and opens next time;
  - first launch opens on Board;
  - an upgrade from `board_open.v1` opens Board on that stop.
- **Switching rules:** every route in §2.3, including notifications and `/board/:id` links.
- **Board tab:**
  - the chips' order;
  - recents (most recent first, capped at 3, no duplicates);
  - Near me with and without location;
  - empty states;
  - departures with Follow (which switches to the Map tab and follows);
  - pull to refresh;
  - alerts at the top;
  - 2× text at 320 pt;
  - tablet width.
- **Back:** the Map tab still steps down; back at the top level of either tab exits; back never switches tabs.
- **Map tab:** the sheet's positions and the tuck-away now sit above the tab bar. Existing tests are updated, with no regressions to follow or "Back to bus".
- **Goldens:** add `board_tab_light` and `board_tab_dark`, and regenerate the rest. Every one is checked by eye.
- **Simulator and Android:** the developer's `.dev` build on RFCRA1CK68W covers:
  - first launch;
  - switching tabs;
  - Follow from the Board;
  - planning from the Board;
  - back;
  - the notification deep link if it can be triggered.

## 7. Out of scope

- multiple "your stops" beyond the saved places;
- reordering chips;
- widgets;
- a Board-only setting that hides the Map tab.
