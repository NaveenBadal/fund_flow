import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/flux.dart';
import '../domain/preferences.dart';
import 'app_controller.dart';
import 'app_experience.dart';

/// Matches the status and navigation bar glyphs to the theme.
///
/// Edge-to-edge means system bars sit over app content, so dark glyphs on a dark
/// background is a real legibility failure rather than a cosmetic mismatch.
class _SystemBars extends StatelessWidget {
  const _SystemBars({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: const Color(0x00000000),
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: const Color(0x00000000),
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: child,
    );
  }
}

class FundFlowApp extends ConsumerWidget {
  const FundFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance =
        ref.watch(appControllerProvider).value?.preferences.appearance ??
        AppearancePreference.system;
    return MaterialApp(
      title: 'Fund Flow',
      debugShowCheckedModeBanner: false,
      theme: FluxTheme.light,
      darkTheme: FluxTheme.dark,
      themeMode: switch (appearance) {
        AppearancePreference.system => ThemeMode.system,
        AppearancePreference.light => ThemeMode.light,
        AppearancePreference.dark => ThemeMode.dark,
      },
      // Text scaling is honoured, but a 2× headline turns a summary into a
      // scroll. Capping it keeps the layout intact while still respecting a
      // real accessibility need.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.4,
        // Flux pages are built from plain surfaces rather than Scaffolds, so
        // nothing else in the tree supplies a Material. Without one, text
        // inherits Flutter's fallback style and every label renders with a
        // yellow debug underline.
        child: Material(
          type: MaterialType.transparency,
          child: _SystemBars(child: child!),
        ),
      ),
      home: const AppExperience(),
    );
  }
}
