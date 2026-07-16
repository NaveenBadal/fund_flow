import 'package:expense_manager/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expressive theme renders shaped Material components', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(null),
        home: const Scaffold(
          body: Card(
            child: Padding(padding: EdgeInsets.all(16), child: Text('Balance')),
          ),
        ),
      ),
    );

    expect(find.text('Balance'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
  });
}
