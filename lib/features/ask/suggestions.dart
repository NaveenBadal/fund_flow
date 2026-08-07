import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_snapshot.dart';
import '../../design/flux.dart';
import '../common/formatting.dart';

/// The empty state, with suggestions drawn from this person's own data.
///
/// Static example questions are a tour of the feature list. These name the
/// person's actual largest category, their actual review backlog, their actual
/// repeat charges — so the first tap returns something true about them, which is
/// the only demonstration that matters.
class AskEmptyState extends ConsumerWidget {
  const AskEmptyState({super.key, required this.snapshot, required this.onAsk});

  final HomeSnapshot snapshot;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final money = ref.watch(moneyProvider);
    final now = DateTime.now();

    final suggestions = <String>[
      if (snapshot.categories.isNotEmpty)
        'How much am I spending on ${snapshot.categories.first.category}?',
      if (snapshot.spendChange != null)
        'Why is ${monthLabel(now)} different from last month?',
      if (snapshot.reviewCount > 0) 'What is waiting for me to review?',
      if (snapshot.upcoming.isNotEmpty) 'What repeat charges are coming up?',
      if (snapshot.duplicateCount > 0)
        'Have I been charged twice for anything?',
      if (snapshot.budgets.isEmpty && snapshot.categories.isNotEmpty)
        'Set a monthly limit on ${snapshot.categories.first.category}',
      'How am I doing this month?',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FluxSpace.page,
        FluxSpace.x10,
        FluxSpace.page,
        FluxSpace.x6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => FluxPalette.ai.createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 30,
              color: Color(0xFFFFFFFF),
            ),
          ),
          const SizedBox(height: FluxSpace.x4),
          Text(
            'Ask about your money',
            style: FluxType.display.copyWith(color: palette.text, fontSize: 28),
          ),
          const SizedBox(height: FluxSpace.x2),
          Text(
            snapshot.empty
                ? 'Once your messages are imported, everything here becomes '
                      'answerable.'
                : 'Answers are calculated from the '
                      '${snapshot.month.transactionCount} records on this '
                      'device this month, never estimated. This agent only '
                      'works on your money.',
            style: FluxType.body.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: FluxSpace.x6),
          for (final suggestion in suggestions.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: FluxSpace.x2),
              child: FluxCard(
                onTap: () => onAsk(suggestion),
                radius: FluxRadius.sm,
                padding: const EdgeInsets.symmetric(
                  horizontal: FluxSpace.x4,
                  vertical: FluxSpace.x3 + 2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        suggestion,
                        style: FluxType.body.copyWith(color: palette.text),
                      ),
                    ),
                    Icon(
                      Icons.north_east_rounded,
                      size: 15,
                      color: palette.textFaint,
                    ),
                  ],
                ),
              ),
            ),
          if (!snapshot.empty) ...[
            const SizedBox(height: FluxSpace.x4),
            Text(
              'This month: ${money(snapshot.month.outgoingMinor, snapshot.currency)} '
              'out, ${money(snapshot.month.incomingMinor, snapshot.currency)} in.',
              style: FluxType.caption.copyWith(color: palette.textFaint),
            ),
          ],
        ],
      ),
    );
  }
}
