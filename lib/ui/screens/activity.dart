import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/transaction.dart';
import '../ff_format.dart';
import '../theme/ff_theme.dart';
import '../widgets/ff_controls.dart';
import '../widgets/ff_group.dart';
import '../widgets/ff_notice.dart';
import '../widgets/ff_screen.dart';
import '../widgets/ff_transaction_row.dart';
import 'transaction_detail.dart';
import 'transaction_editor.dart';

enum _Lens { all, spending, income, review }

/// The ledger.
///
/// Grouped by day and nothing else. Filters exist, but they sit above the list
/// where they can be seen rather than behind an icon that hides what state the
/// list is in.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _search = TextEditingController();
  _Lens _lens = _Lens.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final hidden = app.preferences.hideAmounts;
    final query = _search.text.trim().toLowerCase();

    final matching =
        app.transactions.where((t) {
            switch (_lens) {
              case _Lens.spending:
                if (t.direction != TransactionDirection.outgoing) return false;
              case _Lens.income:
                if (t.direction != TransactionDirection.incoming) return false;
              case _Lens.review:
                if (t.reviewState != ReviewState.needsReview) return false;
              case _Lens.all:
                break;
            }
            if (query.isEmpty) return true;
            return '${t.merchant} ${t.category} ${t.note ?? ''}'
                .toLowerCase()
                .contains(query);
          }).toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    final groups = byDay(matching);
    final total = matching.length;

    return FFScreen(
      title: 'Activity',
      trailing: [
        FFBarButton(
          icon: Icons.add_rounded,
          tooltip: 'Add a transaction',
          onTap: () => showTransactionEditor(context),
        ),
      ],
      belowTitle: Column(
        children: [
          FFSearchField(
            controller: _search,
            placeholder: 'Merchant, category or note',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: FFSpace.md),
          FFSegmented<_Lens>(
            value: _lens,
            segments: const [
              (_Lens.all, 'All'),
              (_Lens.spending, 'Spending'),
              (_Lens.income, 'Income'),
              (_Lens.review, 'To review'),
            ],
            onChanged: (value) => setState(() => _lens = value),
          ),
        ],
      ),
      slivers: [
        if (groups.isEmpty)
          SliverToBoxAdapter(
            child: app.transactions.isEmpty
                ? FFEmpty(
                    icon: Icons.receipt_long_rounded,
                    title: 'Nothing recorded yet',
                    message:
                        'Payment messages become transactions here once you '
                        'run a check.',
                    action: 'Check my messages',
                    onAction: ref
                        .read(appControllerProvider.notifier)
                        .importMessages,
                    secondaryAction: 'Add one manually',
                    onSecondaryAction: () => showTransactionEditor(context),
                  )
                : FFEmpty(
                    icon: Icons.search_off_rounded,
                    title: 'No matches',
                    message: query.isEmpty
                        ? 'Nothing in this view yet.'
                        : 'Nothing matches “${_search.text.trim()}”.',
                    action: query.isEmpty ? null : 'Clear search',
                    onAction: () {
                      _search.clear();
                      setState(() {});
                    },
                  ),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                FFSpace.lg + FFSpace.gutter,
                0,
                FFSpace.gutter,
                FFSpace.md,
              ),
              child: Text(
                '$total ${total == 1 ? 'transaction' : 'transactions'}',
                style: FFText.footnote.copyWith(
                  color: context.ff.secondaryLabel,
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final (day, items) = groups[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FFSpace.lg + FFSpace.gutter,
                      0,
                      FFSpace.gutter,
                      FFSpace.sm,
                    ),
                    child: Text(
                      dayLabel(day),
                      style: FFText.footnote.copyWith(
                        color: context.ff.secondaryLabel,
                      ),
                    ),
                  ),
                  FFGroup(
                    separatorIndent: 64,
                    children: [
                      for (final item in items)
                        FFTransactionRow(
                          item: item,
                          hidden: hidden,
                          onTap: () => openTransaction(context, item),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
