import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_provider.dart';
import '../flow_os/system/system_components.dart';
import '../providers/expense_provider.dart';
import '../providers/notification_ingestion_provider.dart';
import '../services/development_update_service.dart';
import '../services/ollama_cloud_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/development_update_ui.dart';
import '../widgets/ui/flow_ui.dart';
import 'audit_screen.dart';
import 'custom_categories_screen.dart';
import 'logs_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _key;
  late final TextEditingController _url;
  late String _model;
  late String _currency;
  late int _lookback;
  bool _obscure = true;
  bool _testing = false;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: ref.read(ollamaApiKeyProvider));
    _url = TextEditingController(text: ref.read(ollamaBaseUrlProvider));
    _currency = ref.read(preferredCurrencyProvider);
    _model = ref.read(ollamaModelProvider);
    _lookback = ref.read(syncLookbackProvider);
  }

  @override
  void dispose() {
    _key.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final private = ref.watch(privateModeProvider);
    final locked = ref.watch(appLockEnabledProvider);
    final capture = ref.watch(notificationParsingEnabledProvider);
    final ingestion = ref.watch(notificationIngestionProvider);
    final themeMode = ref.watch(themeModeProvider);
    final aiConfigured = ref.watch(ollamaApiKeyProvider).trim().isNotEmpty;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentInset = screenWidth > AppBreakpoint.contentMax + 40
        ? (screenWidth - AppBreakpoint.contentMax) / 2
        : AppSpacing.lg;
    final effectiveAi = _connected || aiConfigured;
    final themeLabel = switch (themeMode) {
      ThemeMode.light => 'Light field',
      ThemeMode.dark => 'Dark field',
      ThemeMode.system => 'Follow device',
    };
    return Scaffold(
      body: Column(
        children: [
          SystemMasthead(aiOnline: effectiveAi),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(contentInset, 0, contentInset, 40),
              children: [
                const SystemSectionLabel('NODE GROUP / INTELLIGENCE'),
                SystemNode(
                  code: 'AI-01',
                  title: 'Flow intelligence',
                  detail: _testing
                      ? 'Testing encrypted connection…'
                      : effectiveAi
                      ? 'Online · $_model'
                      : 'Offline · required for analysis and answers',
                  signal: _testing
                      ? NodeSignal.attention
                      : effectiveAi
                      ? NodeSignal.live
                      : NodeSignal.attention,
                  onTap: _showAiConnection,
                ),
                const SystemSectionLabel('NODE GROUP / EVIDENCE CHANNELS'),
                const SystemNode(
                  code: 'EV-01',
                  title: 'Transaction messages',
                  detail: 'Primary evidence · analyzed only after consent',
                  signal: NodeSignal.private,
                ),
                const SizedBox(height: 8),
                SystemNode(
                  code: 'EV-02',
                  title: 'Notification continuity',
                  detail: capture
                      ? ingestion.accessEnabled
                            ? 'Listening for supported transaction signals'
                            : 'Android access still required'
                      : 'Optional real-time evidence channel',
                  signal: capture ? NodeSignal.live : NodeSignal.neutral,
                  control: BinaryRail(
                    value: capture,
                    onChanged: _toggleCapture,
                  ),
                ),
                const SizedBox(height: 8),
                SystemNode(
                  code: 'EV-03',
                  title: 'Evidence horizon',
                  detail: 'How far Flow looks back when rebuilding proof',
                  signal: NodeSignal.private,
                  control: StepRail(
                    value: '${_lookback}D',
                    onDecrease: () {
                      setState(() => _lookback = (_lookback - 7).clamp(7, 180));
                      _saveMemory();
                    },
                    onIncrease: () {
                      setState(() => _lookback = (_lookback + 7).clamp(7, 180));
                      _saveMemory();
                    },
                  ),
                ),
                const SystemSectionLabel('NODE GROUP / PRIVACY'),
                SystemNode(
                  code: 'PR-01',
                  title: 'Device authentication',
                  detail: 'Guard Flow whenever the application opens',
                  signal: locked ? NodeSignal.live : NodeSignal.neutral,
                  control: BinaryRail(
                    value: locked,
                    onChanged: (value) => ref
                        .read(appLockEnabledProvider.notifier)
                        .setEnabled(value),
                  ),
                ),
                const SizedBox(height: 8),
                SystemNode(
                  code: 'PR-02',
                  title: 'Data boundary',
                  detail: 'Inspect exactly what remains local and what leaves',
                  signal: NodeSignal.private,
                  onTap: _showPrivacy,
                ),
                const SizedBox(height: 8),
                SystemNode(
                  code: 'PR-03',
                  title: 'Amount visibility',
                  detail: private
                      ? 'Values veiled throughout the interface'
                      : 'Values visible throughout the interface',
                  signal: private ? NodeSignal.private : NodeSignal.neutral,
                  control: BinaryRail(
                    value: !private,
                    onLabel: 'SHOW',
                    offLabel: 'VEIL',
                    onChanged: (value) =>
                        ref.read(privateModeProvider.notifier).set(!value),
                  ),
                ),
                const SystemSectionLabel('NODE GROUP / PERSONAL FIELD'),
                SystemNode(
                  code: 'UI-01',
                  title: 'Appearance',
                  detail: '$themeLabel · tap to change field state',
                  onTap: () => _setTheme(switch (themeMode) {
                    ThemeMode.system => ThemeMode.dark,
                    ThemeMode.dark => ThemeMode.light,
                    ThemeMode.light => ThemeMode.system,
                  }),
                ),
                const SizedBox(height: 8),
                SystemNode(
                  code: 'MO-01',
                  title: 'Primary currency',
                  detail: '$_currency · fallback when evidence has no currency',
                  onTap: _showMoneyPreferences,
                ),
                const SystemSectionLabel('NODE GROUP / DIAGNOSTICS'),
                SystemNode(
                  code: 'DX-01',
                  title: 'Import history',
                  detail: 'Trace each ingestion and extraction decision',
                  onTap: () => _push(const AuditScreen()),
                ),
                const SizedBox(height: 8),
                SystemNode(
                  code: 'DX-02',
                  title: 'Category library',
                  detail: 'Control the language used to organize evidence',
                  onTap: () => _push(const CustomCategoriesScreen()),
                ),
                const SizedBox(height: 8),
                SystemNode(
                  code: 'DX-03',
                  title: 'AI activity log',
                  detail: 'Inspect local agent operations and failures',
                  onTap: () => _push(const LogsScreen()),
                ),
                if (githubDevelopmentUpdatesEnabled) ...[
                  const SizedBox(height: 12),
                  const DevelopmentUpdateSettingsCard(),
                ],
                const SizedBox(height: 28),
                Text(
                  'LOCAL RECORDS / USER CONTROLLED / PROOF BOUND',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoneyPreferences() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FlowSheetHeader(
                  leading: Icon(Icons.payments_outlined),
                  title: 'Primary currency',
                  description:
                      'Used for new transactions, monthly guides, and spending limits. Existing records keep their original currency.',
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [
                    for (final value in const [
                      'INR',
                      'USD',
                      'EUR',
                      'GBP',
                      'SGD',
                      'AED',
                    ])
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _currency = value);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await _saveCurrency();
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    child: const Text('Save currency'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAiConnection() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FlowSheetHeader(
                  leading: FlowOrb(size: 44),
                  title: 'Connect Ollama Cloud',
                  description:
                      'Used for Flow answers and transaction SMS understanding when you start them.',
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _key,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'API key',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show API key' : 'Hide API key',
                      onPressed: () {
                        setState(() => _obscure = !_obscure);
                        setSheetState(() {});
                      },
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _model,
                  decoration: const InputDecoration(labelText: 'Model'),
                  items: [
                    for (final value in ollamaModelChoices)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _model = value);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Endpoint'),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _testing
                            ? null
                            : () async {
                                await _test();
                                setSheetState(() {});
                              },
                        child: Text(_testing ? 'Testing…' : 'Test'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final valid = await _test(notify: false);
                          if (!valid) {
                            _notify(
                              'Connection failed. Nothing was saved. Check the key and endpoint.',
                            );
                            setSheetState(() {});
                            return;
                          }
                          await _saveAi();
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                        child: const Text('Verify and save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _notify(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _setTheme(ThemeMode mode) async {
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
    await ref
        .read(secureStorageProvider)
        .write(key: 'theme_mode', value: mode.toString());
  }

  Future<void> _toggleCapture(bool value) async {
    if (value) {
      final proceed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              icon: const Icon(Icons.notifications_active_outlined),
              title: const Text('Allow transaction capture?'),
              content: const Text(
                'Android will ask you to grant notification access. Flow keeps supported bank notification text on this device and ignores unrelated notifications.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open Android settings'),
                ),
              ],
            ),
          ) ??
          false;
      if (!proceed) return;
    }
    await ref.read(notificationIngestionProvider.notifier).setEnabled(value);
  }

  Future<void> _saveCurrency() async {
    await ref.read(preferredCurrencyProvider.notifier).setCurrency(_currency);
    _notify('Primary currency saved.');
  }

  Future<void> _saveMemory() async {
    ref.read(syncLookbackProvider.notifier).setDays(_lookback);
    await ref
        .read(secureStorageProvider)
        .write(key: 'sync_lookback_days', value: '$_lookback');
  }

  Future<void> _saveAi() async {
    final url = _url.text.trim().isEmpty
        ? defaultOllamaBaseUrl
        : _url.text.trim();
    await Future.wait([
      ref
          .read(secureStorageProvider)
          .write(key: ollamaApiKeyStorageKey, value: _key.text.trim()),
      ref
          .read(secureStorageProvider)
          .write(key: ollamaBaseUrlStorageKey, value: url),
      ref
          .read(secureStorageProvider)
          .write(key: ollamaModelStorageKey, value: _model),
    ]);
    ref.read(ollamaApiKeyProvider.notifier).set(_key.text.trim());
    ref.read(ollamaBaseUrlProvider.notifier).set(url);
    ref.read(ollamaModelProvider.notifier).set(_model);
    _notify('AI connection saved.');
  }

  Future<bool> _test({bool notify = true}) async {
    setState(() => _testing = true);
    final service = OllamaCloudService(
      apiKey: _key.text.trim(),
      baseUrl: _url.text.trim().isEmpty
          ? defaultOllamaBaseUrl
          : _url.text.trim(),
      model: _model,
    );
    final ok = await service.validateKey();
    service.close();
    if (!mounted) return false;
    setState(() {
      _testing = false;
      _connected = ok;
    });
    if (notify) {
      _notify(
        ok
            ? 'Ollama is connected.'
            : 'Connection failed. Check the key and endpoint.',
      );
    }
    return ok;
  }

  Future<void> _showPrivacy() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FlowSheetHeader(
              leading: Icon(Icons.privacy_tip_outlined),
              title: 'Data and AI privacy',
              description:
                  'A clear map of what Flow processes and where your financial evidence stays.',
            ),
            SizedBox(height: 24),
            _PrivacyFact(
              icon: Icons.sms_outlined,
              title: 'SMS extraction',
              detail:
                  'Selected bank SMS text is sent to your configured Ollama endpoint to extract transaction details.',
            ),
            SizedBox(height: 20),
            _PrivacyFact(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Assistant questions',
              detail:
                  'Ordinary questions share only structured MCP results. Original SMS is shared only when you request re-analysis and approve it.',
            ),
            SizedBox(height: 20),
            _PrivacyFact(
              icon: Icons.storage_outlined,
              title: 'On this device',
              detail:
                  'Transactions, filters, settings, and verification evidence remain local unless an AI request explicitly needs them.',
            ),
          ],
        ),
      ),
    ),
  );

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

// TODO(flow-loom-demolition): delete with the remaining legacy sheet helpers.
// ignore: unused_element
class _ControlStatus extends StatelessWidget {
  const _ControlStatus({
    required this.aiConfigured,
    required this.locked,
    required this.private,
  });

  final bool aiConfigured;
  final bool locked;
  final bool private;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(44),
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(20),
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FlowOrb(
                size: 44,
                state: aiConfigured ? FlowOrbState.ready : FlowOrbState.offline,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SYSTEM SIGNAL',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: FlowPalette.signalCyan,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      aiConfigured ? 'Flow can understand' : 'Flow needs AI',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ControlSignal(
                label: aiConfigured ? 'AI CONNECTED' : 'AI OFFLINE',
                active: aiConfigured,
              ),
              const _ControlSignal(label: 'SMS ON REQUEST', active: true),
              _ControlSignal(
                label: locked ? 'APP LOCKED' : 'APP UNLOCKED',
                active: locked,
              ),
              _ControlSignal(
                label: private ? 'AMOUNTS HIDDEN' : 'AMOUNTS VISIBLE',
                active: private,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlSignal extends StatelessWidget {
  const _ControlSignal({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.fade,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 9,
                letterSpacing: .55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
    child: Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: FlowPalette.signalCyan,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text.toUpperCase(),
            maxLines: 2,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w900,
              letterSpacing: .9,
            ),
          ),
        ),
        if (MediaQuery.textScalerOf(context).scale(1) <= 1.3) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .16),
            ),
          ),
        ],
      ],
    ),
  );
}

// ignore: unused_element
class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  static const _options = [
    (ThemeMode.system, Icons.brightness_auto_outlined, 'System'),
    (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
    (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final adaptive =
        MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    if (adaptive) {
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final option in _options)
            ChoiceChip(
              selected: value == option.$1,
              avatar: Icon(option.$2, size: 18),
              label: Text(option.$3),
              onSelected: (_) => onChanged(option.$1),
            ),
        ],
      );
    }
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: [
        for (final option in _options)
          ButtonSegment(
            value: option.$1,
            icon: Icon(option.$2),
            label: Text(option.$3),
          ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

// ignore: unused_element
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(32),
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(18),
        ),
        child: Material(
          color: scheme.surfaceContainer,
          child: Stack(
            children: [
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: scheme.primary.withValues(alpha: .48)),
              ),
              Column(children: children),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyFact extends StatelessWidget {
  const _PrivacyFact({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
