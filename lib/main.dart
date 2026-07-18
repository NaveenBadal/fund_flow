import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'flow_os/shell/command_rail.dart';
import 'flow_os/shell/command_column.dart';
import 'flow_os/foundation/flow_color.dart';
import 'flow_os/primitives/coordinate_label.dart';
import 'flow_os/primitives/cut_surface.dart';
import 'flow_os/primitives/loom_mark.dart';
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
import 'widgets/ui/flow_ui.dart';

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
      highContrastTheme: AppTheme.highContrastLight(null),
      highContrastDarkTheme: AppTheme.highContrastDark(null),
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: dark
              ? SystemUiOverlayStyle.light.copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness: Brightness.light,
                )
              : SystemUiOverlayStyle.dark.copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness: Brightness.dark,
                ),
          child: child ?? const SizedBox.shrink(),
        );
      },
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
      return const Scaffold(body: Center(child: FlowOrb(size: 52)));
    }
    if (settingsAsync.hasError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LoomMark(size: 48, state: LoomState.review),
                const SizedBox(height: 16),
                const CoordinateLabel(
                  'Boot / settings unavailable',
                  color: FlowColor.coral,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Security settings could not be loaded.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _GateAction(
                  label: 'RETRY SECURE BOOT',
                  onTap: () => ref.invalidate(settingsInitializer),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return onboardingAsync.when(
      loading: () => const Scaffold(body: Center(child: FlowOrb(size: 52))),
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
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LoomMark(size: 72, state: LoomState.offline),
              const SizedBox(height: 24),
              const CoordinateLabel(
                'Privacy gate / local identity',
                line: true,
              ),
              const SizedBox(height: 14),
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
                      ? FlowColor.quiet(context)
                      : FlowColor.coral,
                ),
              ),
              const SizedBox(height: 28),
              _GateAction(
                label: _authenticating ? 'PROVING IDENTITY…' : 'UNLOCK FLOW',
                onTap: _authenticating ? null : _authenticate,
                icon: Icons.fingerprint,
              ),
              if (_authError != null) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => ref
                      .read(appLockEnabledProvider.notifier)
                      .setEnabled(false),
                  child: const CoordinateLabel(
                    'Recovery / disable app lock',
                    color: FlowColor.coral,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GateAction extends StatelessWidget {
  const _GateAction({
    required this.label,
    required this.onTap,
    this.icon = Icons.refresh,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      child: CutSurface(
        color: onTap == null ? FlowColor.plane(context) : FlowColor.loom,
        accent: onTap == null ? FlowColor.rule(context) : FlowColor.proof,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: onTap == null ? FlowColor.quiet(context) : FlowColor.proof,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: onTap == null ? FlowColor.quiet(context) : Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: .7,
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
    final pages = Stack(
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < _pages.length; index++)
          _DestinationLayer(
            active: index == _destination,
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
                CommandColumn(
                  selectedIndex: _destination,
                  extended: constraints.maxWidth >= AppBreakpoint.extendedRail,
                  onSelected: _selectDestination,
                ),
                VerticalDivider(
                  width: 1,
                  color: scheme.outlineVariant.withValues(alpha: .5),
                ),
                Expanded(child: pages),
              ],
            ),
          );
        }
        return Scaffold(
          body: pages,
          bottomNavigationBar: CommandRail(
            selectedIndex: _destination,
            onSelected: _selectDestination,
          ),
        );
      },
    );
  }
}

