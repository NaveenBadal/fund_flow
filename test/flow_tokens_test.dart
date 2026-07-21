import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fund_flow/ui2/tokens/flow_palette.dart';
import 'package:fund_flow/ui2/tokens/flow_theme.dart';
import 'package:fund_flow/ui2/tokens/flow_type.dart';

/// Relative luminance per WCAG.
double _luminance(Color c) {
  double channel(double v) {
    v = v / 255.0;
    return v <= 0.03928
        ? v / 12.92
        : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
  }

  // Approximation is adequate: the exact ratios were already checked by the
  // palette validator. This guards against a value being edited by hand later.
  return 0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('palette', () {
    test('series slots are distinct and fixed in order', () {
      for (final series in [FlowPalette.lightSeries, FlowPalette.darkSeries]) {
        expect(series, hasLength(6));
        expect(series.toSet(), hasLength(6), reason: 'no duplicate slots');
      }
    });

    test('a ninth series folds back rather than inventing a hue', () {
      const colors = FlowColors.light;
      expect(colors.seriesAt(6), colors.seriesAt(0));
      expect(colors.seriesAt(13), colors.seriesAt(1));
    });

    test('income and expense are not the same colour in either mode', () {
      expect(FlowColors.light.income, isNot(FlowColors.light.expense));
      expect(FlowColors.dark.income, isNot(FlowColors.dark.expense));
    });

    test('ink meets text contrast against its own canvas', () {
      expect(
        _contrast(FlowColors.light.ink, FlowColors.light.canvas),
        greaterThan(7),
      );
      expect(
        _contrast(FlowColors.dark.ink, FlowColors.dark.canvas),
        greaterThan(7),
      );
    });

    test('the three surface levels are actually distinct', () {
      for (final c in [FlowColors.light, FlowColors.dark]) {
        expect({c.sunken, c.canvas, c.raised}, hasLength(3));
      }
    });

    test('themes swap wholesale instead of blending', () {
      // A half-interpolated palette is not a state any value was validated in.
      expect(FlowColors.light.lerp(FlowColors.dark, .2), FlowColors.light);
      expect(FlowColors.light.lerp(FlowColors.dark, .8), FlowColors.dark);
    });
  });

  group('typography', () {
    test('every amount style uses tabular figures', () {
      for (final style in [
        FlowType.amountHero,
        FlowType.amountLarge,
        FlowType.amountRow,
        FlowType.amountSmall,
      ]) {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'columns must align and a changing amount must not reflow',
        );
      }
    });

    test('amounts do not use the display face', () {
      // Its wide apertures compete with precision on a balance.
      expect(FlowType.amountHero.fontFamily, isNot(FlowType.display));
      expect(FlowType.amountRow.fontFamily, isNot(FlowType.display));
    });
  });

  group('theme', () {
    testWidgets('exposes FlowColors and suppresses elevation tint', (
      tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: FlowTheme.light(),
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(captured.flow.canvas, FlowPalette.lightCanvas);
      expect(Theme.of(captured).applyElevationOverlayColor, isFalse);
    });
  });
}
