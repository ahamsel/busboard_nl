import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:flutter_test/flutter_test.dart';

GtfsRepository _repo() {
  final repo = GtfsRepository();
  for (final (id, short) in [('r10', '10'), ('r2', '2'), ('r15', '15'), ('rX', 'X1')]) {
    repo.routesById[id] = RouteInfo(routeId: id, routeShortName: short, routeLongName: '');
  }
  for (final (trip, route) in [('t1', 'r10'), ('t2', 'r2'), ('t3', 'r10'), ('t4', 'r15'), ('t5', 'rX'), ('t6', 'missing')]) {
    repo.tripsById[trip] = TripInfo(tripId: trip, routeId: route, serviceId: 's', tripHeadsign: '', directionId: 0);
  }
  repo.stopTimesByStopId['1150'] = [
    for (final trip in ['t1', 't2', 't3', 't4', 't5', 't6', 'unknown-trip'])
      StopTimeRow(tripId: trip, arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: '1150', stopSequence: 1),
  ];
  return repo;
}

void main() {
  test('distinct routes serving a stop, numeric order, then alphanumeric', () {
    expect(_repo().routeShortNamesForStop('1150'), ['2', '10', '15', 'X1']);
  });

  test('unknown stop has no routes', () {
    expect(_repo().routeShortNamesForStop('9999'), isEmpty);
  });

  test('result is memoised and unmodifiable', () {
    final repo = _repo();
    final a = repo.routeShortNamesForStop('1150');
    expect(identical(a, repo.routeShortNamesForStop('1150')), isTrue);
    expect(() => a.add('99'), throwsUnsupportedError);
  });

  test('compareRouteNames is a consistent total order', () {
    final names = ['X1', '10', '2', 'A', '15'];
    names.sort(GtfsRepository.compareRouteNames);
    expect(names, ['2', '10', '15', 'A', 'X1']);
  });

  test('equal numeric values are tie-broken deterministically', () {
    final a = ['10', '010']..sort(GtfsRepository.compareRouteNames);
    final b = ['010', '10']..sort(GtfsRepository.compareRouteNames);
    expect(a, ['010', '10']);
    expect(b, ['010', '10']);
  });

  test('only digit-only names are numeric', () {
    final names = ['0x1A', '+5', '2', ' 10', '', '10']..sort(GtfsRepository.compareRouteNames);
    expect(names, ['2', '10', '', ' 10', '+5', '0x1A']);
  });

  test('compareRouteNames is antisymmetric and zero only for equal names', () {
    const names = ['2', '10', '010', 'A', 'X1', '', '+5'];
    for (final a in names) {
      for (final b in names) {
        final ab = GtfsRepository.compareRouteNames(a, b);
        final ba = GtfsRepository.compareRouteNames(b, a);
        expect(ab.sign, -ba.sign, reason: '"$a" vs "$b"');
        expect(ab == 0, a == b, reason: '"$a" vs "$b"');
      }
    }
  });
}
