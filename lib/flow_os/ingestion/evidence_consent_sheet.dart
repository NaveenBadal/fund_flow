import 'package:flutter/material.dart';

import '../foundation/flow_color.dart';

class EvidenceConsentSheet extends StatelessWidget {
  const EvidenceConsentSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
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
            'Before messages are checked',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: FlowColor.intelligence(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Allow access to transaction messages?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Fund Flow checks recent messages for likely bank and payment activity. '
            'Only candidates are sent to your configured AI provider.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: FlowColor.quiet(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          const _Boundary(
            icon: Icons.sms_outlined,
            title: 'Read recent messages',
            detail: 'Android asks for permission before anything is read.',
          ),
          const _Boundary(
            icon: Icons.cloud_outlined,
            title: 'Understand candidates',
            detail: 'Potential transaction text goes to your configured AI.',
          ),
          const _Boundary(
            icon: Icons.phone_android_rounded,
            title: 'Keep your record local',
            detail:
                'Transactions, sources, and corrections stay on this device.',
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'You can revoke access in Android settings.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: FlowColor.quiet(context)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Boundary extends StatelessWidget {
  const _Boundary({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: FlowColor.plane(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: FlowColor.intelligence(context)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: FlowColor.quiet(context),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
