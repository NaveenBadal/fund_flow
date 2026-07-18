import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'providers/expense_provider.dart';
import 'providers/development_update_provider.dart';
import 'providers/notification_ingestion_provider.dart';
import 'theme/app_theme.dart';
import 'screens/activity_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_tokens.dart';
import 'widgets/money_chat_sheet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ProviderScope(child: ExpenseManagerApp()));
  // Non-essential integrations initialize after the first frame. This keeps
  // cold start independent of plugin latency.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await NotificationService.instance.init();
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
  int _destination = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      MoneyChatSheet(
        key: const PageStorageKey('flow'),
        fullScreen: true,
        onOpenSettings: _openSettings,
        onOpenActivity: () => _selectDestination(1),
      ),
      ActivityScreen(
        key: const PageStorageKey('activity'),
        onOpenSettings: _openSettings,
      ),
      const SettingsScreen(key: PageStorageKey('you')),
    ];
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

  void _selectDestination(int value) {
    if (value == _destination) return;
    HapticFeedback.selectionClick();
    setState(() => _destination = value);
  }

  void _openSettings() {
    _selectDestination(2);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pages = Stack(
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < _pages.length; index++)
          _DestinationLayer(
            active: index == _destination,
            reduceMotion: reduceMotion,
            child: _pages[index],
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppBreakpoint.rail;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _destination,
                  extended: constraints.maxWidth >= AppBreakpoint.extendedRail,
                  groupAlignment: -.72,
                  onDestinationSelected: _selectDestination,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.blur_on_outlined),
                      selectedIcon: Icon(Icons.blur_on_rounded),
                      label: Text('Flow'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long_rounded),
                      label: Text('Activity'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: Text('You'),
                    ),
                  ],
                ),
                VerticalDivider(width: 1, color: scheme.outlineVariant),
                Expanded(child: pages),
              ],
            ),
          );
        }
        return Scaffold(
          body: pages,
          bottomNavigationBar: FlowNavigationBar(
            selectedIndex: _destination,
            onDestinationSelected: _selectDestination,
          ),
        );
      },
    );
  }
}

/// Keeps every primary destination mounted so expensive history, Markdown, and
/// settings trees are never constructed during a navigation animation.
class _DestinationLayer extends StatelessWidget {
  const _DestinationLayer({
    required this.active,
    required this.reduceMotion,
    required this.child,
  });

  final bool active;
  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotion ? Duration.zero : AppMotion.fast;
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: duration,
      curve: AppMotion.emphasizedDecelerate,
      child: AnimatedScale(
        scale: active ? 1 : .992,
        duration: duration,
        curve: AppMotion.emphasizedDecelerate,
        child: TickerMode(
          enabled: active,
          child: ExcludeSemantics(
            excluding: !active,
            child: IgnorePointer(
              ignoring: !active,
              child: FocusScope(canRequestFocus: active, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone navigation occupies layout space so it can never cover content or
/// collide with a screen-level action. See docs/design_system.md.
class FlowNavigationBar extends StatelessWidget {
  const FlowNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: onDestinationSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.blur_on_outlined),
          selectedIcon: Icon(Icons.blur_on_rounded),
          label: 'Flow',
          tooltip: 'Flow agent',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: 'Activity',
          tooltip: 'Activity',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'You',
          tooltip: 'Your settings and privacy',
        ),
      ],
    );
  }
}
