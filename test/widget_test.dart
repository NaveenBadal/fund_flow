import 'package:expense_manager/theme/app_theme.dart';
import 'package:expense_manager/widgets/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('premium card renders with bundled design system', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(null),
        home: const Scaffold(body: AppCard(child: Text('Balance'))),
      ),
    );

    expect(find.text('Balance'), findsOneWidget);
    expect(find.byType(AppCard), findsOneWidget);
  });
}
