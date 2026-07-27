import 'package:fund_flow/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fresh journey reaches the Zero mobile product', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    if (find.text('Continue').evaluate().isNotEmpty) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter Fund Flow'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Overview'), findsWidgets);
    expect(find.bySemanticsLabel('Ask your money'), findsOneWidget);
    await tester.tap(find.text('Transactions').last);
    await tester.pumpAndSettle();
    expect(find.text('Transactions'), findsWidgets);
    await tester.tap(find.text('Overview').last);
    await tester.pumpAndSettle();
    expect(find.text('Spent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
