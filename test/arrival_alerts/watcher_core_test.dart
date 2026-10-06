// test/arrival_alerts/watcher_core_test.dart
import 'package:busboard_nl/data/arrival_alerts/alert_notifications.dart';
import 'package:busboard_nl/data/arrival_alerts/alert_store.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/domain/arrival_alerts/alert_copy.dart';
import 'package:busboard_nl/domain/arrival_alerts/arrival_alert.dart';
import 'package:busboard_nl/platform/android_alert_watcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class FakeNotifications implements AlertNotifications {
  final shown = <AlertMessage>[];
  final scheduled = <(AlertMessage, DateTime)>[];
  int cancels = 0;
  bool throwOnShow = false;
  @override
  Future<void> init() async {}
  @override
  Future<bool> permissionGranted() async => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> show(AlertMessage m) async {
    if (throwOnShow) throw Exception('notification failed');
    shown.add(m);
  }

  @override
  Future<void> schedule(AlertMessage m, DateTime at) async =>
      scheduled.add((m, at));
  @override
  Future<void> cancelScheduled() async => cancels++;
}

final t0 = DateTime(2026, 10, 6, 8, 0);
final _alert = ArrivalAlert(
  stopId: '1150',
  stopName: 'MUN Centre',
  routeShortName: '10',
  headsign: 'MUN-CNA-MI',
  tripId: 't1',
  scheduledAt: DateTime(2026, 10, 6, 8, 12),
  expectedAt: DateTime(2026, 10, 6, 8, 12),
  live: true,
  leadMinutes: 5,
  setAt: t0,
  lastSeenAt: t0,
);

MetrobusDeparturesResult _live(int h, int m) => MetrobusDeparturesResult(
  departures: [
    MetrobusDeparture(
      routeRun: '10-4',
      routeShortName: '10',
      vehicle: '1415',
      scheduledTime: '',
      predictedTime: '',
      headsign: 'MUN-CNA-MI',
      currentLocation: '',
      isTracked: true,
      tripId: 't1',
      scheduledDepartureSeconds: 8 * 3600 + 12 * 60,
      predictedDepartureSeconds: h * 3600 + m * 60,
      isRealtime: true,
    ),
  ],
  succeeded: true,
  realtimeAvailable: true,
  serviceOperating: true,
  fetchedAt: t0,
);

