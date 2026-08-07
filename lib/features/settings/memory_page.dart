import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../design/flux.dart';

/// Durable facts the agent has been told to remember.
///
/// Every entry got here because someone explicitly asked for it and approved a
/// card — the agent is forbidden from inferring memory from conversation, from
/// transactions or from message text. This page is where that promise becomes
/// checkable: if something is here that you did not agree to, it is a bug, and
/// you can delete it.
final financialMemoryProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) {
  // Watched so approving or deleting a memory refreshes this list rather
  // than leaving a stale one behind.
  ref.watch(appControllerProvider);
  return ref.read(storeProvider).financialMemory();
});

class MemoryPage extends ConsumerWidget {
  const MemoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final memories = ref.watch(financialMemoryProvider);

    return FluxDetailPage(
      title: 'Memory',
      slivers: [
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: Text(
            'Facts you asked the agent to keep — your salary date, an account '
            'nickname, a rule of thumb. It never adds anything here on its own, '
            'and it reads this list instead of guessing about you.',
            style: FluxType.body.copyWith(color: palette.textMuted),
          ),
        ),
        ...switch (memories) {
          AsyncData(:final value) when value.isEmpty => [
            const SliverToBoxAdapter(
              child: FluxEmpty(
                icon: Icons.psychology_outlined,
                title: 'Nothing remembered',
                message:
                    'Ask the agent to remember something and it will offer you '
                    'a card to approve.',
                compact: true,
              ),
            ),
          ],
          AsyncData(:final value) => [
            SliverToBoxAdapter(
              child: FluxGroup(
                header:
                    '${value.length} '
                    '${value.length == 1 ? 'fact' : 'facts'}',
                children: [
                  for (final memory in value)
                    FluxRow(
                      title: memory['key']?.toString() ?? '',
                      subtitle: memory['value']?.toString(),
                      icon: Icons.push_pin_outlined,
                      trailing: FluxIconButton(
                        icon: Icons.delete_outline_rounded,
                        size: 17,
                        color: palette.textFaint,
                        tooltip: 'Forget',
                        onPressed: () async {
                          final key = memory['key']?.toString();
                          if (key == null) return;
                          final confirmed = await fluxConfirm(
                            context: context,
                            title: 'Forget this?',
                            message:
                                'The agent stops knowing "$key". Your '
                                'transactions are not affected.',
                            confirmLabel: 'Forget',
                          );
                          if (!confirmed) return;
                          await ref
                              .read(storeProvider)
                              .deleteFinancialMemory(key);
                          ref.invalidate(financialMemoryProvider);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
          AsyncError() => [
            const SliverToBoxAdapter(
              child: FluxEmpty(
                icon: Icons.error_outline_rounded,
                title: 'Could not read memory',
                compact: true,
              ),
            ),
          ],
          _ => [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(FluxSpace.page),
                child: FluxSkeleton(height: 56, radius: FluxRadius.md),
              ),
            ),
          ],
        },
      ],
    );
  }
}
