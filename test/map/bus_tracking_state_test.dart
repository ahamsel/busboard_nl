import 'package:busboard_nl/domain/map/bus_track.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fetched = DateTime(2026, 10, 5, 12, 0, 10);
  final gps = DateTime(2026, 10, 5, 12, 0, 0);

  BusTrack track({bool offRoute = false, bool snapped = true}) => BusTrack(
        vehicleId: '2573',
        routeNumber: 10,
        routeRun: 'Rt 10',
        headsign: 'Kelsey Drive',
        fixes: [
          TrackFix(
            gpsTime: gps,
            fetchTime: fetched,
            lat: 47.5601,
            lon: -52.7,
            heading: 90,
            speedKmh: 29,
            tripId: 'trip',
            shapeId: 'shape',
            progress: offRoute || !snapped ? null : 250,
            snappedLat: offRoute || !snapped ? null : 47.5600,
            snappedLon: offRoute || !snapped ? null : -52.7001,
            offRoute: offRoute,
          ),
        ],
        lastFixAt: fetched,
      );

  test('fromTrack copies the latest fix and reports active', () {
    final s = BusTrackingState.fromTrack(track(), stale: false);
    expect(s.status, BusStatus.active);
    expect(s.vehicleId, '2573');
    expect(s.routeNumber, 10);
    expect(s.headsign, 'Kelsey Drive');
    expect(s.currentTripId, 'trip');
    expect(s.shapeId, 'shape');
    expect(s.lat, 47.5600);
    expect(s.lon, -52.7001);
    expect(s.progress, 250);
    expect(s.speedKmh, 29);
    expect(s.lastGpsTime, gps);
    expect(s.lastUpdateTime, fetched);
  });

  test('fromTrack reports stale when asked, even for an off-route bus', () {
    expect(BusTrackingState.fromTrack(track(), stale: true).status, BusStatus.stale);
    expect(BusTrackingState.fromTrack(track(offRoute: true), stale: true).status, BusStatus.stale);
  });

  test('fromTrack reports offRoute and falls back to the raw position', () {
    final s = BusTrackingState.fromTrack(track(offRoute: true), stale: false);
    expect(s.status, BusStatus.offRoute);
    expect(s.lat, 47.5601);
    expect(s.lon, -52.7);
    expect(s.progress, isNull);
  });
}
