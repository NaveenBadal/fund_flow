import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../design/flux.dart';
import '../../domain/conversation.dart';

/// What one answer was actually built from.
@immutable
class AnswerTrace {
  const AnswerTrace({required this.events, this.run});
  final List<Map<String, Object?>> events;
  final Map<String, Object?>? run;

  /// A local answer made no capability calls and had no provider run.
  bool get isLocal => events.isEmpty && run == null;
}

final answerTraceProvider = FutureProvider.family<AnswerTrace, int>((
  ref,
  messageId,
) async {
  final store = ref.read(storeProvider);
  final events = await store.toolEventsFor(messageId);
  final run = await store.agentRunFor(messageId);
  return AnswerTrace(events: events, run: run);
});

/// The line under every answer, and the working behind it.
///
/// Collapsed it states the two things that decide whether a figure can be
/// trusted: how many records it was checked against, and whether it came back
/// in the app's verified format. Expanded it lists the actual capability calls
/// the run made, read from the database rather than described — an answer that
/// claims to have checked your ledger should be able to show the queries.
class AnswerTraceRow extends ConsumerStatefulWidget {
  const AnswerTraceRow({super.key, required this.message});
  final ConversationMessage message;

  @override
  ConsumerState<AnswerTraceRow> createState() => _AnswerTraceRowState();
}

class _AnswerTraceRowState extends ConsumerState<AnswerTraceRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final message = widget.message;
    final count = message.supportingTransactionIds.length;
    final verified = message.verified;
    final id = message.id;

    final summary = verified
        ? (count == 0
              ? 'Answered from your local records'
              : 'Checked against $count '
                    '${count == 1 ? 'record' : 'records'} on this device')
        : 'Unverified — this answer did not come back in the app\'s checked '
              'format';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: id != null,
          label: id == null
              ? summary
              : '$summary. ${_open ? 'Hide' : 'Show'} the working behind this '
                    'answer',
          excludeSemantics: true,
          child: FluxPressable(
            feedback: PressFeedback.none,
            onTap: id == null ? null : () => setState(() => _open = !_open),
            child: Padding(
              // The row is one line of faint 12pt text; without padding its
              // tap target is about a third of the minimum, and it is the
              // control that opens an answer's provenance.
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    verified
                        ? Icons.verified_outlined
                        : Icons.help_outline_rounded,
                    size: 13,
                    color: verified ? palette.textFaint : palette.attention,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      summary,
                      style: FluxType.caption.copyWith(
                        color: verified ? palette.textFaint : palette.attention,
                      ),
                    ),
                  ),
                  if (id != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 14,
                      color: palette.textFaint,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: FluxMotion.duration(context, FluxMotion.normal),
          curve: FluxMotion.emphasized,
          alignment: Alignment.topCenter,
          child: !_open || id == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: FluxSpace.x3),
                  child: _TraceBody(messageId: id),
                ),
        ),
      ],
    );
  }
}

class _TraceBody extends ConsumerWidget {
  const _TraceBody({required this.messageId});
  final int messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final trace = ref.watch(answerTraceProvider(messageId));

    return FluxCard(
      raised: true,
      radius: FluxRadius.sm,
      padding: const EdgeInsets.all(FluxSpace.x4),
      child: switch (trace) {
        AsyncData(:final value) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (value.isLocal)
              Text(
                'Computed on this device from your ledger. No provider was '
                'called, which is why it came back instantly.',
                style: FluxType.caption.copyWith(
                  color: palette.textMuted,
                  height: 1.5,
                ),
              )
            else ...[
              if (value.run case final run?)
                Padding(
                  padding: const EdgeInsets.only(bottom: FluxSpace.x3),
                  child: Text(
                    [
                      '${((run['elapsedMs'] as int? ?? 0) / 1000).toStringAsFixed(1)} s',
                      '${run['turns'] ?? 0} model ${run['turns'] == 1 ? 'turn' : 'turns'}',
                      '${value.events.length} '
                          '${value.events.length == 1 ? 'capability' : 'capabilities'}',
                      if (run['model'] case final model?) '$model',
                    ].join(' · '),
                    style: FluxType.caption.copyWith(color: palette.textFaint),
                  ),
                ),
              for (final event in value.events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        event['isError'] == true
                            ? Icons.error_outline_rounded
                            : Icons.check_rounded,
                        size: 13,
                        color: event['isError'] == true
                            ? palette.danger
                            : palette.income,
                      ),
                      const SizedBox(width: FluxSpace.x2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event['tool']?.toString() ?? '',
                              style: FluxType.caption.copyWith(
                                color: palette.text,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            if (event['summary']?.toString().isNotEmpty ??
                                false)
                              Text(
                                event['summary'].toString(),
                                style: FluxType.caption.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (value.events.isEmpty)
                Text(
                  'This answer made no capability calls.',
                  style: FluxType.caption.copyWith(color: palette.textMuted),
                ),
            ],
          ],
        ),
        AsyncError() => Text(
          'The working for this answer could not be read back.',
          style: FluxType.caption.copyWith(color: palette.textMuted),
        ),
        _ => const FluxSkeleton(height: 30),
      },
    );
  }
}
