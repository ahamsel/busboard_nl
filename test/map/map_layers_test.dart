import 'dart:async';
import 'dart:typed_data';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/map/delayed_track_renderer.dart';
import 'package:busboard_nl/domain/map/heading_smoother.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_layers.dart';
import 'package:busboard_nl/ui/map/marker_images.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'support/fake_map_surface.dart';

final _now = DateTime(2026, 10, 5, 12);

BusTrackingState _bus(String id, {int route = 10, String routeRun = 'Rt 10', BusStatus status = BusStatus.active, double lat = 47.56, double lon = -52.71}) =>
    BusTrackingState(
      routeRun: routeRun,
      vehicleId: id,
      routeNumber: route,
      headsign: 'Downtown',
      lat: lat,
      lon: lon,
      heading: 90,
      speedKmh: 30,
      lastGpsTime: _now,
      status: status,
      lastUpdateTime: _now,
    );

/// Images arrive slowly (a busy phone or emulator): addImage for the held ids
/// waits until released.
class _SlowImageSurface extends FakeMapSurface {
  final held = <String>{};
  final _gates = <String, Completer<void>>{};
  final published = <List<String>>[];

  void release(String id) => _gates.remove(id)?.complete();

  @override
  Future<void> addImage(String name, Uint8List bytes) async {
    if (held.contains(name)) {
      final gate = _gates[name] = Completer<void>();
      await gate.future;
    }
    return super.addImage(name, bytes);
  }

  @override
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data) async {
    await super.setGeoJsonSource(id, data);
    if (id == MapLayers.busesSource) {
      published.add([for (final f in features(id)) f['properties']['vehicleId'] as String]);
    }
  }
}

class _FlakySurface extends FakeMapSurface {
  String? failOn;
  @override
  Future<void> addImage(String name, Uint8List bytes) async {
    if (name == failOn) throw StateError('addImage failed');
    return super.addImage(name, bytes);
  }
}

const _mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.57, stopLon: -52.73);