void main() {
  late AlertStore store;
  late FakeNotifications notes;
  late List<(String, String)> ongoing;
  late DateTime now;

  WatcherCore core(Future<MetrobusDeparturesResult> Function(ArrivalAlert) fetch) =>
      WatcherCore(
        store: store,
        fetch: fetch,
        notifications: notes,
        updateOngoing: (t, x) async => ongoing.add((t, x)),
        clock: () => now,
        use24h: true,
      );

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    store = AlertStore();
    notes = FakeNotifications();
    ongoing = [];
    now = t0.add(const Duration(minutes: 1));
    await store.write(_alert);
  });

  test(
    'a check updates the countdown, re-times the store and the backup',
    () async {
      expect(
        await core((_) async => _live(8, 14)).check(),
        WatchOutcome.keepGoing,
      );
      expect(ongoing.single, ('Route 10 to MUN-CNA-MI', 'About 13 min · live'));
      expect((await store.read())!.expectedAt, DateTime(2026, 10, 6, 8, 14));
      expect(
        notes.scheduled.single.$2,
        DateTime(2026, 10, 6, 8, 11),
      ); // 8:14 − 5 + 2 min grace
      expect(notes.shown, isEmpty);
    },
  );

  test('the fetch is handed the stored alert', () async {
    ArrivalAlert? asked;
    await core((a) async {
      asked = a;
      return _live(8, 14);
    }).check();
    expect(asked!.isSameAlert(_alert), isTrue);
    expect(asked!.tripId, 't1');
  });

  test('fires once, cancels the backup, keeps counting until due', () async {
    now = DateTime(2026, 10, 6, 8, 9);
    final c = core((_) async => _live(8, 14));
    expect(await c.check(), WatchOutcome.keepGoing);
    expect(notes.shown.single.title, 'Route 10 is about 5 min away');
    expect(notes.cancels, 1);
    now = DateTime(2026, 10, 6, 8, 10);
    expect(await c.check(), WatchOutcome.keepGoing);
    expect(notes.shown, hasLength(1));
    now = DateTime(2026, 10, 6, 8, 14);
    expect(await c.check(), WatchOutcome.finished);
    expect(await store.read(), isNull);
  });

  test(
    'a failing feed still checks (and falls back after 2 minutes)',
    () async {
      now = t0.add(const Duration(minutes: 3));
      expect(
        await core((_) async => throw Exception('down')).check(),
        WatchOutcome.keepGoing,
      );
      expect(ongoing.single.$2, startsWith('Live tracking lost'));
    },
  );

  test('a cancel during the fetch is not undone by the check', () async {
    final c = core((_) async {
      await store
          .clear(); // the rider taps Cancel while the request is in flight
      return _live(8, 14);
    });
    expect(await c.check(), WatchOutcome.finished);
    expect(await store.read(), isNull);
    expect(ongoing, isEmpty);
    expect(notes.shown, isEmpty);
    expect(notes.scheduled, isEmpty);
  });

  test('a replacement during the fetch stops this check without touching the new alert', () async {
    final replacement = _alert.copyWith().toJson()
      ..['setAt'] = t0.add(const Duration(minutes: 1)).millisecondsSinceEpoch;
    final c = core((_) async {
      await store.write(ArrivalAlert.fromJson(replacement)!);
      return _live(8, 14);
    });
    expect(await c.check(), WatchOutcome.superseded);
    expect((await store.read())!.setAt, t0.add(const Duration(minutes: 1)));
    expect(
      (await store.read())!.expectedAt,
      DateTime(2026, 10, 6, 8, 12),
    ); // untouched
    expect(ongoing, isEmpty);
    expect(notes.shown, isEmpty);
    expect(notes.scheduled, isEmpty);
    expect(notes.cancels, 0);
  });

  test('no stored alert: stop', () async {
    await store.clear();
    expect(
      await core((_) async => _live(8, 14)).check(),
      WatchOutcome.finished,
    );
  });

  test(
    'fire and finished in the same check: shown once, store cleared',
    () async {
      now = DateTime(2026, 10, 6, 8, 14);
      expect(
        await core((_) async => _live(8, 14)).check(),
        WatchOutcome.finished,
      );
      expect(notes.shown, hasLength(1));
      expect(await store.read(), isNull);
    },
  );

  test('a failing notification cannot block finishing', () async {
    notes.throwOnShow = true;
    now = DateTime(2026, 10, 6, 8, 14);
    expect(
      await core((_) async => _live(8, 14)).check(),
      WatchOutcome.finished,
    );
    expect(await store.read(), isNull);
  });

  test('show throwing on fire: no throw, firedAt persisted, backup kept, no second fire', () async {
    notes.throwOnShow = true;
    now = DateTime(2026, 10, 6, 8, 9);
    final c = core((_) async => _live(8, 14));
    expect(await c.check(), WatchOutcome.keepGoing);
    expect((await store.read())!.firedAt, isNotNull);
    expect(notes.cancels, 0);
    notes.throwOnShow = false;
    now = DateTime(2026, 10, 6, 8, 10);
    expect(await c.check(), WatchOutcome.keepGoing);
    expect(notes.shown, isEmpty);
  });

  group('backupTimeFor', () {
    test('a future backup time is alertAt + grace', () {
      expect(
        backupTimeFor(_alert, DateTime(2026, 10, 6, 8, 1)),
        DateTime(2026, 10, 6, 8, 9),
      );
    });
    test('at or after now: none', () {
      expect(backupTimeFor(_alert, DateTime(2026, 10, 6, 8, 9)), isNull);
      expect(backupTimeFor(_alert, DateTime(2026, 10, 6, 8, 30)), isNull);
    });
    test('already fired: none', () {
      expect(
        backupTimeFor(
          _alert.copyWith(firedAt: t0),
          DateTime(2026, 10, 6, 8, 1),
        ),
        isNull,
      );
    });
  });
}
