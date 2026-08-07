import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_snapshot.dart';
import '../../design/flux.dart';
import '../activity/merchant_page.dart';
import '../common/formatting.dart';
import '../shell/shell.dart';

/// Repeat charges that look like subscriptions.
///
/// Presented as candidates throughout, and the page says so in as many words.
/// A monthly rent transfer, a gym membership and a genuine subscription are
/// indistinguishable from the ledger alone, and telling someone they are paying
/// for something they are not is worse than saying nothing.
class SubscriptionsPage extends ConsumerWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final charges = ref.watch(recurringProvider);
    final money = ref.watch(moneyProvider);
    final now = DateTime.now();

    if (charges.isEmpty) {
      return const FluxDetailPage(
        title: 'Repeat charges',
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: FluxEmpty(
              icon: Icons.autorenew_rounded,
              title: 'Nothing repeating yet',
              message:
                  'This needs three charges at one merchant, similar in size '
                  'and about a month apart, before it will call anything a '
                  'pattern.',
            ),
          ),
        ],
      );
    }

    // One monthly figure per currency. Charges in different currencies are
    // listed together but never summed into one number.
    final monthlyByCurrency = <String, int>{};
    for (final charge in charges) {
      monthlyByCurrency[charge.currency] =
          (monthlyByCurrency[charge.currency] ?? 0) + charge.typicalMinor;
    }

    return FluxDetailPage(
      title: 'Repeat charges',
      slivers: [
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: FluxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ABOUT EVERY MONTH',
                  style: FluxType.overline.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: FluxSpace.x2),
                for (final entry in monthlyByCurrency.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: MoneyText(
                      money(entry.value, entry.key),
                      style: FluxType.moneyLarge,
                    ),
                  ),
                const SizedBox(height: FluxSpace.x2),
                Text(
                  'Across ${charges.length} '
                  '${charges.length == 1 ? 'merchant' : 'merchants'} that charge '
                  'you on a cycle.',
                  style: FluxType.caption.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: FluxSectionHeader(title: 'Candidates')),
        SliverToBoxAdapter(
          child: FluxGroup(
            footer:
                'Worked out on this device from repeat charges — not confirmed '
                'with the merchant, and never cancelled for you.',
            children: [
              for (final charge in charges)
                FluxRow(
                  title: charge.merchant,
                  subtitle:
                      '${money(charge.typicalMinor, charge.currency)} · '
                      '${charge.occurrences} charges · next '
                      '${relativeDays(charge.daysUntilNext(now))}',
                  icon: Icons.autorenew_rounded,
                  iconColor: palette.forCategory(charge.category),
                  chevron: true,
                  onTap: () => fluxPush(
                    context,
                    (context) => MerchantPage(merchant: charge.merchant),
                  ),
                ),
            ],
          ),
        ),
        FluxSliverPadding(
          top: FluxSpace.x6,
          child: FluxChip(
            label: 'Ask which of these to cancel',
            icon: Icons.auto_awesome_rounded,
            onTap: () => openAsk(
              context,
              ref,
              seed:
                  'Which of my repeat charges am I paying the most for, and '
                  'which look least used?',
            ),
          ),
        ),
      ],
    );
  }
}
