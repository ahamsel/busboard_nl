// The 1.5 demo-video tour: one rider's trip from MUN Centre, on live data, for a
// screen recording. Run it on a simulator with the touch overlay built in:
//
//   flutter test integration_test/demo_tour_15_test.dart -d <device> --dart-define=DEMO_TOUR=true
//
// The map of every bus, then the rider's stop: set an alert on a bus coming,
// follow that same bus on the map, then plan the trip on from a saved trip.
// Each step prints "DEMO <wall clock> <step>", so the recording can be cut and
// captioned against it (tool/demo_edit_tour.py).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:busboard_nl/demo/demo_tour.dart';
import 'package:busboard_nl/main.dart' as app;
import 'package:busboard_nl/state/arrival_alert_providers.dart';
import 'package:busboard_nl/ui/arrival_alerts/alert_bell.dart';
import 'package:busboard_nl/ui/board/arrival_row_tile.dart';
import 'package:busboard_nl/ui/kit/bb_chip.dart';
import 'package:busboard_nl/ui/kit/bb_sheet.dart';
import 'package:busboard_nl/ui/map/map_layers.dart';
import 'package:busboard_nl/ui/shell/top_actions.dart';
import 'package:busboard_nl/ui/trip_planner/journey_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tripId = 'demo-mun-avalon';

/// Metres between two points, near enough at St. John's latitude.
double _metres(LatLng a, LatLng b) {
  final dy = (a.latitude - b.latitude) * 111320;
  final dx = (a.longitude - b.longitude) * 111320 * math.cos(a.latitude * math.pi / 180);
  return math.sqrt(dx * dx + dy * dy);
}