void main() {
  group('busMarkers', () {
    test('uses the drawn position and heading, falling back to the latest fix', () {
      final markers = busMarkers(
        tracking: {'a': _bus('a'), 'b': _bus('b', lat: 47.5)},
        drawn: {'a': const RenderedBus(vehicleId: 'a', lat: 47.6, lon: -52.7, heading: 45)},
        routeFilter: const {},
        headings: HeadingSmoother(),
        now: _now,
      );
      final a = markers.firstWhere((m) => m.vehicleId == 'a');
      expect((a.lat, a.lon, a.heading), (47.6, -52.7, 45));
      final b = markers.firstWhere((m) => m.vehicleId == 'b');
      expect((b.lat, b.heading), (47.5, 90));
    });

    test('the route filter keeps only chosen routes; empty means all', () {
      final tracking = {'a': _bus('a', route: 10), 'b': _bus('b', route: 2)};
      List<String> ids(Set<int> filter) => [
            for (final m in busMarkers(tracking: tracking, drawn: const {}, routeFilter: filter, headings: HeadingSmoother(), now: _now)) m.vehicleId,
          ];
      expect(ids(const {}), unorderedEquals(['a', 'b']));
      expect(ids(const {2}), ['b']);
    });

    test('the followed bus stays even when the route filter excludes its route', () {
      final tracking = {'a': _bus('a', route: 10), 'b': _bus('b', route: 2), 'c': _bus('c', route: 5)};
      final markers = busMarkers(
        tracking: tracking,
        drawn: const {},
        routeFilter: const {2},
        headings: HeadingSmoother(),
        now: _now,
        followedVehicleId: 'a',
      );
      expect(markers.map((m) => m.vehicleId), unorderedEquals(['a', 'b']));
      expect(markers.firstWhere((m) => m.vehicleId == 'a').emphasis, MarkerEmphasis.followed);
    });

    test('stale buses stay on the map, flagged stale', () {
      final markers = busMarkers(
        tracking: {'a': _bus('a', status: BusStatus.stale)},
        drawn: const {},
        routeFilter: const {},
        headings: HeadingSmoother(),
        now: _now,
      );
      expect(markers.single.stale, isTrue);
    });

    test('label falls back to routeRun, then "?"', () {
      expect(busLabel(_bus('a', route: 10)), '10');
      expect(busLabel(_bus('a', route: 0, routeRun: 'Rt 10A')), '10A');
      expect(busLabel(_bus('a', route: 0, routeRun: '')), '?');
      expect(busLabel(_bus('a', route: 0, routeRun: 'Rt 10-1')), '10');
      expect(busLabel(_bus('a', route: 0, routeRun: 'RT 10')), '10');
      expect(busLabel(_bus('a', route: 0, routeRun: '10A')), '10A');
      expect(busLabel(_bus('a', route: 0, routeRun: 'route:0')), '?');
      expect(busLabel(_bus('a', route: 0, routeRun: 'trip:12345-abc')), '?');
      expect(busMarkers(tracking: {'a': _bus('a', route: 0, routeRun: 'Rt 10A')}, drawn: const {}, routeFilter: const {}, headings: HeadingSmoother(), now: _now).single.hue,
          RoutePalette.ofName('10A'));
    });
  });

  group('MapLayers', () {
    testWidgets('install adds images, sources and layers bottom to top', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        await MapLayers(surface, brightness: Brightness.light, pixelRatio: 1).install(stops: const [_mun]);
        final layerOrder = [for (final c in surface.calls) if (c.startsWith('layer ')) c.substring(6)];
        // Your stop is on top: at a terminal the buses park on it, and the
        // star must still show (taps pick buses first by distance, not by layer).
        expect(layerOrder, [
          MapLayers.routeCasingLayer,
          MapLayers.routeLineLayer,
          MapLayers.journeyCasingLayer,
          MapLayers.journeyLineLayer,
          MapLayers.journeyWalkLayer,
          MapLayers.stopsLayer,
          MapLayers.notchLayer,
          MapLayers.badgeLayer,
          MapLayers.myStopLayer,
        ]);
        expect((surface.layers[MapLayers.notchLayer]! as SymbolLayerProperties).symbolSortKey, isNotNull,
            reason: 'stale notches sit under fresh ones');
        expect(surface.images.keys, contains(MarkerImages.myStopId));
        expect(surface.layerMinZoom[MapLayers.stopsLayer], MapLayers.stopsMinZoom);
        expect(surface.layerMinZoom[MapLayers.myStopLayer], isNull, reason: 'your stop shows at every zoom');
        expect(surface.features(MapLayers.stopsSource).single['properties']['stopId'], '1150');
      });
    });

    testWidgets('images are registered once per id', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        final markers = busMarkers(
          tracking: {'a': _bus('a'), 'b': _bus('b'), 'c': _bus('c')},
          drawn: const {},
          routeFilter: const {},
          headings: HeadingSmoother(),
          now: _now,
        );
        await layers.updateBuses(markers);
        await layers.updateBuses(markers);
        final imageCalls = surface.calls.where((c) => c.startsWith('image bb-badge') || c.startsWith('image bb-notch'));
        expect(imageCalls, ['image ${MarkerImages.badgeId('10', stale: false, brightness: Brightness.light)}', 'image ${MarkerImages.notchId(RoutePalette.of(10), stale: false)}']);
        final f = surface.features(MapLayers.busesSource);
        expect(f, hasLength(3));
        expect(f.first['properties']['badge'], MarkerImages.badgeId('10', stale: false, brightness: Brightness.light));
        expect(f.first['properties']['heading'], 90);
      });
    });

    testWidgets('a failed badge image is retried and does not block the other buses', (tester) async {
      await tester.runAsync(() async {
        final surface = _FlakySurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        final markers = busMarkers(
          tracking: {'a': _bus('a'), 'b': _bus('b', route: 2, routeRun: 'Rt 2')},
          drawn: const {},
          routeFilter: const {},
          headings: HeadingSmoother(),
          now: _now,
        );
        final badge10 = MarkerImages.badgeId('10', stale: false, brightness: Brightness.light);
        surface.failOn = badge10;
        surface.calls.clear();
        await layers.updateBuses(markers);
        expect(surface.calls, contains('set ${MapLayers.busesSource}'), reason: 'one bad image must not skip the update');
        expect(surface.images.keys, contains(MarkerImages.badgeId('2', stale: false, brightness: Brightness.light)));
        expect(surface.images.keys, isNot(contains(badge10)));
        surface.failOn = null;
        await layers.updateBuses(markers);
        expect(surface.images.keys, contains(badge10), reason: 'retried on the next update');
      });
    });

    testWidgets('install after a style reload re-adds images and layers', (tester) async {
      await tester.runAsync(() async {
        final first = FakeMapSurface();
        final layers = MapLayers(first, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        final markers = busMarkers(tracking: {'a': _bus('a')}, drawn: const {}, routeFilter: const {}, headings: HeadingSmoother(), now: _now);
        await layers.updateBuses(markers);
        first.calls.clear();
        // A style reload drops every image and layer on the native side.
        await layers.install(stops: const []);
        await layers.updateBuses(markers);
        expect(first.calls, contains('layer ${MapLayers.badgeLayer}'));
        expect(first.calls, contains('image ${MarkerImages.badgeId('10', stale: false, brightness: Brightness.light)}'));
      });
    });

    testWidgets('install twice on the same style succeeds and leaves one of each', (tester) async {
      // onStyleLoaded can fire twice for one native style: the second install
      // finds our sources and layers already there.
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const [_mun]);
        await layers.install(stops: const [_mun]);
        expect(surface.sources.keys,
            unorderedEquals([
              MapLayers.routeSource,
              MapLayers.journeySource,
              MapLayers.journeyWalkSource,
              MapLayers.stopsSource,
              MapLayers.myStopSource,
              MapLayers.busesSource,
            ]));
        expect(surface.layers.keys,
            unorderedEquals([
              MapLayers.routeCasingLayer,
              MapLayers.routeLineLayer,
              MapLayers.journeyCasingLayer,
              MapLayers.journeyLineLayer,
              MapLayers.journeyWalkLayer,
              MapLayers.stopsLayer,
              MapLayers.myStopLayer,
              MapLayers.notchLayer,
              MapLayers.badgeLayer,
            ]));
        // Each install clears first, layers before the sources they draw from
        // (the first install finds nothing there, and shrugs).
        final removals = surface.calls.where((c) => c.startsWith('remove ')).toList();
        final oneClear = [
          for (final l in [
            MapLayers.myStopLayer,
            MapLayers.badgeLayer,
            MapLayers.notchLayer,
            MapLayers.stopsLayer,
            MapLayers.journeyWalkLayer,
            MapLayers.journeyLineLayer,
            MapLayers.journeyCasingLayer,
            MapLayers.routeLineLayer,
            MapLayers.routeCasingLayer,
          ])
            'remove layer $l',
          for (final src in [
            MapLayers.busesSource,
            MapLayers.myStopSource,
            MapLayers.stopsSource,
            MapLayers.journeyWalkSource,
            MapLayers.journeySource,
            MapLayers.routeSource,
          ])
            'remove source $src',
        ];
        expect(removals, [...oneClear, ...oneClear]);
        expect(surface.features(MapLayers.stopsSource), hasLength(1));
      });
    });

    testWidgets('install on a fresh style tolerates there being nothing to remove', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        await MapLayers(surface, brightness: Brightness.light, pixelRatio: 1).install(stops: const []);
        expect(surface.layers, hasLength(9));
      });
    });

    testWidgets('buses show up route by route while the rest of the images are still being made', (tester) async {
      await tester.runAsync(() async {
        final surface = _SlowImageSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        final slowBadge = MarkerImages.badgeId('2', stale: false, brightness: Brightness.light);
        surface.held.add(slowBadge);
        final markers = busMarkers(
          tracking: {'a': _bus('a'), 'b': _bus('b', route: 2, routeRun: 'Rt 2'), 'c': _bus('c')},
          drawn: const {},
          routeFilter: const {},
          headings: HeadingSmoother(),
          now: _now,
        );
        final done = layers.updateBuses(markers);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        // Route 10's images are in; route 2's badge is still being added.
        expect(surface.published, isNotEmpty, reason: 'do not wait for every image before drawing anything');
        expect(surface.published.last, unorderedEquals(['a', 'c']));
        surface.release(slowBadge);
        await done;
        expect(surface.published.last, unorderedEquals(['a', 'b', 'c']));
      });
    });

    testWidgets('your stop is one feature, or none', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        await layers.updateMyStop(_mun);
        expect(surface.features(MapLayers.myStopSource).single['geometry']['coordinates'], [-52.73, 47.57]);
        await layers.updateMyStop(null);
        expect(surface.features(MapLayers.myStopSource), isEmpty);
      });
    });
  });

  group('follow mode', () {
    test('the followed bus is emphasised and every other bus dimmed', () {
      final markers = busMarkers(
        tracking: {'a': _bus('a'), 'b': _bus('b')},
        drawn: const {},
        routeFilter: const {},
        headings: HeadingSmoother(),
        now: _now,
        followedVehicleId: 'a',
      );
      expect({for (final m in markers) m.vehicleId: m.emphasis}, {'a': MarkerEmphasis.followed, 'b': MarkerEmphasis.dimmed});
      final none = busMarkers(tracking: {'a': _bus('a')}, drawn: const {}, routeFilter: const {}, headings: HeadingSmoother(), now: _now);
      expect(none.single.emphasis, MarkerEmphasis.normal);
    });

    testWidgets('bus features carry scale, opacity and sort for the emphasis', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        await layers.updateBuses(busMarkers(
          tracking: {'a': _bus('a'), 'b': _bus('b')},
          drawn: const {},
          routeFilter: const {},
          headings: HeadingSmoother(),
          now: _now,
          followedVehicleId: 'a',
        ));
        final props = {for (final f in surface.features(MapLayers.busesSource)) f['properties']['vehicleId']: f['properties']};
        expect((props['a']['scale'], props['a']['opacity'], props['a']['sort']), (1.35, 1.0, 2));
        expect((props['b']['scale'], props['b']['opacity']), (1.0, 0.35));
      });
    });

    testWidgets('both bus layers size and fade each bus from its own feature', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        await MapLayers(surface, brightness: Brightness.light, pixelRatio: 1).install(stops: const []);
        for (final id in [MapLayers.notchLayer, MapLayers.badgeLayer]) {
          final p = surface.layers[id]! as SymbolLayerProperties;
          expect(p.iconSize, [Expressions.get, 'scale'], reason: id);
          expect(p.iconOpacity, [Expressions.get, 'opacity'], reason: id);
        }
      });
    });

    testWidgets('the route line sits under every other layer and splits into driven and ahead', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        final order = [for (final c in surface.calls) if (c.startsWith('layer ')) c.substring(6)];
        expect(order.take(2), [MapLayers.routeCasingLayer, MapLayers.routeLineLayer]);
        await layers.updateRoute(
          driven: const [[-52.70, 47.56], [-52.71, 47.56]],
          ahead: const [[-52.71, 47.56], [-52.72, 47.56]],
          color: RouteHue.green.line,
        );
        final f = surface.features(MapLayers.routeSource);
        expect([for (final x in f) x['properties']['part']], ['driven', 'ahead']);
        expect([for (final x in f) x['properties']['opacity']], [0.4, 1.0]);
        expect(f.first['geometry']['type'], 'LineString');
        await layers.clearRoute();
        expect(surface.features(MapLayers.routeSource), isEmpty);
      });
    });

    testWidgets('a second install also clears the route layers first', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        await layers.install(stops: const []);
        expect(surface.layers.keys.where((k) => k.startsWith('bb-route')), hasLength(2));
      });
    });
  });
}
