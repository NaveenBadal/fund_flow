import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../design/flux.dart';

/// Every Flux component, on one screen, with no app data behind it.
///
/// This exists to be screenshotted. Verifying the design system through the real
/// app means a component is only ever seen in the one state the current ledger
/// happens to produce; here every state is on screen at once, in both themes and
/// at both text scales, which is how the last redesign's problems would have been
/// caught before they shipped.
///
/// Reachable in debug builds from Settings > About by long-pressing the version.
class DesignGallery extends StatefulWidget {
  const DesignGallery({super.key});

  @override
  State<DesignGallery> createState() => _DesignGalleryState();
}

class _DesignGalleryState extends State<DesignGallery> {
  bool _toggle = true;
  int _segment = 0;
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;

    return FluxDetailPage(
      title: 'Flux gallery',
      slivers: [
        _section('Type'),
        FluxSliverPadding(
          child: FluxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₹1,84,320',
                  style: FluxType.moneyHero.copyWith(color: palette.text),
                ),
                Text(
                  '₹42,190',
                  style: FluxType.moneyLarge.copyWith(color: palette.text),
                ),
                Text(
                  '₹1,299',
                  style: FluxType.moneyRow.copyWith(color: palette.text),
                ),
                const SizedBox(height: FluxSpace.x3),
                Text(
                  'Display 34',
                  style: FluxType.display.copyWith(color: palette.text),
                ),
                Text(
                  'Title 22',
                  style: FluxType.title.copyWith(color: palette.text),
                ),
                Text(
                  'Subtitle 17',
                  style: FluxType.subtitle.copyWith(color: palette.text),
                ),
                Text(
                  'Body large 17',
                  style: FluxType.bodyLarge.copyWith(color: palette.text),
                ),
                Text(
                  'Body 15',
                  style: FluxType.body.copyWith(color: palette.text),
                ),
                Text(
                  'Label 13',
                  style: FluxType.label.copyWith(color: palette.text),
                ),
                Text(
                  'Caption 12',
                  style: FluxType.caption.copyWith(color: palette.textMuted),
                ),
                Text(
                  'OVERLINE 11',
                  style: FluxType.overline.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
        ),

        _section('Colour roles'),
        FluxSliverPadding(
          child: Wrap(
            spacing: FluxSpace.x2,
            runSpacing: FluxSpace.x2,
            children: [
              for (final entry in <(String, Color)>[
                ('background', palette.background),
                ('surface', palette.surface),
                ('raised', palette.surfaceRaised),
                ('highest', palette.surfaceHighest),
                ('iris', palette.iris),
                ('income', palette.income),
                ('attention', palette.attention),
                ('danger', palette.danger),
                ('outflow', palette.outflow),
              ])
                _Swatch(label: entry.$1, color: entry.$2),
            ],
          ),
        ),

        _section('Categorical (validated)'),
        FluxSliverPadding(
          child: Wrap(
            spacing: FluxSpace.x2,
            runSpacing: FluxSpace.x2,
            children: [
              for (var slot = 0; slot < palette.categorical.length; slot++)
                _Swatch(label: '${slot + 1}', color: palette.categorical[slot]),
              _Swatch(label: 'other', color: palette.neutralCategory),
            ],
          ),
        ),

        _section('Buttons'),
        FluxSliverPadding(
          child: Column(
            children: [
              const FluxButton(label: 'Primary', onPressed: _noop),
              const SizedBox(height: FluxSpace.x2),
              const FluxButton(
                label: 'Secondary',
                kind: FluxButtonKind.secondary,
                icon: Icons.sell_outlined,
                onPressed: _noop,
              ),
              const SizedBox(height: FluxSpace.x2),
              const FluxButton(
                label: 'Ghost',
                kind: FluxButtonKind.ghost,
                onPressed: _noop,
              ),
              const SizedBox(height: FluxSpace.x2),
              const FluxButton(
                label: 'Danger',
                kind: FluxButtonKind.danger,
                onPressed: _noop,
              ),
              const SizedBox(height: FluxSpace.x2),
              const FluxButton(label: 'Busy', busy: true, onPressed: _noop),
              const SizedBox(height: FluxSpace.x2),
              const FluxButton(label: 'Disabled'),
            ],
          ),
        ),

        _section('Chips and segments'),
        FluxSliverPadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: FluxSpace.x2,
                runSpacing: FluxSpace.x2,
                children: [
                  const FluxChip(label: 'Unselected'),
                  const FluxChip(label: 'Selected', selected: true),
                  FluxChip(
                    label: 'Food',
                    selected: true,
                    tint: palette.forCategory('Food'),
                  ),
                  const FluxChip(
                    label: 'Dismissable',
                    selected: true,
                    trailingIcon: Icons.close_rounded,
                  ),
                  const FluxChip(
                    label: 'With icon',
                    icon: Icons.calendar_today_rounded,
                  ),
                ],
              ),
              const SizedBox(height: FluxSpace.x4),
              FluxSegmented<int>(
                value: _segment,
                onChanged: (value) => setState(() => _segment = value),
                options: const [(0, 'Month'), (1, 'Last'), (2, 'All')],
              ),
            ],
          ),
        ),

        _section('Charts'),
        FluxSliverPadding(
          child: FluxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FluxSparkline(
                  values: [3, 8, 5, 12, 9, 14, 11, 18, 13, 21],
                ),
                const SizedBox(height: FluxSpace.x5),
                FluxBars(
                  showLabels: true,
                  bars: [
                    for (var day = 1; day <= 14; day++)
                      FluxBar(
                        value: (day * 7 % 11).toDouble(),
                        label: day % 5 == 0 ? '$day' : '',
                        highlight: day == 9,
                      ),
                  ],
                ),
                const SizedBox(height: FluxSpace.x5),
                Row(
                  children: [
                    FluxDonut(
                      centreValue: '₹42,190',
                      centreLabel: 'spent',
                      slices: [
                        for (final entry in const [
                          ('Food', 40.0),
                          ('Transport', 25.0),
                          ('Bills', 18.0),
                          ('Shopping', 11.0),
                          ('Health', 6.0),
                        ])
                          FluxSlice(
                            label: entry.$1,
                            value: entry.$2,
                            color: palette.forCategory(entry.$1),
                            display: '₹${(entry.$2 * 100).round()}',
                          ),
                      ],
                    ),
                    const SizedBox(width: FluxSpace.x4),
                    Expanded(
                      child: FluxDonutLegend(
                        slices: [
                          for (final entry in const [
                            ('Food', 40.0),
                            ('Transport', 25.0),
                            ('Bills', 18.0),
                          ])
                            FluxSlice(
                              label: entry.$1,
                              value: entry.$2,
                              color: palette.forCategory(entry.$1),
                              display: '₹${(entry.$2 * 100).round()}',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FluxSpace.x5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: const [
                    FluxRing(fraction: 0.42, label: 'Food', detail: 'on track'),
                    FluxRing(fraction: 0.91, label: 'Bills', detail: 'close'),
                    FluxRing(fraction: 1.36, label: 'Shopping', detail: 'over'),
                  ],
                ),
                const SizedBox(height: FluxSpace.x5),
                const Row(
                  children: [
                    FluxDelta(fraction: 0.12),
                    SizedBox(width: FluxSpace.x2),
                    FluxDelta(fraction: -0.31),
                    SizedBox(width: FluxSpace.x2),
                    FluxDelta(fraction: 0.004),
                    SizedBox(width: FluxSpace.x2),
                    FluxDelta(fraction: 0.2, higherIsWorse: false),
                  ],
                ),
                const SizedBox(height: FluxSpace.x5),
                const FluxComparison(
                  currentLabel: 'August',
                  currentValue: 42190,
                  currentDisplay: '₹42,190',
                  previousLabel: 'July',
                  previousValue: 37600,
                  previousDisplay: '₹37,600',
                ),
              ],
            ),
          ),
        ),

        _section('Money'),
        FluxSliverPadding(
          child: FluxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                MoneyText('₹1,299', signed: true),
                MoneyText('₹84,000', incoming: true, signed: true),
                MoneyText('••••', muted: true),
                SizedBox(height: FluxSpace.x3),
                MoneyOdometer('₹1,84,320'),
              ],
            ),
          ),
        ),

        _section('Rows and groups'),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'Group header',
            footer: 'A footer explains the trade-off the rows cannot.',
            children: [
              const FluxRow(title: 'Plain row', value: 'Value'),
              FluxRow(
                title: 'With icon and chevron',
                subtitle: 'And a subtitle',
                icon: Icons.sms_outlined,
                chevron: true,
                onTap: _noop,
              ),
              FluxRow.toggle(
                title: 'Toggle',
                value: _toggle,
                onChanged: (value) => setState(() => _toggle = value),
              ),
              const FluxRow(title: 'Busy row', busy: true),
              FluxRow(
                title: 'Destructive',
                icon: Icons.delete_outline_rounded,
                danger: true,
                onTap: _noop,
              ),
            ],
          ),
        ),

        _section('Avatars'),
        FluxSliverPadding(
          child: Wrap(
            spacing: FluxSpace.x3,
            children: [
              for (final name in const ['Swiggy', 'Big Bazaar', 'Netflix', 'A'])
                FluxAvatar(name: name, tint: palette.forCategory(name)),
              FluxAvatar(
                name: 'Salary',
                tint: palette.income,
                icon: Icons.south_west_rounded,
              ),
            ],
          ),
        ),

        _section('Fields'),
        FluxSliverPadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FluxSearchField(controller: _field),
              const SizedBox(height: FluxSpace.x4),
              const FluxField(label: 'Label', hint: 'Hint text'),
              const SizedBox(height: FluxSpace.x4),
              const FluxField(
                label: 'With error',
                hint: '0',
                error: 'Enter an amount greater than zero.',
              ),
              const SizedBox(height: FluxSpace.x4),
              const FluxField(
                label: 'With helper',
                hint: 'sk-…',
                helper: 'Stored in the Android keystore.',
              ),
            ],
          ),
        ),

        _section('Banners'),
        SliverToBoxAdapter(
          child: Column(
            children: [
              const FluxBanner(
                title: 'Needs attention',
                message: '7 transactions need review.',
                tone: FluxBannerTone.attention,
                icon: Icons.rule_rounded,
                actionLabel: 'Review',
                onAction: _noop,
              ),
              const SizedBox(height: FluxSpace.x3),
              const FluxBanner(
                title: 'Something broke',
                message: 'The provider stopped responding.',
                tone: FluxBannerTone.danger,
                icon: Icons.error_outline_rounded,
              ),
              const SizedBox(height: FluxSpace.x3),
              const FluxBanner(
                title: 'Intelligence',
                message: 'No provider connected.',
                tone: FluxBannerTone.ai,
                icon: Icons.auto_awesome_outlined,
              ),
            ],
          ),
        ),

        _section('Loading and empty'),
        FluxSliverPadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              FluxRowSkeleton(),
              FluxRowSkeleton(),
              SizedBox(height: FluxSpace.x4),
              FluxEmpty(
                icon: Icons.inbox_outlined,
                title: 'No transactions yet',
                message: 'Run an import and this fills itself in.',
                actionLabel: 'Read my messages',
                onAction: _noop,
                compact: true,
              ),
            ],
          ),
        ),

        _section('Sheets and dialogs'),
        FluxSliverPadding(
          child: Column(
            children: [
              FluxButton(
                label: 'Open a sheet',
                kind: FluxButtonKind.secondary,
                onPressed: () => showFluxSheet<void>(
                  context: context,
                  builder: (context) => FluxSheetBody(
                    title: 'A sheet',
                    subtitle: 'One thing to fill in and finish',
                    actions: FluxButton(
                      label: 'Done',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    child: const FluxField(label: 'Amount', hint: '0'),
                  ),
                ),
              ),
              const SizedBox(height: FluxSpace.x2),
              FluxButton(
                label: 'Open a confirmation',
                kind: FluxButtonKind.secondary,
                onPressed: () => fluxConfirm(
                  context: context,
                  title: 'Delete this transaction?',
                  message: 'This removes it from every total.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _section(String title) =>
      SliverToBoxAdapter(child: FluxSectionHeader(title: title));

  static void _noop() {}
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Column(
      children: [
        Container(
          width: 52,
          height: 40,
          decoration: ShapeDecoration(
            color: color,
            shape: FluxRadius.shape(
              FluxRadius.xs,
              side: BorderSide(color: palette.line, width: 1),
            ),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 52,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FluxType.caption.copyWith(
              color: palette.textMuted,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }
}
