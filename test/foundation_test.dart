import 'package:expense_manager/app/fund_flow_app.dart';
import 'package:expense_manager/ui/components/current_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('greenfield shell and single-surface field render cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(const FundFlowApp());
    expect(find.text('Ask'), findsWidgets);
    expect(find.byType(CurrentField), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.decoration, isA<InputDecoration>());
    expect(textField.decoration!.filled, isNot(true));
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation remains bounded at 200 percent text', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(
          size: Size(320, 720),
          textScaler: TextScaler.linear(2),
        ),
        child: FundFlowApp(),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Activity'), findsOneWidget);
  });
}
