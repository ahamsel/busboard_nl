import 'dart:async';

import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/bus_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('open bus sheet reacts to live vehicle updates', (tester) async {
    final controller =
        StreamController<Map<String, BusTrackingState>>.broadcast();
    addTearDown(controller.close);
    final now = DateTime.now();
    final initial = _busState(
      now: now,
      latitude: 47.50000,
      longitude: -52.70000,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          busTrackingStreamProvider.overrideWith((ref) => controller.stream),
          serviceUpdatesProvider.overrideWith(
            (ref) => Stream.value(
              ServiceUpdates(
                alerts: const [],
                serviceStatus: null,
                fetchedAt: now,
                feedTimestamp: now,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: BBTheme.light(),
          home: Scaffold(body: BusBottomSheet(bus: initial)),
        ),
      ),
    );

    expect(find.text('47.50000, -52.70000'), findsOneWidget);
    expect(find.text('Bus 1311'), findsOneWidget);

    controller.add({
      '1311': _busState(
        now: now.add(const Duration(seconds: 10)),
        latitude: 47.51000,
        longitude: -52.71000,
      ),
    });
    await tester.pump();

    expect(find.text('47.51000, -52.71000'), findsOneWidget);
    expect(find.text('47.50000, -52.70000'), findsNothing);
  });
}

BusTrackingState _busState({
  required DateTime now,
  required double latitude,
  required double longitude,
}) {
  return BusTrackingState(
    routeRun: '10-1',
    vehicleId: '1311',
    routeNumber: 10,
    headsign: 'Kelsey Drive',
    currentTripId: 'trip-10',
    lat: latitude,
    lon: longitude,
    heading: 90,
    speedKmh: 30,
    lastGpsTime: now,
    status: BusStatus.active,
    lastUpdateTime: now,
  );
}
