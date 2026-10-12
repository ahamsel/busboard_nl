import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/gtfs/headsign.dart';
import 'package:flutter_test/flutter_test.dart';

/// A repo where each trip is `(tripId, routeShortName, headsign, stops)` and
/// visits [stops] in order (stop_sequence 1, 2, ...).
GtfsRepository _repo(List<(String, String, String, List<String>)> trips) {
  final repo = GtfsRepository();
  for (final (trip, route, headsign, stops) in trips) {
    repo.routesById['r$route'] = RouteInfo(routeId: 'r$route', routeShortName: route, routeLongName: '');
    repo.tripsById[trip] = TripInfo(tripId: trip, routeId: 'r$route', serviceId: 's', tripHeadsign: headsign, directionId: 0);
    for (var i = 0; i < stops.length; i++) {
      repo.stopTimesByStopId.putIfAbsent(stops[i], () => []).add(StopTimeRow(
          tripId: trip, arrivalTime: '08:00:00', departureTime: '08:00:00', stopId: stops[i], stopSequence: i + 1));
    }
  }
  return repo;
}

Map<String, List<String>> _directions(GtfsRepository repo, String stopId) => {
      for (final d in repo.routeDirectionsForStop(stopId)) d.routeShortName: d.destinations,
    };

void main() {
  group('headsignDestination', () {
    test('takes the last " - " segment as the destination', () {
      expect(headsignDestination('AVALON MALL - MUN CENTRE - DOWNTOWN'), 'Downtown');
      expect(headsignDestination('MOUNT PEARL SQUARE - DONOVANS'), 'Donovans');
    });

    test('splits a hyphen-only list of single words', () {
      expect(headsignDestination('MUN-CNA-MI'), 'MI');
    });

    test('keeps a hyphenated place name whole', () {
      expect(headsignDestination("PORTUGAL COVE-ST. PHILIP'S"), "Portugal Cove-St. Philip's");
    });

    test('title-cases all-caps text, keeping acronyms and small words', () {
      expect(headsignDestination('THE VILLAGE'), 'The Village');
      expect(headsignDestination('EXPRESS TO MUN CENTRE'), 'Express to MUN Centre');
      expect(headsignDestination('MUN CENTRE - MOUNT SCIO RD - CNA'), 'CNA');
      expect(headsignDestination('EXPRESS HSC'), 'Express HSC');
    });

    test('leaves mixed-case text as the feed wrote it', () {
      expect(headsignDestination('MI - Eastern Health'), 'Eastern Health');
    });

    test('blank headsign has no destination', () {
      expect(headsignDestination(''), '');
      expect(headsignDestination('  '), '');
    });
  });

  group('routeDirectionsForStop', () {
    test('one destination per route, routes in compareRouteNames order', () {
      final repo = _repo([
        ('a', '10', 'AVALON MALL - MUN CENTRE - DOWNTOWN', ['1600', '1150', '9000']),
        ('b', '2', 'PLEASANTVILLE - THE VILLAGE', ['1600', '1000']),
      ]);
      expect(repo.routeDirectionsForStop('1600').map((d) => d.routeShortName), ['2', '10']);
      expect(_directions(repo, '1600'), {'2': ['The Village'], '10': ['Downtown']});
    });

    test('both directions of a route, most frequent first', () {
      final repo = _repo([
        ('a', '16', 'AVALON MALL - MUN CENTRE', ['1600', '1150']),
        ('b', '16', 'AVALON MALL - KENMOUNT TERRACE', ['1600', '1700']),
        ('c', '16', 'AVALON MALL - KENMOUNT TERRACE', ['1600', '1700']),
      ]);
      expect(_directions(repo, '1600'), {'16': ['Kenmount Terrace', 'MUN Centre']});
    });

    test('equally frequent destinations are ordered alphabetically', () {
      final repo = _repo([
        ('a', '23', 'STAVANGER DRIVE', ['1200', '1300']),
        ('b', '23', 'AVALON MALL', ['1200', '1100']),
      ]);
      expect(_directions(repo, '1200'), {'23': ['Avalon Mall', 'Stavanger Drive']});
    });

    test('shows at most two destinations', () {
      final repo = _repo([
        ('a', '1', 'A - ONE', ['1000', '1']),
        ('b', '1', 'B - TWO', ['1000', '2']),
        ('c', '1', 'C - TWO', ['1000', '3']),
        ('d', '1', 'C - THREE', ['1000', '4']),
      ]);
      expect(_directions(repo, '1000'), {'1': ['Two', 'One']});
    });

    test('trips that end at the stop do not give it a direction', () {
      final repo = _repo([
        ('a', '24', 'MUN EXPRESS', ['1000', '1150']),
        ('b', '10', 'MUN CENTRE - AVALON MALL - KELSEY DRIVE', ['1150', '1600']),
        ('c', '10', 'AVALON MALL - MUN CENTRE - DOWNTOWN', ['1600', '1150']),
      ]);
      // Route 24 only terminates here: it keeps its chip, with no direction.
      expect(_directions(repo, '1150'), {'10': ['Kelsey Drive'], '24': <String>[]});
    });

    test('a blank headsign gives no direction', () {
      final repo = _repo([('a', '9', '', ['1000', '1100'])]);
      expect(_directions(repo, '1000'), {'9': <String>[]});
    });

    test('unknown stop has no routes', () {
      expect(_repo([]).routeDirectionsForStop('9999'), isEmpty);
    });

    test('result is memoised and unmodifiable', () {
      final repo = _repo([('a', '9', 'MI - CNA - EAST WHITE HILLS', ['1000', '1100'])]);
      final first = repo.routeDirectionsForStop('1000');
      expect(identical(first, repo.routeDirectionsForStop('1000')), isTrue);
      expect(() => first.add(first.first), throwsUnsupportedError);
      expect(() => first.first.destinations.add('X'), throwsUnsupportedError);
    });
  });
}
