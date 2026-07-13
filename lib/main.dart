import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'providers/expense_provider.dart';
import 'providers/development_update_provider.dart';
import 'providers/notification_ingestion_provider.dart';
import 'theme/app_theme.dart';
import 'screens/activity_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/intelligence_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/plan_screen.dart';
import 'services/notification_service.dart';
import 'services/drive_backup_service.dart';
import 'widgets/global_quick_action.dart';

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
    final settingsAsync = ref.watch(settingsInitializer);

    if (settingsAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (settingsAsync.hasError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.security_rounded, size: 42),
                const SizedBox(height: 16),
                const Text(
                  'Security settings could not be loaded.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(settingsInitializer),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

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

class _AppLockGateState extends ConsumerState<_AppLockGate>
    with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _authenticating = false;
  bool _backgrounded = false;
  String? _authError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAndAuthenticate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final enabled = ref.read(appLockEnabledProvider);
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        enabled &&
        !_authenticating) {
      _backgrounded = true;
      if (_unlocked && mounted) setState(() => _unlocked = false);
      return;
    }
    if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      if (enabled && !_authenticating) _authenticate();
    }
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
    setState(() {
      _authenticating = true;
      _authError = null;
    });
    try {
      final auth = LocalAuthentication();
      final canCheck =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!mounted) return;
      if (!canCheck) {
        await ref.read(appLockEnabledProvider.notifier).setEnabled(false);
        if (!mounted) return;
        setState(() {
          _unlocked = true;
          _authenticating = false;
          _authError = null;
        });
        return;
      }
      final authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to open Fund Flow',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Fund Flow is locked',
            cancelButton: 'Cancel',
          ),
        ],
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (!mounted) return;
      setState(() {
        _unlocked = authenticated;
        _authenticating = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _unlocked = false;
        _authenticating = false;
        _authError = 'Authentication was unavailable. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(appLockEnabledProvider, (previous, enabled) {
      if (!mounted) return;
      if (!enabled) {
        setState(() {
          _unlocked = true;
          _authError = null;
        });
      } else if (previous == false && !_authenticating) {
        setState(() => _unlocked = false);
        _authenticate();
      }
    });

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
                _authError ?? 'Authenticate to continue',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: _authError == null
                      ? scheme.onSurfaceVariant
                      : scheme.error,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _authenticating ? null : _authenticate,
                icon: const Icon(Icons.fingerprint_rounded),
                label: Text(_authenticating ? 'Authenticating…' : 'Unlock'),
              ),
              if (_authError != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref
                      .read(appLockEnabledProvider.notifier)
                      .setEnabled(false),
                  child: const Text('Disable app lock'),
                ),
              ],
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(developmentUpdateProvider.notifier).check(silent: true);
      await ref.read(settingsInitializer.future);
      if (!mounted) return;
      ref.read(notificationIngestionProvider.notifier).processPending();
    });
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
      ref.read(notificationIngestionProvider.notifier).processPending();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      sync.pause();
    }
  }

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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 30,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 18),
                          const GlobalQuickActionButton(small: true),
                        ],
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
            child: _ActionDock(
              selectedIndex: _index,
              onSelected: (i) => setState(() => _index = i),
            ),
          ),
        );
      },
    );
  }
}

class _ActionDock extends StatelessWidget {
  const _ActionDock({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Today'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Activity'),
    (Icons.track_changes_outlined, Icons.track_changes_rounded, 'Plan'),
    (Icons.auto_graph_outlined, Icons.auto_graph_rounded, 'Insights'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .12),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          _DockItem(
            item: _items[0],
            selected: selectedIndex == 0,
            onTap: () => onSelected(0),
          ),
          _DockItem(
            item: _items[1],
            selected: selectedIndex == 1,
            onTap: () => onSelected(1),
          ),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlobalQuickActionButton(),
                SizedBox(height: 2),
                Text(
                  'Add',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          _DockItem(
            item: _items[2],
            selected: selectedIndex == 2,
            onTap: () => onSelected(2),
          ),
          _DockItem(
            item: _items[3],
            selected: selectedIndex == 3,
            onTap: () => onSelected(3),
          ),
        ],
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final (IconData, IconData, String) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: item.$3,
        child: InkResponse(
          onTap: onTap,
          radius: 30,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Icon(selected ? item.$2 : item.$1, size: 21),
              ),
              const SizedBox(height: 3),
              Text(
                item.$3,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