// ignore: unused_element
class _FlowNavigationRail extends StatelessWidget {
  const _FlowNavigationRail({
    required this.selectedIndex,
    required this.extended,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.blur_on_outlined, 'Ask', 'Ask Flow'),
      (Icons.receipt_long_outlined, 'Proof', 'Evidence timeline'),
      (Icons.person_outline_rounded, 'Control', 'Control and privacy'),
    ];
    return FlowAtmosphere(
      alignment: const Alignment(-1, -1),
      child: SafeArea(
        child: SizedBox(
          width: extended ? 232 : 88,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 8),
                  child: Row(
                    mainAxisAlignment: extended
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      const FlowOrb(size: 38),
                      if (extended) ...[
                        const SizedBox(width: 12),
                        Text(
                          'Fund Flow',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 52),
                for (var index = 0; index < items.length; index++) ...[
                  _FlowRailDestination(
                    selected: selectedIndex == index,
                    extended: extended,
                    icon: items[index].$1,
                    label: items[index].$2,
                    tooltip: items[index].$3,
                    onTap: () => onDestinationSelected(index),
                  ),
                  const SizedBox(height: 8),
                ],
                const Spacer(),
                if (extended)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Private by design',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowRailDestination extends StatelessWidget {
  const _FlowRailDestination({
    required this.selected,
    required this.extended,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final bool selected;
  final bool extended;
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: AnimatedContainer(
            height: 56,
            duration: reduce ? Duration.zero : AppMotion.medium,
            curve: AppMotion.emphasizedDecelerate,
            padding: EdgeInsets.symmetric(horizontal: extended ? 16 : 0),
            decoration: ShapeDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: .1)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: selected
                    ? BorderSide(color: scheme.primary.withValues(alpha: .24))
                    : BorderSide.none,
              ),
            ),
            child: Row(
              mainAxisAlignment: extended
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                if (label == 'Ask')
                  FlowOrb(
                    size: 24,
                    state: selected ? FlowOrbState.ready : FlowOrbState.offline,
                  )
                else
                  Icon(
                    icon,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                if (extended) ...[
                  const SizedBox(width: 14),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps every primary destination mounted so expensive history, Markdown, and
/// settings trees are never constructed during a navigation animation.
class _DestinationLayer extends StatelessWidget {
  const _DestinationLayer({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !active,
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
    final scheme = Theme.of(context).colorScheme;
    const destinations = [
      (Icons.blur_on_outlined, Icons.blur_on_rounded, 'Ask', 'Ask Flow'),
      (
        Icons.receipt_long_outlined,
        Icons.receipt_long_rounded,
        'Proof',
        'Evidence timeline',
      ),
      (
        Icons.person_outline_rounded,
        Icons.person_rounded,
        'Control',
        'Control and privacy',
      ),
    ];
    return ColoredBox(
      color: scheme.surface.withValues(alpha: .96),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: FlowGlass(
          radius: AppRadius.xl,
          padding: const EdgeInsets.all(5),
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                for (var index = 0; index < destinations.length; index++)
                  Expanded(
                    child: _FlowDestination(
                      selected: selectedIndex == index,
                      icon: destinations[index].$1,
                      selectedIcon: destinations[index].$2,
                      label: destinations[index].$3,
                      tooltip: destinations[index].$4,
                      onTap: () => onDestinationSelected(index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowDestination extends StatelessWidget {
  const _FlowDestination({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final showLabel =
        selected && MediaQuery.textScalerOf(context).scale(1) <= 1.3;
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Center(
            child: AnimatedContainer(
              width: showLabel ? 108 : 52,
              height: 46,
              duration: reduceMotion ? Duration.zero : AppMotion.medium,
              curve: AppMotion.emphasizedDecelerate,
              // Leave a small rounding buffer for the longest label
              // ("Activity"). At some Android font metrics, 12px padding on
              // both sides exceeded the compact capsule by a fraction of a
              // logical pixel.
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: ShapeDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: .1)
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                  side: selected
                      ? BorderSide(color: scheme.primary.withValues(alpha: .24))
                      : BorderSide.none,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: reduceMotion ? Duration.zero : AppMotion.fast,
                    child: label == 'Ask'
                        ? FlowOrb(
                            key: const ValueKey('flow-field'),
                            size: 22,
                            state: selected
                                ? FlowOrbState.ready
                                : FlowOrbState.offline,
                          )
                        : Icon(
                            selected ? selectedIcon : icon,
                            key: ValueKey(selected),
                            size: 22,
                            color: selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                  ),
                  Flexible(
                    child: AnimatedSize(
                      duration: reduceMotion ? Duration.zero : AppMotion.medium,
                      curve: AppMotion.emphasizedDecelerate,
                      child: showLabel
                          ? Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: 8,
                              ),
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
