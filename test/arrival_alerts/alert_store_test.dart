import 'package:busboard_nl/data/arrival_alerts/alert_store.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final _alert = ArrivalAlert(
  stopId: '1150',
  stopName: 'MUN Centre',
  routeShortName: '10',
  headsign: 'MUN-CNA-MI',
  tripId: 't1',
  scheduledAt: DateTime(2026, 10, 6, 8, 12),
  expectedAt: DateTime(2026, 10, 6, 8, 14),
  live: true,
  leadMinutes: 5,
  setAt: DateTime(2026, 10, 6, 8, 0),
);

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  test('empty store: no alert, lead 5', () async {
    final store = AlertStore();
    expect(await store.read(), isNull);
    expect(await store.lastLead(), 5);
  });

  test('write, read, clear', () async {
    final store = AlertStore();
    await store.write(_alert);
    expect((await store.read())!.toJson(), _alert.toJson());
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('a second store instance (another isolate) sees the same alert', () async {
    await AlertStore().write(_alert);
    expect((await AlertStore().read())!.tripId, 't1');
  });

  test('remembers the last lead time', () async {
    final store = AlertStore();
    await store.saveLead(10);
    expect(await store.lastLead(), 10);
  });
}
