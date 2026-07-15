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
import 'widgets/money_chat_sheet.dart';

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
  bool _portalOpen = false;

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
    return Scaffold(
      extendBody: true,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -350 && _index < _pages.length - 1) {
            setState(() => _index++);
          } else if (velocity > 350 && _index > 0) {
            setState(() => _index--);
          }
        },
        child: Stack(
          children: [
            Positioned.fill(child: body),
            if (_portalOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _portalOpen = false),
                  child: ColoredBox(color: Colors.black.withValues(alpha: .48)),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: _FlowPortal(
                  open: _portalOpen,
                  selectedIndex: _index,
                  onToggle: () => setState(() => _portalOpen = !_portalOpen),
                  onAsk: () {
                    setState(() => _portalOpen = false);
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const MoneyChatSheet(),
                    );
                  },
                  onSelected: (index) => setState(() {
                    _index = index;
                    _portalOpen = false;
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowPortal extends StatelessWidget {
  const _FlowPortal({
    required this.open,
    required this.selectedIndex,
    required this.onToggle,
    required this.onAsk,
    required this.onSelected,
  });

  final bool open;
  final int selectedIndex;
  final VoidCallback onToggle;
  final VoidCallback onAsk;
  final ValueChanged<int> onSelected;

  static const _items = [
    (Icons.blur_on_rounded, 'Now', 'What is changing'),
    (Icons.route_rounded, 'Memory', 'Every money event'),
    (Icons.all_inclusive_rounded, 'Possible', 'Shape what comes next'),
    (Icons.auto_awesome_rounded, 'Oracle', 'Patterns and answers'),
  ];

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF090D16);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      width: open ? 430 : 176,
      constraints: const BoxConstraints(maxWidth: 430),
      padding: EdgeInsets.all(open ? 10 : 7),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .97),
        borderRadius: BorderRadius.circular(open ? 32 : 99),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 36,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: open
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < _items.length; index++)
                  _PortalDestination(
                    item: _items[index],
                    selected: selectedIndex == index,
                    onTap: () => onSelected(index),
                  ),
                const Divider(color: Colors.white12, height: 20),
                ListTile(
                  onTap: onAsk,
                  leading: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: Color(0xFFC7FF4A),
                  ),
                  title: const Text(
                    'Ask your money',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Answers grounded in your transactions',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
                Row(
                  children: [
                    const GlobalQuickActionButton(small: true),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Create a money event',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    IconButton(
                      onPressed: onToggle,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: onToggle,
              child: const SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.blur_circular_rounded, color: Color(0xFFC7FF4A)),
                    SizedBox(width: 10),
                    Text(
                      'Open flow',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _PortalDestination extends StatelessWidget {
  const _PortalDestination({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final (IconData, String, String) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Colors.white.withValues(alpha: .09) : Colors.transparent,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              item.$1,
              color: selected ? const Color(0xFFC7FF4A) : Colors.white54,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.$2,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    item.$3,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.circle, size: 7, color: Color(0xFFC7FF4A)),
          ],
        ),
      ),
    ),
  );
}
