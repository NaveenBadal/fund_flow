import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/notification_ingestion_provider.dart';
import '../services/bank_csv_importer.dart';
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
  late final TextEditingController _income;
  late final TextEditingController _buffer;
  late String _model;
  late String _currency;
  late int _lookback;
  bool _obscure = true;
  bool _testing = false;
  bool _connected = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: ref.read(ollamaApiKeyProvider));
    _url = TextEditingController(text: ref.read(ollamaBaseUrlProvider));
    final plan = ref.read(monthlyPlanProvider);
    _income = TextEditingController(
      text: plan.income == 0 ? '' : '${plan.income}',
    );
    _buffer = TextEditingController(
      text: plan.buffer == 0 ? '' : '${plan.buffer}',
    );
    _currency = ref.read(preferredCurrencyProvider);
    _model = ref.read(ollamaModelProvider);
    _lookback = ref.read(syncLookbackProvider);
  }

  @override
  void dispose() {
    _key.dispose();
    _url.dispose();
    _income.dispose();
    _buffer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final private = ref.watch(privateModeProvider);
    final locked = ref.watch(appLockEnabledProvider);
    final capture = ref.watch(notificationParsingEnabledProvider);
    final themeMode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          const _SettingsHero(),
          const _SectionTitle('Appearance'),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (value) => _setTheme(value.first),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_outlined),
                title: const Text('Show amounts'),
                subtitle: const Text(
                  'Display monetary values throughout the app',
                ),
                value: !private,
                onChanged: (value) =>
                    ref.read(privateModeProvider.notifier).set(!value),
              ),
            ],
          ),
          const _SectionTitle('Privacy and security'),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline_rounded),
                title: const Text('App lock'),
                subtitle: const Text(
                  'Require device authentication when Flow opens',
                ),
                value: locked,
                onChanged: (value) =>
                    ref.read(appLockEnabledProvider.notifier).setEnabled(value),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Data and AI privacy'),
                subtitle: const Text('See exactly what leaves this device'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _showPrivacy,
              ),
            ],
          ),
          const _SectionTitle('Transaction import'),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Notification capture'),
                subtitle: Text(
                  capture
                      ? 'Automatically detect supported transaction notifications'
                      : 'Only import when you start an SMS sync',
                ),
                value: capture,
                onChanged: _toggleCapture,
              ),
              const Divider(height: 1, indent: 56),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('SMS history range'),
                          Text(
                            'Scan the last $_lookback days',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Slider(
                value: _lookback.toDouble(),
                min: 7,
                max: 180,
                divisions: 25,
                label: '$_lookback days',
                onChanged: (value) => setState(() => _lookback = value.round()),
                onChangeEnd: (_) => _saveMemory(),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: Text(_importing ? 'Importing…' : 'Import bank CSV'),
                subtitle: const Text('Add historical transactions from a file'),
                trailing: const Icon(Icons.chevron_right_rounded),
                enabled: !_importing,
                onTap: _importing ? null : _importCsv,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Import history'),
                subtitle: const Text(
                  'Review where imported transactions came from',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _push(const AuditScreen()),
              ),
            ],
          ),
          const _SectionTitle('Money preferences'),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      onChanged: (value) => setState(() => _currency = value!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _income,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Expected monthly income',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _buffer,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Protected safety buffer',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saveMoneyPreferences,
                        child: const Text('Save preferences'),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('Categories'),
                subtitle: const Text('Manage names and learned categorization'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _push(const CustomCategoriesScreen()),
              ),
            ],
          ),
          const _SectionTitle('AI connection'),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _connected
                                ? context.finance.income
                                : Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _connected
                                ? 'Ollama connected'
                                : 'Ollama connection',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _key,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'API key',
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show API key' : 'Hide API key',
                          onPressed: () => setState(() => _obscure = !_obscure),
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
                      onChanged: (value) => setState(() => _model = value!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Endpoint'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _testing ? null : _test,
                            child: Text(
                              _testing ? 'Testing…' : 'Test connection',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saveAi,
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.terminal_outlined),
                title: const Text('AI activity log'),
                subtitle: const Text('Review extraction requests and errors'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _push(const LogsScreen()),
              ),
            ],
          ),
          if (githubDevelopmentUpdatesEnabled) ...[
            const _SectionTitle('App updates'),
            const _SettingsCard(
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: DevelopmentUpdateSettingsCard(),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Flow keeps your financial records on this device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
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
    await ref.read(notificationIngestionProvider.notifier).setEnabled(value);
  }

  Future<void> _saveMoneyPreferences() async {
    await ref.read(preferredCurrencyProvider.notifier).setCurrency(_currency);
    await ref
        .read(monthlyPlanProvider.notifier)
        .setPlan(
          income: double.tryParse(_income.text.trim()) ?? 0,
          buffer: double.tryParse(_buffer.text.trim()) ?? 0,
        );
    _notify('Money preferences saved.');
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

  Future<void> _test() async {
    setState(() => _testing = true);
    final ok = await OllamaCloudService(
      apiKey: _key.text.trim(),
      baseUrl: _url.text.trim().isEmpty
          ? defaultOllamaBaseUrl
          : _url.text.trim(),
      model: _model,
    ).validateKey();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _connected = ok;
    });
    _notify(
      ok
          ? 'Ollama is connected.'
          : 'Connection failed. Check the key and endpoint.',
    );
  }

  Future<void> _importCsv() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    final path = picked?.files.firstOrNull?.path;
    if (path == null) return;
    setState(() => _importing = true);
    try {
      final expenses = await BankCsvImporter.parse(
        File(path),
        currency: _currency,
      );
      await ref.read(expenseListProvider.notifier).addExpenses(expenses);
      _notify('Imported ${expenses.length} transactions.');
    } catch (_) {
      _notify('That CSV could not be imported. Nothing changed.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
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
            Text(
              'Data and AI privacy',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Material(
        color: scheme.secondaryContainer,
        shape: ExpressiveShape.hero(),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -22,
              top: -28,
              child: CircleAvatar(
                radius: 54,
                backgroundColor: scheme.tertiaryContainer,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 92, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tune_rounded, color: scheme.onSecondaryContainer),
                  const SizedBox(height: 28),
                  Text(
                    'Make Flow yours',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your appearance, privacy, imports and AI connection — all in one place.',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    shape: ExpressiveShape.soft(),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
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
