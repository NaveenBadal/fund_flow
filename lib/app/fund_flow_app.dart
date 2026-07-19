import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/preferences.dart';
import '../ui2/tokens/flow_theme.dart';
import 'app_controller.dart';
import 'app_experience.dart';

class FundFlowApp extends ConsumerWidget {
  const FundFlowApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance =
        ref.watch(appControllerProvider).value?.preferences.appearance ??
        AppearancePreference.system;
    final mode = switch (appearance) {
      AppearancePreference.system => ThemeMode.system,
      AppearancePreference.light => ThemeMode.light,
      AppearancePreference.dark => ThemeMode.dark,
    };
    return MaterialApp(
      title: 'Fund Flow',
      debugShowCheckedModeBanner: false,
      theme: FlowTheme.light(),
      darkTheme: FlowTheme.dark(),
      themeMode: mode,
      home: const AppExperience(),
    );
  }
}
