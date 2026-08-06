import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/preferences.dart';
import '../ui/theme/precision_theme.dart';
import 'app_controller.dart';
import 'app_experience.dart';

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
      theme: PrecisionTheme.lightTheme,
      darkTheme: PrecisionTheme.darkTheme,
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
        child: child!,
      ),
      home: const AppExperience(),
    );
  }
}
