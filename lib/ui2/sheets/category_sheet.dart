import 'package:flutter/material.dart';

import '../flow_categories.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';

/// Offers the shared category vocabulary and returns the choice, or null if
/// the sheet is dismissed. [current] highlights the category already set.
Future<String?> pickCategory(
  BuildContext context, {
  required String title,
  String? current,
}) => showModalBottomSheet<String>(
  context: context,
  builder: (sheet) => _CategorySheet(title: title, current: current),
);

class _CategorySheet extends StatelessWidget {
  const _CategorySheet({required this.title, this.current});
  final String title;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FlowSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: FlowSpace.lg),
            Wrap(
              spacing: FlowSpace.sm,
              runSpacing: FlowSpace.sm,
              children: [
                for (final category in kFlowCategories)
                  Builder(
                    builder: (context) {
                      final selected =
                          category.toLowerCase() == current?.toLowerCase();
                      return InkWell(
                        onTap: () => Navigator.pop(context, category),
                        borderRadius: FlowRadius.pill,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FlowSpace.md,
                            vertical: FlowSpace.sm,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? flow.accent : flow.raised,
                            borderRadius: FlowRadius.pill,
                            border: Border.all(
                              color: selected ? flow.accent : flow.line,
                            ),
                          ),
                          child: Text(
                            category,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: selected ? flow.onAccent : flow.ink,
                                ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
