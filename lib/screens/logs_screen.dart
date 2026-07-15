import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ai_log.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/ui/command_ui.dart';

class LogsScreen extends ConsumerWidget {
  const LogsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(aiLogProvider);
    return CommandScaffold(
      eyebrow: 'How the machine reached its conclusions',
      title: 'Reasoning trace',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
            tooltip: 'Clear history',
            onPressed: () => _clear(context, ref),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'A technical timeline of cloud extraction. Your financial dashboard does not depend on keeping this history.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ),
        logs.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            child: StatePanel(
              icon: Icons.error_outline_rounded,
              title: 'Diagnostics unavailable',
              message: '$error',
            ),
          ),
          data: (items) => items.isEmpty
              ? const SliverFillRemaining(
                  hasScrollBody: false,
                  child: StatePanel(
                    icon: Icons.terminal_rounded,
                    title: 'No diagnostic events',
                    message: 'Cloud parsing events will appear here.',
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _LogEvent(items[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear diagnostics?'),
            content: const Text('This only removes technical request history.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (yes) await ref.read(aiLogProvider.notifier).clearLogs();
  }
}

class _LogEvent extends StatelessWidget {
  const _LogEvent(this.log);
  final AiLog log;
  @override
  Widget build(BuildContext context) {
    final failed = log.status.startsWith('Error');
    final color = failed
        ? Theme.of(context).colorScheme.error
        : context.finance.income;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: AppRadius.all(12),
          ),
          child: Icon(
            failed ? Icons.close_rounded : Icons.check_rounded,
            color: color,
            size: 19,
          ),
        ),
        title: Text(
          failed ? 'Extraction failed' : 'Extraction complete',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(DateFormat('d MMM · HH:mm:ss').format(log.timestamp)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                _CodeBlock(label: 'REQUEST', value: log.requestPrompt),
                const SizedBox(height: 10),
                _CodeBlock(label: 'RESPONSE', value: log.responseBody),
                const SizedBox(height: 10),
                _CodeBlock(label: 'STATUS', value: log.status),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
      borderRadius: AppRadius.all(AppRadius.sm),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        SelectableText(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.4),
        ),
      ],
    ),
  );
}
