import 'package:busboard_nl/domain/trip_planner/walking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('haversine: 0.01339° north and 0.021821° west at 47.57° N is about 2.2 km', () {
    final d = haversineMeters(47.57337, -52.735682, 47.55998, -52.757503);
    expect(d, closeTo(2214, 15));
  });

  test('haversine: 0.004° of longitude at 47.57° N is about 300 m', () {
    expect(haversineMeters(47.57, -52.75, 47.57, -52.746), closeTo(300, 3));
  });

  test('walk time: ×1.3 at 4.5 km/h, rounded up to the minute', () {
    expect(walkSeconds(0), 0);
    expect(walkSeconds(1), 60); // any walk is at least a minute
    expect(walkSeconds(300), 360); // 390 m at 1.25 m/s = 312 s → 6 min
    expect(walkSeconds(400), 420); // 520 m → 416 s → 7 min
    expect(walkSeconds(800), 840); // 1040 m → 832 s → 14 min
  });
}
