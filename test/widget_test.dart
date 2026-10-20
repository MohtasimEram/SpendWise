import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/main.dart';

void main() {
  testWidgets('Smoke test SpendWiseApp', (WidgetTester tester) async {
    // Basic instantiation test for SetupErrorApp widget
    await tester.pumpWidget(const SetupErrorApp(error: 'Test error'));
    expect(find.text('SpendWise could not start'), findsOneWidget);
  });
}
