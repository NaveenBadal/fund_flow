import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../design/flux.dart';
import '../../domain/preferences.dart';

/// Theme and currency.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  /// Currencies offered by name.
  ///
  /// A free-text field here produces "Rs", "rupees" and "inr" in the same
  /// database, and every total then has to guess which of them are the same
  /// thing. A short list of codes keeps the ledger summable.
  static const _currencies = [
    ('INR', 'Indian rupee'),
    ('USD', 'US dollar'),
    ('EUR', 'Euro'),
    ('GBP', 'Pound sterling'),
    ('AED', 'UAE dirham'),
    ('SGD', 'Singapore dollar'),
    ('AUD', 'Australian dollar'),
    ('CAD', 'Canadian dollar'),
    ('JPY', 'Japanese yen'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final prefs = app?.preferences;
    if (prefs == null) {
      return const FluxDetailPage(title: 'Appearance', slivers: []);
    }
    final controller = ref.read(appControllerProvider.notifier);

    return FluxDetailPage(
      title: 'Appearance',
      slivers: [
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'Theme',
            footer:
                'Light and dark are the same design expressed twice, so neither '
                'is the real one — the device already knows which you want.',
            children: [
              for (final option in const [
                (
                  AppearancePreference.system,
                  'Match device',
                  Icons.brightness_auto_rounded,
                ),
                (
                  AppearancePreference.light,
                  'Light',
                  Icons.light_mode_outlined,
                ),
                (AppearancePreference.dark, 'Dark', Icons.dark_mode_outlined),
              ])
                FluxRow(
                  title: option.$2,
                  icon: option.$3,
                  iconColor: prefs.appearance == option.$1
                      ? palette.iris
                      : null,
                  trailing: prefs.appearance == option.$1
                      ? Icon(Icons.check_rounded, size: 18, color: palette.iris)
                      : null,
                  onTap: () => controller.updatePreferences(
                    prefs.copyWith(appearance: option.$1),
                  ),
                ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'Currency',
            footer:
                'Used for anything you add by hand. Imported transactions keep '
                'whatever currency their message stated, and currencies are '
                'never added together.',
            children: [
              FluxRow(
                title: 'Default currency',
                value: prefs.currency,
                icon: Icons.payments_outlined,
                chevron: true,
                onTap: () async {
                  final chosen = await showFluxPicker<String>(
                    context: context,
                    title: 'Default currency',
                    selected: prefs.currency,
                    options: [
                      for (final entry in _currencies)
                        (entry.$1, '${entry.$1} · ${entry.$2}'),
                    ],
                  );
                  if (chosen != null) {
                    await controller.updatePreferences(
                      prefs.copyWith(currency: chosen),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
