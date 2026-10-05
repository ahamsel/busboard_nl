import 'package:busboard_nl/data/realtime/service_alert_models.dart';
import 'package:busboard_nl/ui/alerts/service_alert_card.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('alert target tags expose their full multiline label', (
    tester,
  ) async {
    const stopName = 'Freshwater Rd before Anderson Ave · 3080';
    const alert = ServiceAlert(
      sourceIds: {'alert'},
      header: 'Stop out of service',
      description: 'Construction',
      cause: ServiceAlertCause.construction,
      effect: ServiceAlertEffect.noService,
      severity: ServiceAlertSeverity.warning,
      activePeriods: [],
      targets: [ServiceAlertTarget(stopId: '3080')],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: BBTheme.light(),
        home: const Center(
          child: SizedBox(
            width: 320,
            child: ServiceAlertCard(
              alert: alert,
              stopNames: {'3080': 'Freshwater Rd before Anderson Ave'},
            ),
          ),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text(stopName));
    expect(label.maxLines, isNull);
    expect(label.softWrap, isTrue);
    expect(label.overflow, TextOverflow.visible);
    expect(tester.takeException(), isNull);
  });
}
