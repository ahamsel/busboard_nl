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
        expect(layerOrder, [MapLayers.stopsLayer, MapLayers.myStopLayer, MapLayers.notchLayer, MapLayers.badgeLayer]);
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
        expect(surface.sources.keys, unorderedEquals([MapLayers.stopsSource, MapLayers.myStopSource, MapLayers.busesSource]));
        expect(surface.layers.keys,
            unorderedEquals([MapLayers.stopsLayer, MapLayers.myStopLayer, MapLayers.notchLayer, MapLayers.badgeLayer]));
        // Each install clears first, layers before the sources they draw from
        // (the first install finds nothing there, and shrugs).
        final removals = surface.calls.where((c) => c.startsWith('remove ')).toList();
        final oneClear = [
          for (final l in [MapLayers.badgeLayer, MapLayers.notchLayer, MapLayers.myStopLayer, MapLayers.stopsLayer]) 'remove layer $l',
          for (final src in [MapLayers.busesSource, MapLayers.myStopSource, MapLayers.stopsSource]) 'remove source $src',
        ];
        expect(removals, [...oneClear, ...oneClear]);
        expect(surface.features(MapLayers.stopsSource), hasLength(1));
      });
    });

    testWidgets('install on a fresh style tolerates there being nothing to remove', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        await MapLayers(surface, brightness: Brightness.light, pixelRatio: 1).install(stops: const []);
        expect(surface.layers, hasLength(4));
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
}
