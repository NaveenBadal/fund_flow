import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'providers/expense_provider.dart';
import 'screens/analytics_screen.dart';
import 'screens/budget_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/subscriptions_screen.dart';
import 'services/notification_service.dart';
import 'services/drive_backup_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await FlutterGemma.initialize();
  await GoogleSignIn.instance.initialize();
  DriveBackupService.instance; // trigger listener
  runApp(const ProviderScope(child: ExpenseManagerApp()));
}

class ExpenseManagerApp extends ConsumerWidget {
  const ExpenseManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsInitializer);
    final themeMode = ref.watch(themeModeProvider);

    final subThemes = const FlexSubThemesData(
      blendOnLevel: 10,
      blendOnColors: false,
      useMaterial3Typography: true,
      useM2StyleDividerInM3: true,
      alignedDropdown: true,
      useInputDecoratorThemeInDialogs: true,
      cardRadius: 28,
      defaultRadius: 20,
      inputDecoratorRadius: 20,
      chipRadius: 999,
      fabUseShape: true,
      fabRadius: 20,
      navigationBarHeight: 72,
    );

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightScheme = lightDynamic?.harmonized();
        final darkScheme = darkDynamic?.harmonized();

        return MaterialApp(
          title: 'Expense Manager',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: lightScheme != null
              ? FlexThemeData.light(
                  colorScheme: lightScheme,
                  subThemesData: subThemes,
                  visualDensity: FlexColorScheme.comfortablePlatformDensity,
                  useMaterial3: true,
                  fontFamily: GoogleFonts.notoSans().fontFamily,
                )
              : FlexThemeData.light(
                  scheme: FlexScheme.materialBaseline,
                  surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
                  blendLevel: 7,
                  subThemesData: subThemes,
                  visualDensity: FlexColorScheme.comfortablePlatformDensity,
                  useMaterial3: true,
                  fontFamily: GoogleFonts.notoSans().fontFamily,
                ),
          darkTheme: darkScheme != null
              ? FlexThemeData.dark(
                  colorScheme: darkScheme,
                  subThemesData: subThemes.copyWith(blendOnLevel: 20),
                  visualDensity: FlexColorScheme.comfortablePlatformDensity,
                  useMaterial3: true,
                  fontFamily: GoogleFonts.notoSans().fontFamily,
                )
              : FlexThemeData.dark(
                  scheme: FlexScheme.materialBaseline,
                  surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
                  blendLevel: 13,
                  subThemesData: subThemes.copyWith(blendOnLevel: 20),
                  visualDensity: FlexColorScheme.comfortablePlatformDensity,
                  useMaterial3: true,
                  fontFamily: GoogleFonts.notoSans().fontFamily,
                ),
          home: const _AppGate(),
        );
      },
    );
  }
}

// ─── App gate: onboarding + app lock ─────────────────────────────────────

class _AppGate extends ConsumerWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingAsync = ref.watch(onboardingDoneProvider);

    return onboardingAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const AppShell(),
      data: (done) {
        if (!done) return const OnboardingScreen();
        return const _AppLockGate();
      },
    );
  }
}

class _AppLockGate extends ConsumerStatefulWidget {
  const _AppLockGate();

  @override
  ConsumerState<_AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<_AppLockGate> {
  bool _unlocked = false;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    _checkAndAuthenticate();
  }

  Future<void> _checkAndAuthenticate() async {
    final lockEnabled = ref.read(appLockEnabledProvider);
    if (!lockEnabled) {
      setState(() => _unlocked = true);
      return;
    }
    await _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    try {
      final auth = LocalAuthentication();
      final canCheck = await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!canCheck) {
        setState(() {
          _unlocked = true;
          _authenticating = false;
        });
        return;
      }
      final authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to open Expense Manager',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'App Locked',
          ),
        ],
      );
      setState(() {
        _unlocked = authenticated;
        _authenticating = false;
      });
    } catch (_) {
      setState(() {
        _unlocked = true; // fail open if auth errors
        _authenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return const AppShell();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.lock_rounded, size: 40, color: scheme.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'App Locked',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                'Authenticate to continue',
                style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _authenticating ? null : _authenticate,
                icon: const Icon(Icons.fingerprint_rounded),
                label: Text(_authenticating ? 'Authenticating…' : 'Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── App shell ────────────────────────────────────────────────────────────

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart_rounded),
      label: 'Analytics',
    ),
    NavigationDestination(
      icon: Icon(Icons.account_balance_wallet_outlined),
      selectedIcon: Icon(Icons.account_balance_wallet_rounded),
      label: 'Budgets',
    ),
    NavigationDestination(
      icon: Icon(Icons.repeat_outlined),
      selectedIcon: Icon(Icons.repeat_rounded),
      label: 'Subscriptions',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_index) {
      0 => const DashboardScreen(),
      1 => const AnalyticsScreen(),
      2 => const BudgetScreen(),
      3 => const SubscriptionsScreen(),
      _ => const DashboardScreen(),
    };

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}
