import 'dart:math' as math;

import 'package:busboard_nl/ui/map/follow_camera.dart';
import 'package:flutter/widgets.dart' show EdgeInsets, Size;
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

  group('fitCamera', () {
    // Web Mercator, MapLibre's 512-point world: where [p] is drawn for [cam].
    (double, double) screen(LatLng p, ({LatLng target, double zoom}) cam, Size view) {
      double mx(double lon) => (lon + 180) / 360;
      double my(double lat) {
        final r = lat * math.pi / 180;
        return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
      }
      final s = 512 * math.pow(2, cam.zoom);
      return (
        (mx(p.longitude) - mx(cam.target.longitude)) * s + view.width / 2,
        (my(p.latitude) - my(cam.target.latitude)) * s + view.height / 2,
      );
    }

    // The case seen live on a 13-inch iPad: a tall card leaves far more
    // padding below than above, and MapLibre iOS centred the bounds as if
    // the padding were symmetric, drawing the bus under the card.
    const view = Size(1032, 1376);
    const padding = EdgeInsets.fromLTRB(64, 172, 64, 397);
    const bus = LatLng(47.561607, -52.749134);
    const stop = LatLng(47.573370, -52.735682);

    test('keeps both points inside the padded window, however lopsided', () {
      final cam = FollowCamera.fitCamera(bus, stop, padding: padding, view: view);
      for (final p in [bus, stop]) {
        final (x, y) = screen(p, cam, view);
        expect(x, inInclusiveRange(padding.left - 0.5, view.width - padding.right + 0.5));
        expect(y, inInclusiveRange(padding.top - 0.5, view.height - padding.bottom + 0.5));
      }
    });

    test('fills the window along the tighter side', () {
      final cam = FollowCamera.fitCamera(bus, stop, padding: padding, view: view);
      final (bx, by) = screen(bus, cam, view);
      final (sx, sy) = screen(stop, cam, view);
      final w = view.width - padding.horizontal, h = view.height - padding.vertical;
      final fill = math.max((bx - sx).abs() / w, (by - sy).abs() / h);
      expect(fill, closeTo(1, 0.01));
    });

    test('never zooms closer than maxZoom for two points on top of each other', () {
      final cam = FollowCamera.fitCamera(bus, bus, padding: padding, view: view, maxZoom: 16.5);
      expect(cam.zoom, 16.5);
      final (x, y) = screen(bus, cam, view);
      expect(x, closeTo(padding.left + (view.width - padding.horizontal) / 2, 0.5));
      expect(y, closeTo(padding.top + (view.height - padding.vertical) / 2, 0.5));
    });
  });
}
