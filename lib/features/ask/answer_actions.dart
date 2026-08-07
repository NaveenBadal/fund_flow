import 'package:flutter/material.dart' show Icons, ScaffoldMessenger, SnackBar;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../agent/agent_presentation.dart';
import '../../design/flux.dart';
import '../../domain/conversation.dart';
import '../../domain/money_format.dart';
import '../common/formatting.dart';

/// An answer as text someone can paste somewhere else.
///
/// Not [ConversationMessage.providerContent], which exists for replaying
/// figures back to a model and writes money in minor units — pasting
/// "Food 355798 INR" to an accountant is worse than pasting nothing. Every
/// amount here goes through the same formatter the screen used, so what lands
/// in the clipboard is what was read on screen, masking included.
String answerAsText(ConversationMessage message, MoneyFormatter money) {
  String amount(Object? minor, Object? currency) {
    final code = currency?.toString();
    if (minor is! num || !isPlausibleCurrency(code)) return '';
    return money(minor.round(), code!);
  }

  String row(Object? item) {
    if (item is! Map) return '';
    final label = (item['label'] ?? item['title'] ?? '').toString().trim();
    final value =
        amount(item['amountMinor'], item['currency']).ifEmpty ??
        item['value']?.toString().trim() ??
        '';
    if (label.isEmpty) return value;
    return value.isEmpty ? label : '$label: $value';
  }

  List<Object?> list(AgentPart part, String key) {
    final value = part.data[key];
    return value is List ? value : const [];
  }

  final blocks = <String>[];
  for (final part in message.parts) {
    final text = part.data['text']?.toString().trim();
    switch (part.kind) {
      case AgentPartKind.conclusion:
      case AgentPartKind.redirect:
      case AgentPartKind.narrative:
      case AgentPartKind.insight:
      case AgentPartKind.sourceNote:
        if (text != null && text.isNotEmpty) blocks.add(text);
      case AgentPartKind.warning:
        if (text != null && text.isNotEmpty) blocks.add('Note: $text');
      case AgentPartKind.metricRow:
        final metrics = [
          for (final item in [
            ...list(part, 'metrics'),
            ...list(part, 'values'),
          ])
            row(item),
        ].where((line) => line.isNotEmpty);
        if (metrics.isNotEmpty) blocks.add(metrics.join('\n'));
      case AgentPartKind.comparison:
        final title = part.data['title']?.toString().trim();
        final current = amount(
          part.data['currentMinor'],
          part.data['currency'],
        );
        final previous = amount(
          part.data['previousMinor'],
          part.data['currency'],
        );
        final lines = <String>[
          if (title != null && title.isNotEmpty) title,
          if (current.isNotEmpty)
            '${part.data['currentLabel'] ?? 'This period'}: $current',
          if (previous.isNotEmpty)
            '${part.data['previousLabel'] ?? 'Before'}: $previous',
          if (part.data['detail'] != null) part.data['detail'].toString(),
        ];
        if (lines.isNotEmpty) blocks.add(lines.join('\n'));
      case AgentPartKind.breakdown:
        final title = part.data['title']?.toString().trim();
        final rows = [
          for (final item in list(part, 'rows')) row(item),
        ].where((line) => line.isNotEmpty);
        if (rows.isNotEmpty) {
          blocks.add(
            [
              if (title != null && title.isNotEmpty) title,
              ...rows.map((line) => '  $line'),
            ].join('\n'),
          );
        }
      // Neither carries text worth pasting: a list of database row IDs means
      // nothing outside this device, and suggested questions were never part
      // of the answer.
      case AgentPartKind.transactionList:
      case AgentPartKind.followUps:
      case AgentPartKind.proposal:
        break;
    }
  }
  if (blocks.isEmpty) return message.text.trim();
  return blocks.join('\n\n');
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}

/// Copy, share and ask-again, under every answer.
///
/// Deliberately quiet — faint, iconographic, no fill — because they sit under
/// every single answer and a row of buttons competing with the figures above
/// them would make the thread feel like a toolbar with text in it.
class AnswerActions extends ConsumerWidget {
  const AnswerActions({
    super.key,
    required this.message,
    required this.question,
    required this.onAskAgain,
  });

  final ConversationMessage message;

  /// The question that produced this answer, if it is still in the thread.
  final String? question;
  final ValueChanged<String> onAskAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyProvider);
    String text() => answerAsText(message, money);

    return Row(
      children: [
        _Action(
          icon: Icons.copy_rounded,
          label: 'Copy',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: text()));
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(const SnackBar(content: Text('Answer copied')));
          },
        ),
        const SizedBox(width: FluxSpace.x2),
        _Action(
          icon: Icons.ios_share_rounded,
          label: 'Share',
          onTap: () => SharePlus.instance.share(ShareParams(text: text())),
        ),
        if (question != null) ...[
          const SizedBox(width: FluxSpace.x2),
          _Action(
            icon: Icons.refresh_rounded,
            label: 'Ask again',
            onTap: () => onAskAgain(question!),
          ),
        ],
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Semantics(
      button: true,
      label: label,
      child: FluxPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FluxRadius.sm),
        child: Padding(
          // Padded to the minimum tap height rather than sized to the icon:
          // these are small marks, and a small mark with a small target is a
          // control that only works for people who aim well.
          padding: const EdgeInsets.symmetric(
            horizontal: FluxSpace.x2,
            vertical: FluxSpace.x2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: palette.textFaint),
              const SizedBox(width: 5),
              Text(
                label,
                style: FluxType.caption.copyWith(color: palette.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
