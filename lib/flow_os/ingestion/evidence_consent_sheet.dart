import 'package:flutter/material.dart';

import '../foundation/flow_color.dart';
import '../primitives/coordinate_label.dart';
import '../primitives/cut_surface.dart';
import '../primitives/loom_mark.dart';

class EvidenceConsentSheet extends StatelessWidget {
  const EvidenceConsentSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LoomMark(size: 44, state: LoomState.review),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CoordinateLabel('CONSENT / EVIDENCE CHANNEL'),
                    const SizedBox(height: 4),
                    Text(
                      'OPEN SMS TO FLOW?',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: FlowColor.content(context),
                        fontWeight: FontWeight.w900,
                        letterSpacing: .3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Flow will inspect recent messages for bank and payment signals, use your configured AI to structure candidates, then bind every accepted event to local proof.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: FlowColor.quiet(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          const _BoundaryRow(
            code: '01 / READ',
            title: 'Recent transaction candidates',
            detail: 'Android grants access only after your system approval.',
            signal: FlowColor.proof,
          ),
          const SizedBox(height: 8),
          const _BoundaryRow(
            code: '02 / SEND',
            title: 'Candidate text to configured AI',
            detail: 'Only potential bank and payment messages are extracted.',
            signal: FlowColor.amber,
          ),
          const SizedBox(height: 8),
          const _BoundaryRow(
            code: '03 / KEEP',
            title: 'Records and provenance on device',
            detail: 'Structured events, sources, and decisions remain local.',
            signal: FlowColor.mint,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ConsentAction(
                  label: 'KEEP CLOSED',
                  onTap: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _ConsentAction(
                  label: 'OPEN CHANNEL →',
                  active: true,
                  onTap: () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Center(child: CoordinateLabel('REVOCABLE IN ANDROID SETTINGS')),
        ],
      ),
    ),
  );
}

class _BoundaryRow extends StatelessWidget {
  const _BoundaryRow({
    required this.code,
    required this.title,
    required this.detail,
    required this.signal,
  });
  final String code;
  final String title;
  final String detail;
  final Color signal;

  @override
  Widget build(BuildContext context) => CutSurface(
    cut: 9,
    color: FlowColor.plane(context),
    accent: signal.withValues(alpha: .6),
    padding: const EdgeInsets.all(13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4), color: signal),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                code,
                style: TextStyle(
                  color: signal,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: FlowColor.content(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: FlowColor.quiet(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ConsentAction extends StatelessWidget {
  const _ConsentAction({
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CutSurface(
        cut: 8,
        color: active ? FlowColor.loom : FlowColor.plane(context),
        accent: active ? FlowColor.proof : FlowColor.rule(context),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 15),
        child: Center(
          child: Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : FlowColor.quiet(context),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
            ),
          ),
        ),
      ),
    ),
  );
}
