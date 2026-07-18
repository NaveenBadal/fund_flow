import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_provider.dart';
import '../flow_os/system/system_components.dart';
import '../flow_os/agent/decision_sheet.dart';
import '../flow_os/foundation/flow_color.dart';
import '../flow_os/primitives/coordinate_label.dart';
import '../flow_os/primitives/cut_surface.dart';
import '../flow_os/primitives/loom_mark.dart';
import '../providers/expense_provider.dart';
import '../providers/notification_ingestion_provider.dart';
import '../services/development_update_service.dart';
import '../services/ollama_cloud_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/development_update_ui.dart';
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
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
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
                const SystemSectionLabel('Intelligence'),
                SystemNode(
                  code: 'AI-01',
                  title: 'AI connection',
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
                const SystemSectionLabel('Money sources'),
                const SystemNode(
                  code: 'EV-01',
                  title: 'Transaction messages',
                  detail: 'Checked only after you give permission',
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
                const SystemSectionLabel('Privacy'),
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
                const SystemSectionLabel('Personalization'),
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
                const SystemSectionLabel('Advanced'),
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
                  'Your records stay under your control',
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
      backgroundColor: FlowColor.canvas(context),
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
                const _SystemSheetHeader(
                  coordinate: 'MONEY / FALLBACK UNIT',
                  title: 'PRIMARY CURRENCY',
                  description:
                      'Used only when new evidence has no currency. Existing records keep their original unit.',
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final value in const [
                      'INR',
                      'USD',
                      'EUR',
                      'GBP',
                      'SGD',
                      'AED',
                    ])
                      _SystemChoicePort(
                        label: value,
                        selected: _currency == value,
                        onTap: () {
                          setState(() => _currency = value);
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _SystemCommit(
                  label: 'SAVE CURRENCY',
                  onTap: () async {
                    await _saveCurrency();
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
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
      backgroundColor: FlowColor.canvas(context),
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
                const _SystemSheetHeader(
                  coordinate: 'INTELLIGENCE / CONNECTION',
                  title: 'ATTACH OLLAMA CLOUD',
                  description:
                      'This reasoning engine powers Flow answers and extracts transaction evidence when you explicitly start analysis.',
                ),
                const SizedBox(height: 24),
                _SystemField(
                  label: 'CREDENTIAL / ENCRYPTED LOCAL STORAGE',
                  child: TextField(
                    controller: _key,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: 'Ollama API key',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show API key' : 'Hide API key',
                        onPressed: () {
                          setState(() => _obscure = !_obscure);
                          setSheetState(() {});
                        },
                        icon: Text(_obscure ? 'SHOW' : 'HIDE'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const CoordinateLabel('AI model'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final value in ollamaModelChoices)
                      _SystemChoicePort(
                        label: value,
                        selected: _model == value,
                        onTap: () {
                          setState(() => _model = value);
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _SystemField(
                  label: 'ENDPOINT / ADVANCED',
                  child: TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'Ollama endpoint',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _SystemChoicePort(
                        label: _testing ? 'TESTING…' : 'TEST',
                        selected: _connected,
                        onTap: _testing
                            ? () {}
                            : () async {
                                await _test();
                                setSheetState(() {});
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _SystemCommit(
                        label: 'VERIFY AND SAVE',
                        onTap: () async {
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
          await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: FlowColor.canvas(context),
            builder: (_) => const AgentDecisionSheet(
              title: 'Open notification channel?',
              description:
                  'Android will ask for notification access. Flow keeps supported transaction signals locally and ignores unrelated notifications.',
              confirmLabel: 'Open Android settings',
              notice:
                  'This optional channel can be disabled from the Control Map.',
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
    backgroundColor: FlowColor.canvas(context),
    builder: (context) => const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SystemSheetHeader(
              coordinate: 'PRIVACY / DATA BOUNDARY',
              title: 'Where your data lives',
              description:
                  'A precise map of what Flow processes, what the configured AI receives, and what remains on this device.',
            ),
            SizedBox(height: 24),
            SystemNode(
              code: 'OUT-01',
              title: 'SMS extraction',
              detail:
                  'Selected bank SMS text is sent to your configured Ollama endpoint to extract transaction details.',
              signal: NodeSignal.attention,
            ),
            SizedBox(height: 8),
            SystemNode(
              code: 'OUT-02',
              title: 'Assistant questions',
              detail:
                  'Ordinary questions share only structured MCP results. Original SMS is shared only when you request re-analysis and approve it.',
              signal: NodeSignal.private,
            ),
            SizedBox(height: 8),
            SystemNode(
              code: 'LOC-01',
              title: 'On this device',
              detail:
                  'Transactions, filters, settings, and verification evidence remain local unless an AI request explicitly needs them.',
              signal: NodeSignal.live,
            ),
          ],
        ),
      ),
    ),
  );

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class _SystemSheetHeader extends StatelessWidget {
  const _SystemSheetHeader({
    required this.coordinate,
    required this.title,
    required this.description,
  });
  final String coordinate;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LoomMark(size: 44),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoordinateLabel(coordinate),
            const SizedBox(height: 5),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: FlowColor.content(context),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: FlowColor.quiet(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SystemField extends StatelessWidget {
  const _SystemField({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => CutSurface(
    cut: 9,
    color: FlowColor.plane(context),
    accent: FlowColor.rule(context),
    padding: const EdgeInsets.fromLTRB(13, 9, 8, 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoordinateLabel(label, color: FlowColor.quiet(context)),
        child,
      ],
    ),
  );
}

class _SystemChoicePort extends StatelessWidget {
  const _SystemChoicePort({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 58, minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? FlowColor.loom : FlowColor.plane(context),
          border: Border.all(
            color: selected ? FlowColor.proof : FlowColor.rule(context),
          ),
        ),
        child: Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : FlowColor.quiet(context),
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: .55,
          ),
        ),
      ),
    ),
  );
}

class _SystemCommit extends StatelessWidget {
  const _SystemCommit({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CutSurface(
        cut: 9,
        color: FlowColor.loom,
        accent: FlowColor.proof,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        child: Center(
          child: Text(
            '$label →',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
            ),
          ),
        ),
      ),
    ),
  );
}
