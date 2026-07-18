import 'dart:io';

import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/providers/expense_provider.dart';
import 'package:expense_manager/screens/activity_screen.dart';
import 'package:expense_manager/screens/settings_screen.dart';
import 'package:expense_manager/screens/onboarding_screen.dart';
import 'package:expense_manager/services/database_helper.dart';
import 'package:expense_manager/theme/app_theme.dart';
import 'package:expense_manager/widgets/money_chat_sheet.dart';
import 'package:expense_manager/widgets/expense_form_sheet.dart';
import 'package:expense_manager/widgets/agent_artifact_card.dart';
import 'package:expense_manager/models/agent_artifact.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory databaseDirectory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseDirectory = await Directory.systemTemp.createTemp(
      'expense-manager-accessibility-test-',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
    await DatabaseHelper.instance.insertExpense(
      Expense(
        amount: 450,
        currency: 'INR',
        merchant: 'Accessible Cafe',
        category: 'Food',
        date: DateTime.now(),
        originalSms: '',
      ),
    );
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    await databaseDirectory.delete(recursive: true);
  });

  testWidgets('Activity supports narrow screens and 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 720),
              textScaler: TextScaler.linear(2),
            ),
            child: const ActivityScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.byTooltip('More activity actions'), findsOneWidget);
    expect(find.byTooltip('Hide amounts'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('You remains usable on a narrow screen at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 720),
              textScaler: TextScaler.linear(2),
            ),
            child: SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('You'), findsOneWidget);
    expect(
      find.text(
        'Control Flow intelligence, data sources, privacy, and preferences.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('AI-first onboarding supports 200% text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: OnboardingScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Transaction messages become answers.'), findsOneWidget);
    await tester.tap(find.text('Set up Flow'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Connect Flow intelligence'), findsOneWidget);
    expect(find.text('Connect intelligence'), findsOneWidget);
  });

  testWidgets('Flow input stays visible when the keyboard opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: const MoneyChatSheet(fullScreen: true),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Flow'), findsOneWidget);
    expect(find.text('Connect intelligence to ask Flow'), findsOneWidget);
  });

  testWidgets('agent financial cards support narrow screens and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1400);
    tester.view.devicePixelRatio = 2;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(null),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: AgentArtifactCard(
                onPrompt: (_) {},
                artifact: const AgentArtifact(
                  kind: AgentArtifactKind.breakdown,
                  title: 'Spending breakdown',
                  subtitle: '24 local records checked',
                  data: {
                    'groups': [
                      {
                        'label': 'Food and dining',
                        'currency': 'INR',
                        'direction': 'expense',
                        'count': 12,
                        'total': 12450,
                      },
                    ],
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Spending breakdown'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Transaction form gives field-specific validation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: Scaffold(body: ExpenseFormSheet(onSave: (_) async {})),
        ),
      ),
    );
    await tester.pump();

    final save = find.text('Add transaction').last;
    await tester.tap(save);
    await tester.pump();

    expect(find.text('Enter an amount greater than zero'), findsOneWidget);
    expect(
      find.text('Enter where this money came from or went to'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity filters open in a focused sheet', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [expenseListProvider.overrideWith(_PopulatedExpenses.new)],
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: const ActivityScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byTooltip('Filter activity'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Filter activity'), findsOneWidget);
    expect(find.text('Show results'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uncertain SMS records expose focused review decisions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [expenseListProvider.overrideWith(_ReviewExpenses.new)],
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: const ActivityScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('1 to review'), findsOneWidget);
    await tester.tap(find.text('Needs review'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Correct'), findsOneWidget);
    expect(find.text('Not a transaction'), findsOneWidget);
    expect(find.textContaining('55%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity stays bounded on a tablet layout', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: const ActivityScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Activity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity supports right-to-left layout', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(null),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: ActivityScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Activity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PopulatedExpenses extends ExpenseListNotifier {
  @override
  Future<List<Expense>> build() async => [
    Expense(
      amount: 125,
      currency: 'INR',
      merchant: 'Filter Test',
      category: 'Others',
      date: DateTime(2026, 7, 17),
      originalSms: '',
    ),
  ];
}

class _ReviewExpenses extends ExpenseListNotifier {
  @override
  Future<List<Expense>> build() async => [
    Expense(
      id: 9001,
      amount: 499,
      currency: 'INR',
      merchant: 'Unknown',
      category: 'Others',
      date: DateTime(2026, 7, 18),
      originalSms: 'Protected source message',
      source: 'sms',
      status: 'needs_review',
      confidence: 0.55,
    ),
  ];
}
