import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ai_log.dart';
import '../providers/expense_provider.dart';
import '../flow_os/foundation/flow_color.dart';
import '../flow_os/primitives/coordinate_label.dart';
import '../flow_os/primitives/cut_surface.dart';
import '../theme/app_tokens.dart';
import '../widgets/ui/flow_ui.dart';

class LogsScreen extends ConsumerWidget {
  const LogsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(aiLogProvider);
    final width = MediaQuery.sizeOf(context).width;
    final inset = width > AppBreakpoint.contentMax + 40
        ? (width - AppBreakpoint.contentMax) / 2
        : AppSpacing.page;
    return FlowScaffold(
      eyebrow: 'Requests, results and errors',
      title: 'AI activity',
      actions: [
        if (logs.value?.isNotEmpty ?? false)
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
            padding: EdgeInsets.fromLTRB(inset, 0, inset, 12),
            child: Text(
              'A technical history of AI extraction. Clearing it does not remove any transactions.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ),
        logs.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: Icon(Icons.hourglass_top_rounded, size: 32)),
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
                  padding: EdgeInsets.fromLTRB(inset, 8, inset, 40),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _LogEvent(items[index], index),
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
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: CutSurface(
              accent: FlowColor.coral,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CoordinateLabel(
                    'Clear technical history',
                    color: FlowColor.coral,
                    line: true,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Clear AI trace?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Transactions remain intact. Only technical request history is removed.',
                    style: TextStyle(color: FlowColor.quiet(context)),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _DecisionPort(
                          label: 'Cancel',
                          color: FlowColor.proof,
                          onTap: () => Navigator.pop(context, false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DecisionPort(
                          label: 'Clear history',
                          color: FlowColor.coral,
                          onTap: () => Navigator.pop(context, true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
    if (yes) await ref.read(aiLogProvider.notifier).clearLogs();
  }
}

class _LogEvent extends StatelessWidget {
  const _LogEvent(this.log, this.index);
  final AiLog log;
  final int index;
  @override
  Widget build(BuildContext context) {
    final failed = log.status.startsWith('Error');
    final color = failed ? FlowColor.coral : FlowColor.mint;
    return CutSurface(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoordinateLabel(
            failed ? 'AI request failed' : 'AI request completed',
            color: color,
            line: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  failed ? 'Extraction failed' : 'Extraction complete',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '#${(index + 1).toString().padLeft(3, '0')}',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('d MMM · HH:mm:ss').format(log.timestamp),
            style: TextStyle(color: FlowColor.quiet(context)),
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              _CodeBlock(label: 'REQUEST', value: log.requestPrompt),
              const SizedBox(height: 10),
              _CodeBlock(label: 'RESPONSE', value: log.responseBody),
              const SizedBox(height: 10),
              _CodeBlock(label: 'STATUS', value: log.status),
            ],
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
  Widget build(BuildContext context) => CutSurface(
    color: FlowColor.canvas(context),
    border: false,
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: FlowColor.proof,
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

class _DecisionPort extends StatelessWidget {
  const _DecisionPort({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: CutSurface(
      accent: color,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: .6,
          ),
        ),
      ),
    ),
  );
}
