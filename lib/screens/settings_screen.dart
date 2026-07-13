import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_provider.dart';
import '../providers/expense_provider.dart';
import '../services/bank_csv_importer.dart';
import '../services/ollama_cloud_service.dart';
import '../theme/app_tokens.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Settings'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverList.list(
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: scheme.inverseSurface,
                    borderRadius: AppRadius.all(AppRadius.xxl),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: AppRadius.all(16),
                        ),
                        child: Icon(
                          Icons.bolt_rounded,
                          color: scheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ollama connection',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: scheme.onInverseSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _connected
                                  ? 'Connected and ready'
                                  : 'Private cloud parsing',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: scheme.onInverseSurface.withValues(
                                      alpha: .65,
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _connected
                            ? Icons.check_circle_rounded
                            : Icons.cloud_outlined,
                        color: _connected
                            ? const Color(0xFFB9F227)
                            : scheme.onInverseSurface,
                      ),
                    ],
                  ),
                ),
                const _SettingsLabel('APPEARANCE'),
                _SettingsSurface(
                  child: Column(
                    children: [
                      SegmentedButton<ThemeMode>(
                        expandedInsets: EdgeInsets.zero,
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {mode},
                        onSelectionChanged: (value) => _setTheme(value.first),
                      ),
                    ],
                  ),
                ),
                const _SettingsLabel('PRIVACY'),
                _SettingsSurface(
                  child: Column(
                    children: [
                      _SwitchRow(
                        icon: Icons.lock_outline_rounded,
                        title: 'App lock',
                        caption: 'Require device authentication',
                        value: ref.watch(appLockEnabledProvider),
                        onChanged: (_) =>
                            ref.read(appLockEnabledProvider.notifier).toggle(),
                      ),
                      const Divider(height: 1, indent: 52),
                      _SwitchRow(
                        icon: Icons.visibility_off_outlined,
                        title: 'Hide amounts',
                        caption: 'Mask money across the app',
                        value: ref.watch(privateModeProvider),
                        onChanged: (value) =>
                            ref.read(privateModeProvider.notifier).set(value),
                      ),
                    ],
                  ),
                ),
                const _SettingsLabel('AI ENGINE'),
                _SettingsSurface(
                  child: Column(
                    children: [
                      TextField(
                        controller: _key,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'API key',
                          prefixIcon: const Icon(Icons.key_rounded),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _model,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          prefixIcon: Icon(Icons.memory_rounded),
                        ),
                        items: [
                          for (final model in ollamaModelChoices)
                            DropdownMenuItem(value: model, child: Text(model)),
                        ],
                        onChanged: (value) => setState(() => _model = value!),
                      ),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Advanced connection'),
                        children: [
                          TextField(
                            controller: _url,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Server URL',
                              prefixIcon: Icon(Icons.dns_outlined),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _testing ? null : _test,
                          icon: _testing
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.wifi_tethering_rounded),
                          label: Text(
                            _testing ? 'Testing…' : 'Test connection',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const _SettingsLabel('IMPORT WINDOW'),
                _SettingsSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan the last $_lookback days',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Slider(
                        value: _lookback.toDouble(),
                        min: 7,
                        max: 180,
                        divisions: 25,
                        label: '$_lookback days',
                        onChanged: (value) =>
                            setState(() => _lookback = value.round()),
                      ),
                    ],
                  ),
                ),
                const _SettingsLabel('ORGANIZE'),
                _SettingsSurface(
                  child: Column(
                    children: [
                      _LinkRow(
                        icon: Icons.category_outlined,
                        title: 'Category library',
                        caption: 'Names, colors, and icons',
                        onTap: () => _push(const CustomCategoriesScreen()),
                      ),
                      const Divider(height: 1, indent: 52),
                      _LinkRow(
                        icon: Icons.sms_outlined,
                        title: 'SMS inbox',
                        caption: 'Review parsed and skipped messages',
                        onTap: () => _push(const AuditScreen()),
                      ),
                    ],
                  ),
                ),
                const _SettingsLabel('DATA'),
                _SettingsSurface(
                  child: Column(
                    children: [
                      _LinkRow(
                        icon: Icons.upload_file_rounded,
                        title: 'Import bank CSV',
                        caption: _importing
                            ? 'Importing…'
                            : 'Bring transaction history',
                        onTap: _importing ? null : _importCsv,
                      ),
                      const Divider(height: 1, indent: 52),
                      _LinkRow(
                        icon: Icons.terminal_rounded,
                        title: 'Diagnostics',
                        caption: 'Cloud parsing activity',
                        onTap: () => _push(const LogsScreen()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Fund Flow · Local-first finance',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setTheme(ThemeMode mode) async {
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
    await ref
        .read(secureStorageProvider)
        .write(key: 'theme_mode', value: mode.toString());
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Connection verified.'
              : 'Could not connect. Check the key and URL.',
        ),
      ),
    );
  }

  Future<void> _save() async {
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
      ref
          .read(secureStorageProvider)
          .write(key: 'sync_lookback_days', value: '$_lookback'),
    ]);
    ref.read(ollamaApiKeyProvider.notifier).set(_key.text.trim());
    ref.read(ollamaBaseUrlProvider.notifier).set(url);
    ref.read(ollamaModelProvider.notifier).set(_model);
    ref.read(syncLookbackProvider.notifier).setDays(_lookback);
    if (mounted) Navigator.pop(context);
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
      final expenses = await BankCsvImporter.parse(File(path));
      if (expenses.isNotEmpty) {
        await ref.read(expenseListProvider.notifier).addExpenses(expenses);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${expenses.length} transactions.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 28, 4, 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.3,
      ),
    ),
  );
}

class _SettingsSurface extends StatelessWidget {
  const _SettingsSurface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: AppRadius.all(AppRadius.lg),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .45),
      ),
    ),
    child: child,
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.caption,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String caption;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    secondary: Icon(icon),
    title: Text(title),
    subtitle: Text(caption),
    value: value,
    onChanged: onChanged,
  );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(caption),
    trailing: const Icon(Icons.arrow_forward_rounded, size: 19),
    onTap: onTap,
  );
}
