import 'package:flutter/material.dart';

import '../foundation/flow_color.dart';

class AgentDecisionSheet extends StatelessWidget {
  const AgentDecisionSheet({
    super.key,
    required this.title,
    required this.description,
    required this.confirmLabel,
    this.notice,
    this.destructive = false,
  });
  final String title;
  final String description;
  final String confirmLabel;
  final String? notice;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final signal = destructive
        ? FlowColor.expense(context)
        : FlowColor.intelligence(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: FlowColor.rule(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              destructive
                  ? 'Please review this change'
                  : 'Your approval is needed',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: signal),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
            if (notice != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: FlowColor.plane(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 19,
                      color: FlowColor.quiet(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        notice!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: FlowColor.quiet(context),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: signal),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
