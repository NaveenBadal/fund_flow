import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fund_flow/domain/category_catalog.dart';
import 'package:fund_flow/domain/transaction.dart';
import 'package:fund_flow/zero/zero_theme.dart';

void main() {
  group('Zero design system', () {
    test('light and dark expose complete semantic palettes', () {
      for (final theme in [ZeroTheme.light(), ZeroTheme.dark()]) {
        final colors = theme.extension<ZeroColors>();
        expect(colors, isNotNull);
        expect(
          colors!.text.computeLuminance(),
          isNot(colors.bg.computeLuminance()),
        );
        expect(theme.splashFactory, NoSplash.splashFactory);
        expect(theme.bottomSheetTheme.showDragHandle, isFalse);
        expect(theme.progressIndicatorTheme.color, colors.accent);
      }
    });

    test('themes preserve meaningful contrast and distinct states', () {
      for (final colors in [ZeroColors.light, ZeroColors.dark]) {
        expect(_contrast(colors.text, colors.bg), greaterThan(7));
        expect(_contrast(colors.muted, colors.bg), greaterThan(3));
        expect(colors.positive, isNot(colors.negative));
        expect(colors.warning, isNot(colors.negative));
        expect(colors.surface, isNot(colors.bg));
      }
    });

    testWidgets('money-sized text does not inherit platform defaults', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ZeroTheme.light(),
          home: Builder(
            builder: (context) {
              final style = Theme.of(context).textTheme.displayLarge!;
              return Text(
                '₹44,146.93',
                style: style,
                textDirection: TextDirection.ltr,
              );
            },
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('₹44,146.93'));
      expect(text.style!.fontFamily, 'Inter');
      expect(text.style!.fontWeight, FontWeight.w600);
    });
  });

  group('Zero transaction vocabulary', () {
    test('income and expense vocabularies do not leak into one another', () {
      expect(
        categoriesFor(TransactionDirection.incoming),
        containsAll(['Income', 'Salary', 'Refund']),
      );
      expect(
        categoriesFor(TransactionDirection.outgoing),
        containsAll(['Food', 'Bills', 'Shopping']),
      );
      expect(
        categoriesFor(TransactionDirection.incoming),
        isNot(contains('Food')),
      );
      expect(
        categoriesFor(TransactionDirection.outgoing),
        isNot(contains('Salary')),
      );
    });

    test('direction defaults are safe', () {
      expect(defaultCategoryFor(TransactionDirection.incoming), 'Income');
      expect(defaultCategoryFor(TransactionDirection.outgoing), 'Other');
    });
  });
}

double _contrast(Color a, Color b) {
  final high = a.computeLuminance() > b.computeLuminance() ? a : b;
  final low = high == a ? b : a;
  return (high.computeLuminance() + .05) / (low.computeLuminance() + .05);
}
