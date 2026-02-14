import 'package:flutter_test/flutter_test.dart';
import 'package:busboard_nl/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Just verify the app widget builds without error
    await tester.pumpWidget(const BusboardApp());
    expect(find.text('BusBoard NL'), findsAny);
  });
}
