import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'providers/expense_provider.dart';
import 'theme/app_theme.dart';
import 'screens/activity_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/intelligence_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/plan_screen.dart';
import 'services/notification_service.dart';
import 'services/drive_backup_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ProviderScope(child: ExpenseManagerApp()));
  // Non-essential integrations initialize after the first frame. This keeps
  // cold start independent of plugin and account-service latency.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future.wait([
      NotificationService.instance.init(),
      GoogleSignIn.instance.initialize(),
    ]);
    DriveBackupService.instance;
  });
}

class ExpenseManagerApp extends ConsumerWidget {
  const ExpenseManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsInitializer);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Fund Flow',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(null),
      darkTheme: AppTheme.dark(null),
      home: const _AppGate(),
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
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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
      final canCheck =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!canCheck) {
        setState(() {
          _unlocked = true;
          _authenticating = false;
        });
        return;
      }
      final authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to open Fund Flow',
        authMessages: const [AndroidAuthMessages(signInTitle: 'App Locked')],
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
                child: Icon(
                  Icons.lock_rounded,
                  size: 40,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'App Locked',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Authenticate to continue',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
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

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;

  static const _pages = [
    DashboardScreen(),
    ActivityScreen(),
    PlanScreen(),
    IntelligenceScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final sync = ref.read(syncProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      sync.resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      sync.pause();
    }
  }

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Today',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long_rounded),
      label: 'Activity',
    ),
    NavigationDestination(
      icon: Icon(Icons.track_changes_outlined),
      selectedIcon: Icon(Icons.track_changes_rounded),
      label: 'Plan',
    ),
    NavigationDestination(
      icon: Icon(Icons.auto_graph_outlined),
      selectedIcon: Icon(Icons.auto_graph_rounded),
      label: 'Insights',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(index: _index, children: _pages);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    extended: constraints.maxWidth >= 1180,
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Icon(
                        Icons.bolt_rounded,
                        size: 30,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: Text('Today'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        selectedIcon: Icon(Icons.receipt_long_rounded),
                        label: Text('Activity'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.track_changes_outlined),
                        selectedIcon: Icon(Icons.track_changes_rounded),
                        label: Text('Plan'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.auto_graph_outlined),
                        selectedIcon: Icon(Icons.auto_graph_rounded),
                        label: Text('Insights'),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: .4),
                ),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          extendBody: true,
          body: body,
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainer.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: NavigationBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: _destinations,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
