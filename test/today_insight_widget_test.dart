import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fund_flow/app/app_controller.dart';
import 'package:fund_flow/app/app_state.dart';
import 'package:fund_flow/domain/preferences.dart';
import 'package:fund_flow/domain/transaction.dart';
import 'package:fund_flow/ui2/components/flow_sheet_inset.dart';
import 'package:fund_flow/ui2/screens/today_screen.dart';
import 'package:fund_flow/ui2/tokens/flow_theme.dart';

/// The shell test deliberately avoids Riverpod by injecting plain widgets.
/// Today cannot be tested that way — it reads the controller directly — so
/// this establishes the override pattern the rest of the screens can follow.
class _FixedController extends AppController {
  _FixedController(this._state);
  final AppState _state;

  @override
  Future<AppState> build() async => _state;
}

void _usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Builds the screen with its state already resolved.
///
/// The controller is asynchronous, so a plain ProviderScope would render one
/// frame of AsyncLoading — and the screen calls requireValue, which throws on
/// exactly that frame. Awaiting the provider in a container first means the
/// widget only ever sees data, which is also what the running app shows.
Future<Widget> _host(
  WidgetTester tester,
  List<MoneyTransaction> transactions, {
  ValueChanged<String>? onAsk,
}) async {
  final container = ProviderContainer(
    overrides: [
      appControllerProvider.overrideWith(
        () => _FixedController(
          AppState(
            preferences: const AppPreferences(),
            transactions: transactions,
            conversation: const [],
            aiConnection: AiConnection.connected,
            threads: const [],
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(appControllerProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: FlowTheme.light(),
      home: Scaffold(
        body: TodayScreen(
          onReview: () {},
          onOpenSettings: () {},
          onAsk: onAsk ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Today says what it noticed without being asked', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(await _host(tester, _withDuplicateCharges()));
    await tester.pumpAndSettle();

    // The point of the section: this is on screen before anyone asks
    // anything, with no network involved.
    expect(find.text('WHAT I NOTICED'), findsOneWidget);
    expect(find.textContaining('charged twice'), findsWidgets);
  });

  testWidgets('a noticed thing hands off to the agent when tapped', (
    tester,
  ) async {
    _usePhone(tester);
    String? asked;
    await tester.pumpWidget(
      await _host(tester, _withDuplicateCharges(), onAsk: (v) => asked = v),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('charged twice').first);
    await tester.pumpAndSettle();

    // A card states the finding; the conversation is what explains it.
    expect(asked, isNotNull);
    expect(asked, contains('duplicates?'));
  });

  testWidgets('an ordinary ledger is not given something to worry about', (
    tester,
  ) async {
    _usePhone(tester);
    await tester.pumpWidget(
      await _host(tester, [
        _transaction(DateTime(2026, 7, 10), merchant: 'Zomato'),
        _transaction(DateTime(2026, 7, 12), merchant: 'Metro'),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('WHAT I NOTICED'), findsNothing);
  });

  testWidgets('sheet content lifts clear of an open keyboard', (tester) async {
    // The chat sheet sat at a fixed height and never insetted, so an open
    // keyboard covered the composer.
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: 320)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FlowSheetInset(child: SizedBox(height: 100)),
        ),
      ),
    );
    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(FlowSheetInset),
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding, const EdgeInsets.only(bottom: 320));
  });

  testWidgets('no keyboard means no wasted space', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FlowSheetInset(child: SizedBox(height: 100)),
        ),
      ),
    );
    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(FlowSheetInset),
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding, EdgeInsets.zero);
  });
}

/// Two charges alike enough and close enough to be worth a look, dated near
/// enough to now that they still count as news.
List<MoneyTransaction> _withDuplicateCharges() {
  final now = DateTime.now();
  return [
    _transaction(
      now.subtract(const Duration(days: 2)),
      merchant: 'Adobe',
      amountMinor: 169900,
      id: 1,
    ),
    _transaction(
      now.subtract(const Duration(days: 1)),
      merchant: 'Adobe',
      amountMinor: 169900,
      id: 2,
    ),
  ];
}

MoneyTransaction _transaction(
  DateTime occurredAt, {
  String merchant = 'Cafe River',
  int amountMinor = 25000,
  int? id,
}) => MoneyTransaction(
  id: id,
  amountMinor: amountMinor,
  currency: 'INR',
  direction: TransactionDirection.outgoing,
  merchant: merchant,
  category: 'Food',
  occurredAt: occurredAt,
  source: TransactionSource.message,
);
