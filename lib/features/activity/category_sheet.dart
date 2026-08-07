import 'package:flutter/widgets.dart';

import '../../design/flux.dart';
import '../../domain/category_catalog.dart';
import '../../domain/transaction.dart';

/// Picks a category from the catalog for [direction].
///
/// A grid of chips rather than a list: there are ten of them, they are short,
/// and each carries its own colour — which is the fastest way to pick the one
/// you mean and also teaches which colour means what in the charts.
Future<String?> showCategorySheet({
  required BuildContext context,
  required TransactionDirection direction,
  required String? selected,
}) => showFluxSheet<String>(
  context: context,
  builder: (context) {
    final palette = context.flux;
    return FluxSheetBody(
      title: 'Category',
      subtitle: direction == TransactionDirection.incoming
          ? 'What kind of money came in'
          : 'What the money went on',
      child: Wrap(
        spacing: FluxSpace.x2,
        runSpacing: FluxSpace.x2,
        children: [
          for (final category in categoriesFor(direction))
            FluxChip(
              label: category,
              selected: category == selected,
              tint: palette.forCategory(category),
              onTap: () => Navigator.of(context).pop(category),
            ),
        ],
      ),
    );
  },
);
