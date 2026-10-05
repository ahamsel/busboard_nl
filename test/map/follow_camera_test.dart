import 'dart:math' as math;

import 'package:busboard_nl/ui/map/follow_camera.dart';
import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

final _t0 = DateTime(2026, 10, 5, 12);

void main() {
  const bus = LatLng(47.5600, -52.7100);
  const farStop = LatLng(47.5700, -52.7300);
  const nearStop = LatLng(47.5605, -52.7102);

  test('fits the bus and your stop when they are apart', () {
    final move = FollowCamera().next(bus: bus, stop: farStop, now: _t0);
    expect(move, isA<FitMove>());
  });

  test('zooms in on the bus as it reaches your stop', () {
    final move = FollowCamera().next(bus: bus, stop: nearStop, now: _t0) as CenterMove;
    expect(move.zoom, FollowCamera.nearZoom);
  });

  test('centres on the bus alone when there is no stop to show', () {
    final move = FollowCamera().next(bus: bus, stop: null, now: _t0) as CenterMove;
    expect((move.target, move.zoom), (bus, FollowCamera.soloZoom));
  });

  test('moves at most once a second; reset allows an immediate move', () {
    final cam = FollowCamera();
    expect(cam.next(bus: bus, stop: farStop, now: _t0), isNotNull);
    expect(cam.next(bus: bus, stop: farStop, now: _t0.add(const Duration(milliseconds: 500))), isNull);
    expect(cam.next(bus: bus, stop: farStop, now: _t0.add(const Duration(seconds: 1))), isNotNull);
    cam.reset();
    expect(cam.next(bus: bus, stop: farStop, now: _t0.add(const Duration(milliseconds: 1100))), isNotNull);
  });

  test('the close move keeps the bus and your stop in the padded window, above the sheet', () {
    // A tall peeking sheet: the visible band is 125 pt above the screen centre.
    const padding = EdgeInsets.fromLTRB(48, 100, 48, 350);
    final move = FollowCamera().next(bus: bus, stop: nearStop, now: _t0, padding: padding) as CenterMove;
    final midLat = (bus.latitude + nearStop.latitude) / 2;
    final midLon = (bus.longitude + nearStop.longitude) / 2;
    expect(move.zoom, FollowCamera.nearZoom);
    // North-up: the camera centre sits south of the pair, so the pair is
    // drawn above the screen centre, in the middle of the band.
    expect(move.target.latitude, lessThan(midLat));
    final metresPerPoint = 78271.517 * math.cos(midLat * math.pi / 180) / math.pow(2, FollowCamera.nearZoom);
    expect((midLat - move.target.latitude) * 111320, closeTo(125 * metresPerPoint, 0.05));
    expect(move.target.longitude, closeTo(midLon, 1e-9), reason: 'equal side padding');
  });

  test('without padding the close move centres on the midpoint', () {
    final move = FollowCamera().next(bus: bus, stop: nearStop, now: _t0) as CenterMove;
    expect(move.target.latitude, closeTo((bus.latitude + nearStop.latitude) / 2, 1e-12));
  });
}