LatLng _at(BusMarker m) => LatLng(m.lat, m.lon);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('demo tour 1.5', (tester) async {
    Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
    void step(String name) => debugPrint('DEMO ${DateTime.now().toIso8601String()} $name');

    Future<void> until(bool Function() ok, {int timeoutMs = 30000, String what = ''}) async {
      final end = DateTime.now().add(Duration(milliseconds: timeoutMs));
      while (!ok()) {
        if (DateTime.now().isAfter(end)) throw StateError('timed out waiting for $what');
        await wait(150);
      }
    }

    // Sent as device events, so the test binding doesn't paint its own
    // crosshair over each touch; the app's demo overlay shows them instead.
    binding.shouldPropagateDevicePointerEvents = true;
    var pointerId = 900;

    Future<void> tapAt(Offset at, {int holdMs = 120}) async {
      final p = TestPointer(pointerId++, PointerDeviceKind.touch);
      binding.handlePointerEventForSource(p.down(at), source: TestBindingEventSource.device);
      await wait(holdMs);
      binding.handlePointerEventForSource(p.up(), source: TestBindingEventSource.device);
    }

    Future<void> tapOn(Finder f) => tapAt(tester.getCenter(f.first));

    Future<void> drag(Offset from, Offset to, int ms) async {
      final p = TestPointer(pointerId++, PointerDeviceKind.touch);
      binding.handlePointerEventForSource(p.down(from), source: TestBindingEventSource.device);
      await wait(90);
      final start = DateTime.now();
      while (true) {
        final t = (DateTime.now().difference(start).inMilliseconds / ms).clamp(0.0, 1.0);
        binding.handlePointerEventForSource(p.move(Offset.lerp(from, to, Curves.easeInOut.transform(t))!),
            source: TestBindingEventSource.device);
        if (t >= 1) break;
        await wait(16);
      }
      await wait(60);
      binding.handlePointerEventForSource(p.up(), source: TestBindingEventSource.device);
    }

    /// Ghost fingers for gestures the script performs through the map camera.
    Future<void> ghost(List<Offset> from, List<Offset> to, int ms) async {
      final start = DateTime.now();
      while (true) {
        final t = (DateTime.now().difference(start).inMilliseconds / ms).clamp(0.0, 1.0);
        final e = Curves.easeInOut.transform(t);
        demoGhostFingers.value = [for (var i = 0; i < from.length; i++) Offset.lerp(from[i], to[i], e)!];
        if (t >= 1) break;
        await wait(16);
      }
      demoGhostFingers.value = const [];
    }

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    // The part of the map the controls and the peeking sheet leave clear (measured once the sheet is down).
    var mid = Offset(size.width / 2, size.height * 0.36);
    var clearH = size.height * 0.42;

    /// A pinch: fingers spread about the clear middle as the camera moves in.
    Future<void> pinch(MapLibreMapController c, CameraUpdate to, {int ms = 1700}) async {
      const near = Offset(32, -32);
      const far = Offset(108, -108);
      unawaited(c.animateCamera(to, duration: Duration(milliseconds: ms)));
      await ghost([mid - near, mid + near], [mid - far, mid + far], ms);
    }

    /// The camera that frames [points] in the part of the map the sheet leaves clear.
    CameraUpdate frame(List<LatLng> points, {double maxZoom = 14.5}) {
      var s = points.first.latitude, n = s, w = points.first.longitude, e = w;
      for (final p in points) {
        s = math.min(s, p.latitude);
        n = math.max(n, p.latitude);
        w = math.min(w, p.longitude);
        e = math.max(e, p.longitude);
      }
      final centre = LatLng((s + n) / 2, (w + e) / 2);
      final cosLat = math.cos(centre.latitude * math.pi / 180);
      final latSpan = math.max(n - s, 0.002), lonSpan = math.max(e - w, 0.002);
      final viewW = size.width - 70, viewH = clearH - 40;
      // MapLibre zooms are for 512 px tiles: half the metres per point of the 256 px web convention.
      double zoomFor(double metres, double px) => math.log(78271.517 * cosLat / (metres / px)) / math.ln2;
      final zoom = math.min(
        maxZoom,
        math.min(zoomFor(lonSpan * 111320 * cosLat, viewW), zoomFor(latSpan * 111320, viewH)),
      );
      // The camera centre is the screen's middle; the clear area's middle is higher.
      final metresPerPx = 78271.517 * cosLat / math.pow(2, zoom);
      final shiftPx = size.height / 2 - mid.dy;
      return CameraUpdate.newLatLngZoom(LatLng(centre.latitude - shiftPx * metresPerPx / 111320, centre.longitude), zoom);
    }

    // ── Seed: MUN Centre as the rider's stop, and one saved trip ────
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedStopId', '1150');
    await SharedPreferencesAsync().setString(
      'saved_trips.v1',
      jsonEncode([
        {
          'id': _tripId,
          'name': 'Avalon Mall',
          'from': {'kind': 'stop', 'stopId': '1150', 'name': 'MUN Centre'},
          'to': {'kind': 'stop', 'stopId': '1600', 'name': 'Avalon Mall'},
        },
      ]),
    );
    // Last lead 3 min, so the sheet opens on 3 and the tour's choice visibly moves the selection.
    await SharedPreferencesAsync().setInt('arrival_alert.lead_minutes', 3);

    // ── Start ───────────────────────────────────────────────────────
    app.main();
    await wait(4000);
    step('waiting-for-location');
    final allowed = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(allowed)) {
      final p = await Geolocator.checkPermission();
      if (p == LocationPermission.whileInUse || p == LocationPermission.always) break;
      await wait(500);
    }
    step('location-ok');
    await until(() => find.text('Map').evaluate().isNotEmpty, what: 'the tab bar');
    await wait(1500);
    await tapOn(find.text('Map'));
    await until(() => DemoMapHooks.current != null && DemoMapHooks.current!.markers().length >= 4,
        what: 'buses on the map');
    final map = DemoMapHooks.current!;
    final c = map.controller;
    await wait(1500);
    final handle = find.byKey(BBSheet.handleKey);
    if (handle.evaluate().isNotEmpty) {
      final h = tester.getCenter(handle.first);
      await drag(h, Offset(h.dx, size.height * 0.9), 500);
      await wait(800);
    }
    final top = tester.getRect(find.text('All routes').first).bottom;
    final bottom = tester.getRect(find.byKey(BBSheet.handleKey).first).top;
    mid = Offset(size.width / 2, (top + bottom) / 2);
    clearH = bottom - top;

    // ── A. Every bus, framed where the buses are ────────────────────
    List<BusMarker> live() => [for (final m in map.markers()) if (!m.stale) m];
    List<LatLng> core() {
      final now = live();
      // Buses within 3.5 km of the median, so a lone bus in Paradise doesn't widen the view.
      final lats = [for (final m in now) m.lat]..sort();
      final lons = [for (final m in now) m.lon]..sort();
      final median = LatLng(lats[lats.length ~/ 2], lons[lons.length ~/ 2]);
      return [for (final m in now) if (_metres(_at(m), median) < 3500) _at(m)];
    }

    /// Buses drawn in the clear part of the map.
    Future<int> inClear() async {
      var n = 0;
      for (final m in live()) {
        final p = await c.toScreenLocation(_at(m));
        if (p.y > top && p.y < bottom && p.x > 0 && p.x < size.width) n++;
      }
      return n;
    }

    await c.moveCamera(frame(core(), maxZoom: 13.2));
    // A fresh install draws each bus at its first fix until the next ones
    // arrive: let the tracks warm up before anything is shown (cut).
    step('warm-up');
    await wait(32000);
    final wcore = core();
    await c.moveCamera(frame(wcore, maxZoom: 13.2));
    step('overview ${live().length} buses, ${await inClear()} in the clear, zoom ${c.cameraPosition?.zoom.toStringAsFixed(1)}');
    await wait(10000);

    // Into the busiest part of town: the bus with the most others within 1.5 km,
    // counting a terminal's layover pile once.
    final now = <BusMarker>[];
    for (final m in live()) {
      if (now.every((o) => _metres(_at(o), _at(m)) > 60)) now.add(m);
    }
    var hub = now.first;
    var most = -1;
    for (final a in now) {
      final n = now.where((b) => _metres(_at(a), _at(b)) < 1500).length;
      if (n > most) (hub, most) = (a, n);
    }
    final knot = [for (final b in live()) if (_metres(_at(hub), _at(b)) < 1500) _at(b)];
    step('zoom-in $most within 1500 m');
    await pinch(c, frame(knot, maxZoom: 14.0), ms: 2200);
    var shot = await inClear();
    for (var i = 0; i < 2 && shot < 6; i++) {
      await pinch(c, CameraUpdate.zoomBy(-0.7), ms: 1400);
      shot = await inClear();
    }
    step('zoomed $shot in shot, zoom ${c.cameraPosition?.zoom.toStringAsFixed(1)}');
    await wait(7000);

    // ── B. The rider's stop ─────────────────────────────────────────
    step('board-tab');
    await tapOn(find.text('Board'));
    await until(() => find.text('Last stop').evaluate().isNotEmpty, what: 'the last stop card');
    await wait(2200);
    step('open-board');
    await tapOn(find.text('Last stop'));
    final rows = find.byType(ArrivalRowTile);
    await until(() => find.text('Change').evaluate().isNotEmpty && rows.evaluate().isNotEmpty,
        what: 'the MUN Centre board');

    // A live bus, followable, far enough out that the lead tapped below is one the sheet allows.
    ArrivalRowTile? liveRow(int lo, int hi) {
      for (final e in rows.evaluate()) {
        final tile = e.widget as ArrivalRowTile;
        final m = tile.arrival.minutesAway;
        if (tile.arrival.isLive && tile.onTap != null && m >= lo && m <= hi) return tile;
      }
      return null;
    }

    ArrivalRowTile? pick;
    final giveUp = DateTime.now().add(const Duration(minutes: 8));
    while (pick == null && DateTime.now().isBefore(giveUp)) {
      pick = liveRow(8, 11) ?? liveRow(12, 15) ?? liveRow(7, 16);
      if (pick == null) await wait(2000);
    }
    if (pick == null) throw StateError('no live bus due at MUN Centre in 7–16 min');
    step('board-ready');
    await wait(3500);
    // A look down the board, then back up to the bus.
    await drag(Offset(size.width / 2, size.height * 0.72), Offset(size.width / 2, size.height * 0.5), 1300);
    await wait(1800);
    final tripId = pick.arrival.tripId;
    Finder row() => find.byWidgetPredicate((w) => w is ArrivalRowTile && w.arrival.tripId == tripId);
    await Scrollable.ensureVisible(tester.element(row().first), alignment: 0.4, duration: const Duration(milliseconds: 900));
    await wait(2000);

    // ── C. An alert on that bus ─────────────────────────────────────
    final current = (row().evaluate().first.widget as ArrivalRowTile).arrival;
    step('bell ${current.routeShortName} in ${current.minutesAway}');
    await tapOn(find.descendant(of: row(), matching: find.byType(AlertBell)));
    await until(() => find.text('Set alert').evaluate().isNotEmpty, what: 'the lead time sheet');
    await wait(2600);
    // Only an enabled chip is pressed: the largest lead the sheet allows, past the 3 min it opened on.
    final chips = [for (final e in find.byType(BBChip).evaluate()) e.widget as BBChip];
    final enabled = [for (final ch in chips) if (ch.onTap != null && !ch.selected) ch.label];
    step('lead chips enabled $enabled');
    if (enabled.isNotEmpty) {
      await tapOn(find.widgetWithText(BBChip, enabled.last));
      await wait(1800);
    }
    step('set-alert');
    await tapOn(find.text('Set alert'));
    // iOS asks to send notifications now; the operator taps Allow on the recording.
    step('notif-prompt');
    // The alert itself, not its strip: the strip leads the list and is not built while the list is scrolled down.
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp).first));
    await until(() => container.read(arrivalAlertProvider).value != null, timeoutMs: 180000, what: 'the alert set');
    step('alert-set');
    await wait(1500);
    // Back up to the "Alert set" strip, a short pull at a time so the last one doesn't pull to refresh.
    final strip = find.textContaining('Alert set');
    for (var i = 0; i < 4 && strip.evaluate().isEmpty; i++) {
      await drag(Offset(size.width / 2, size.height * 0.45), Offset(size.width / 2, size.height * 0.72), 900);
      await wait(700);
    }
    await wait(3000);
    // And back down to the bus, whose row is not built while the list is at the top.
    // The feed can drop a bus's live prediction for a moment: its row falls back to the timetable, further down.
    for (var i = 0; i < 6 && row().evaluate().isEmpty; i++) {
      await drag(Offset(size.width / 2, size.height * 0.72), Offset(size.width / 2, size.height * 0.45), 900);
      await wait(700);
    }
    await Scrollable.ensureVisible(tester.element(row().first), alignment: 0.4, duration: const Duration(milliseconds: 900));
    final pill = find.descendant(of: row(), matching: find.byKey(ArrivalRowTile.followKey));
    await until(() => pill.evaluate().isNotEmpty, timeoutMs: 90000, what: 'the bus live again');
    await Scrollable.ensureVisible(tester.element(row().first), alignment: 0.4, duration: const Duration(milliseconds: 600));
    await wait(1500);

    // ── D. Follow the same bus ──────────────────────────────────────
    step('follow ${current.routeShortName} ${current.vehicleNumber}');
    await tapOn(pill);
    await until(() => find.text('See all stops').evaluate().isNotEmpty, what: 'the follow card');
    step('following');
    await wait(9000);
    step('see-all');
    await tapOn(find.text('See all stops'));
    await wait(5000);
    final h = tester.getCenter(find.byKey(BBSheet.handleKey).first);
    await drag(h, Offset(h.dx, size.height * 0.72), 900);
    step('back-to-bus');

    // Until the alert's time: the iPhone shows its banner over the app.
    final cap = DateTime.now().add(const Duration(minutes: 9));
    DateTime? due;
    while (DateTime.now().isBefore(cap)) {
      final a = container.read(arrivalAlertProvider).value;
      if (a == null || a.firedAt != null || !DateTime.now().isBefore(a.alertAt)) break;
      if (a.alertAt != due) {
        due = a.alertAt;
        step('alert-at ${due.toIso8601String()}');
      }
      await wait(500);
    }
    step('alert-due');
    await wait(9000);
    // The heads-up came: done following, on to the trip after.
    step('stop-follow');
    await tapOn(find.text('Stop following'));
    await wait(3000);

    // ── E. Plan the trip on ─────────────────────────────────────────
    step('plan');
    await tapOn(find.byKey(TopActions.planKey));
    final saved = find.byKey(const ValueKey('saved-trip-$_tripId'));
    await until(() => saved.evaluate().isNotEmpty, what: 'the saved trip');
    await wait(2500);
    step('saved-trip');
    final card = tester.getRect(saved.first);
    await tapAt(Offset(card.left + card.width * 0.35, card.center.dy));
    final journeys = find.byType(JourneyCard);
    await until(() => journeys.evaluate().isNotEmpty, timeoutMs: 20000, what: 'journeys');
    await wait(4000);
    step('journey');
    await tapOn(journeys);
    await until(() => find.text('Show on map').evaluate().isNotEmpty, what: 'the journey');
    await wait(4000);
    await drag(Offset(size.width / 2, size.height * 0.62), Offset(size.width / 2, size.height * 0.42), 1300);
    await wait(2500);
    step('show-on-map');
    await tapOn(find.text('Show on map'));
    await wait(8000);
    step('end');
    binding.shouldPropagateDevicePointerEvents = false; // the binding asserts it is unset at teardown
  }, timeout: const Timeout(Duration(minutes: 20)));
}
