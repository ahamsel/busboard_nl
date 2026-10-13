import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_hit_test.dart';
import 'package:busboard_nl/ui/map/map_layers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

BusMarker _m(String id, double lat, double lon) =>
    BusMarker(vehicleId: id, lat: lat, lon: lon, heading: 0, label: '10', hue: RouteHue.ocean, stale: false);

void main() {
  test('tap radius shrinks as you zoom in', () {
    expect(tapRadiusMeters(13), 200);
    expect(tapRadiusMeters(15), 50);
    expect(tapRadiusMeters(10), 200, reason: 'clamped below zoom 13');
    expect(tapRadiusMeters(14.5), inExclusiveRange(50, 100));
    expect(tapRadiusMeters(14.5), closeTo(70.7, 0.1));
    expect(tapRadiusMeters(18), closeTo(6.25, 0.001));
    expect(tapRadiusMeters(22), closeTo(6.25, 0.001), reason: 'clamped above zoom 18');
  });

  test('nearestBus picks the closest drawn bus within the radius', () {
    final drawn = [_m('far', 47.5700, -52.7300), _m('near', 47.5601, -52.7100)];
    expect(nearestBus(const LatLng(47.5600, -52.7100), 50, drawn), 'near');
    expect(nearestBus(const LatLng(47.6000, -52.7100), 50, drawn), isNull);
  });

  test('nearestStop picks the closest stop within the radius', () {
    const a = StopInfo(stopId: 'a', stopName: 'A', stopLat: 47.5600, stopLon: -52.7100);
    const b = StopInfo(stopId: 'b', stopName: 'B', stopLat: 47.5610, stopLon: -52.7100);
    expect(nearestStop(const LatLng(47.5608, -52.7100), 200, const [a, b])?.stopId, 'b');
    expect(nearestStop(const LatLng(47.6, -52.7), 50, const [a, b]), isNull);
  });
}
