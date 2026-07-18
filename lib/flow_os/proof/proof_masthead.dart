import 'package:flutter/material.dart';

import '../foundation/flow_color.dart';
import '../primitives/coordinate_label.dart';

class ProofMasthead extends StatelessWidget {
  const ProofMasthead({
    super.key,
    required this.hidden,
    required this.onPrivacy,
    required this.onManualEntry,
  });

  final bool hidden;
  final VoidCallback onPrivacy;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CoordinateLabel('PROOF / LOCAL LEDGER'),
                    SizedBox(height: 3),
                    Text(
                      'EVIDENCE',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .7,
                      ),
                    ),
                  ],
                ),
              ),
              _ProofAction(
                semantics: hidden ? 'Show amounts' : 'Hide amounts',
                label: hidden ? 'REVEAL' : 'VEIL',
                glyph: hidden ? '◇' : '◆',
                onTap: onPrivacy,
              ),
              const SizedBox(width: 7),
              _ProofAction(
                semantics: 'Add cash transaction manually',
                label: 'MANUAL',
                glyph: '+',
                quiet: true,
                onTap: onManualEntry,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(width: 38, height: 2, color: FlowColor.proof),
              Expanded(
                child: SizedBox(
                  height: 1,
                  child: ColoredBox(color: FlowColor.rule(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ProofAction extends StatelessWidget {
  const _ProofAction({
    required this.semantics,
    required this.label,
    required this.glyph,
    required this.onTap,
    this.quiet = false,
  });

  final String semantics;
  final String label;
  final String glyph;
  final VoidCallback onTap;
  final bool quiet;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semantics,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 54),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: quiet ? Colors.transparent : FlowColor.plane(context),
          border: Border.all(color: FlowColor.rule(context)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              glyph,
              style: TextStyle(
                color: quiet ? FlowColor.quiet(context) : FlowColor.proof,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: FlowColor.quiet(context),
                fontSize: 7,
                fontWeight: FontWeight.w900,
                letterSpacing: .7,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
