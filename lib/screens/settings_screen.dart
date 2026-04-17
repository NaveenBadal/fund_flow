import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/ai_provider.dart';
import '../models/flutter_gemma_model_info.dart';
import '../providers/expense_provider.dart';
import '../services/categorization_service.dart';
import '../services/flutter_gemma_service.dart';
import '../services/gemini_model_catalog_service.dart';
import '../services/offline_model_service.dart';
import 'audit_screen.dart';
import 'logs_screen.dart';
import 'custom_categories_screen.dart';
import 'year_in_review_screen.dart';
import '../services/pdf_service.dart';
import '../services/bank_csv_importer.dart';
import '../services/drive_backup_service.dart';
import '../services/notification_service.dart';
import 'package:printing/printing.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with WidgetsBindingObserver {
  late TextEditingController _keyController;
  late TextEditingController _modelController;
  late int _lookbackDays;
  late ThemeMode _themeMode;
  late AiProviderType _selectedProvider;
  late int _onDeviceMaxTokens;
  bool _allFilesGranted = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllFilesPermission();
    _selectedProvider = ref.read(selectedAiProviderProvider);
    final apiKeys = ref.read(providerApiKeysProvider);
    final models = ref.read(providerModelsProvider);

    _keyController = TextEditingController(text: apiKeys[_selectedProvider] ?? '');
    _modelController = TextEditingController(
      text: models[_selectedProvider] ?? defaultModelFor(_selectedProvider),
    );
    _lookbackDays = ref.read(syncLookbackProvider);
    _themeMode = ref.read(themeModeProvider);
    _onDeviceMaxTokens = ref.read(onDeviceMaxTokensProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after user returns from system All Files Access settings
    if (state == AppLifecycleState.resumed) {
      _checkAllFilesPermission();
    }
  }

  Future<void> _checkAllFilesPermission() async {
    final granted = await Permission.manageExternalStorage.isGranted;
    if (mounted && granted != _allFilesGranted) {
      setState(() => _allFilesGranted = granted);
      if (granted) {
        // Refresh model lists now that permission is available
        ref.invalidate(availableOfflineModelsProvider);
        ref.invalidate(availableFlutterGemmaModelsProvider);
      }
    }
  }

  Future<void> _requestAllFilesPermission() async {
    await Permission.manageExternalStorage.request();
    // didChangeAppLifecycleState handles the re-check on return
  }

  Future<void> _importModelFile() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      withReadStream: true, // stream avoids loading 2GB+ into RAM
    );
    if (result == null || result.files.isEmpty) return;

    final pf = result.files.first;
    setState(() => _importing = true);

    try {
      final destDir = await FlutterGemmaService.modelsDir();
      final dest = File('${destDir.path}/${pf.name}');

      if (pf.path != null && await File(pf.path!).exists()) {
        await File(pf.path!).copy(dest.path);
      } else if (pf.readStream != null) {
        final sink = dest.openWrite();
        await pf.readStream!.pipe(sink);
        await sink.flush();
        await sink.close();
      } else {
        throw Exception('Could not read selected file.');
      }

      if (mounted) {
        setState(() {
          _importing = false;
          // LiteRT uses filename; flutter_gemma uses full path
          _modelController.text = _selectedProvider == AiProviderType.flutterGemma
              ? dest.path
              : pf.name;
        });
        ref.invalidate(availableOfflineModelsProvider);
        ref.invalidate(availableFlutterGemmaModelsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${pf.name} successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  void _switchProvider(AiProviderType provider) {
    if (_selectedProvider == provider) return;

    final apiKeys = ref.read(providerApiKeysProvider);
    final models = ref.read(providerModelsProvider);

    setState(() {
      _selectedProvider = provider;
      _keyController.text = apiKeys[provider] ?? '';
      _modelController.text = models[provider] ?? defaultModelFor(provider);
    });
  }

  Future<void> _applyThemeMode(ThemeMode mode) async {
    setState(() {
      _themeMode = mode;
    });
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
    await ref.read(secureStorageProvider).write(
      key: 'theme_mode',
      value: mode.toString(),
    );
  }

  Future<void> _saveConfiguration() async {
    final key = _keyController.text.trim();
    final model = _modelController.text.trim();
    final requiresApiKey = _selectedProvider != AiProviderType.offline &&
        _selectedProvider != AiProviderType.flutterGemma;

    if (requiresApiKey && key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a valid ${_selectedProvider.displayName} API key')),
      );
      return;
    }
    if (model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedProvider == AiProviderType.flutterGemma
                ? 'Please select a model from the list.'
                : 'Please enter a valid ${_selectedProvider.displayName} model name',
          ),
        ),
      );
      return;
    }

    final storage = ref.read(secureStorageProvider);
    if (requiresApiKey) {
      await storage.write(key: _selectedProvider.apiKeyStorageKey, value: key);
    }
    await storage.write(key: _selectedProvider.modelStorageKey, value: model);
    await storage.write(key: selectedAiProviderStorageKey, value: _selectedProvider.id);
    await storage.write(key: 'sync_lookback_days', value: _lookbackDays.toString());
    await storage.write(key: 'theme_mode', value: _themeMode.toString());
    await storage.write(key: onDeviceMaxTokensStorageKey, value: _onDeviceMaxTokens.toString());

    // Keep legacy Gemini keys populated for backward compatibility.
    if (_selectedProvider == AiProviderType.gemini) {
      await storage.write(key: 'gemini_api_key', value: key);
      await storage.write(key: 'gemini_model', value: model);
    }

    if (requiresApiKey) {
      ref.read(providerApiKeysProvider.notifier).setKey(_selectedProvider, key);
    }
    ref.read(providerModelsProvider.notifier).setModel(_selectedProvider, model);
    ref.read(selectedAiProviderProvider.notifier).setProvider(_selectedProvider);
    ref.read(syncLookbackProvider.notifier).setDays(_lookbackDays);
    ref.read(themeModeProvider.notifier).setThemeMode(_themeMode);
    ref.read(onDeviceMaxTokensProvider.notifier).setTokens(_onDeviceMaxTokens);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved. Sync will now use ${_selectedProvider.displayName} / "$model".')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _importBankCsv() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    setState(() => _importing = true);

    try {
      final expenses = await BankCsvImporter.parse(file);
      if (expenses.isEmpty) {
        throw Exception('No transactions found in CSV.');
      }
      setState(() => _importing = false);
      if (!mounted) return;

      // Show preview sheet before committing
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (_) => _CsvPreviewSheet(expenses: expenses),
      );

      if (confirmed == true && mounted) {
        setState(() => _importing = true);
        for (final e in expenses) {
          await ref.read(expenseListProvider.notifier).addExpense(e);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported ${expenses.length} transactions.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _generatePdfReport() async {
    final expenses = await ref.read(expenseListProvider.future);
    if (!mounted) return;
    if (expenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No transactions to export.')),
      );
      return;
    }

    final now = DateTime.now();
    final budgetProg = await ref.read(budgetProgressProvider.future);
    if (!mounted) return;
    final pdfFile = await PdfService.generateMonthlyStatement(
      year: now.year,
      month: now.month,
      expenses: expenses,
      budgetProgress: budgetProg,
    );
    await Printing.sharePdf(bytes: await pdfFile.readAsBytes(), filename: 'monthly_statement.pdf');
  }

  Future<void> _driveBackup() async {
    final drive = DriveBackupService.instance;
    final account = await drive.signIn();
    if (account == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google Sign-In failed.')),
        );
      }
      return;
    }
    
    final result = await drive.backup();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result ? 'Backup successful.' : 'Backup failed.')),
      );
    }
  }

  Future<void> _driveRestore() async {
    final drive = DriveBackupService.instance;
    final account = await drive.signIn();
    if (!mounted) return;
    if (account == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Drive?'),
        content: const Text('Current local data will be overwritten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await drive.restore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result ? 'Restore successful. Restart app.' : 'Restore failed.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    
    final appLockEnabled = ref.watch(appLockEnabledProvider);
    final privateMode = ref.watch(privateModeProvider);
    final dailyDigestEnabled = ref.watch(dailyDigestEnabledProvider);
    final notifParsingEnabled = ref.watch(notificationParsingEnabledProvider);

    final currentKey = _keyController.text.trim();
    final currentModel = _modelController.text.trim();
    final availableModelsAsync = _selectedProvider == AiProviderType.gemini
        ? ref.watch(availableGeminiModelsProvider(currentKey))
        : const AsyncValue<List<GeminiModelCatalogItem>>.data([]);
    final availableOfflineModelsAsync = _selectedProvider == AiProviderType.offline
        ? ref.watch(availableOfflineModelsProvider)
        : const AsyncValue<List<OfflineModelInfo>>.data([]);
    final availableFlutterGemmaModelsAsync = _selectedProvider == AiProviderType.flutterGemma
        ? ref.watch(availableFlutterGemmaModelsProvider)
        : const AsyncValue<List<FlutterGemmaModelInfo>>.data([]);
    final remoteModels = availableModelsAsync.asData?.value ?? const <GeminiModelCatalogItem>[];
    final selectedRemoteModel = remoteModels.cast<GeminiModelCatalogItem?>().firstWhere(
          (model) => model?.name == currentModel,
          orElse: () => null,
        );
    final offlineModels = availableOfflineModelsAsync.asData?.value ?? const <OfflineModelInfo>[];
    final selectedOfflineModel = offlineModels.cast<OfflineModelInfo?>().firstWhere(
          (model) => model?.name == currentModel,
          orElse: () => null,
        );
    final flutterGemmaModels = availableFlutterGemmaModelsAsync.asData?.value ?? const <FlutterGemmaModelInfo>[];
    final selectedFlutterGemmaModel = flutterGemmaModels.cast<FlutterGemmaModelInfo?>().firstWhere(
          (model) => model?.path == currentModel,
          orElse: () => null,
        );
    final staticModels = staticModelsFor(_selectedProvider);
    final selectedStaticModel = staticModels.cast<StaticModelOption?>().firstWhere(
          (model) => model?.id == currentModel,
          orElse: () => null,
        );
    final displayModel = currentModel.isEmpty
        ? defaultModelFor(_selectedProvider)
        : (_selectedProvider == AiProviderType.flutterGemma
            ? currentModel.split('/').last
            : currentModel);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _HeroSettingsCard(
            title: 'AI-powered SMS expense tracking',
            subtitle: 'Switch providers, keep separate API keys, and tune sync depth before each scan.',
            icon: Icons.auto_awesome_rounded,
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'AI provider',
            subtitle: 'Each provider keeps its own API key and model. Switching back restores saved values.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: AiProviderType.values.map((provider) {
                    final selected = _selectedProvider == provider;
                    return ChoiceChip(
                      selected: selected,
                      label: Text(provider.displayName),
                      avatar: Icon(_providerIcon(provider), size: 18),
                      onSelected: (_) => _switchProvider(provider),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_clock_outlined, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          (_selectedProvider == AiProviderType.offline || _selectedProvider == AiProviderType.flutterGemma)
                              ? 'On-device provider — no API key required. Model runs entirely on device.'
                              : 'Saved ${_selectedProvider.displayName} credentials stay separate from other providers.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: _selectedProvider.displayName,
            subtitle: _providerSubtitle(_selectedProvider),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedProvider != AiProviderType.offline &&
                    _selectedProvider != AiProviderType.flutterGemma) ...[
                  TextField(
                    controller: _keyController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: '${_selectedProvider.displayName} API key',
                      hintText: 'Enter your API key here',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 20),
                ],
                if (_selectedProvider == AiProviderType.gemini) ...[
                  Text(
                    'Available models',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  availableModelsAsync.when(
                    data: (models) => _ModelDropdown(
                      title: 'Gemini model catalog',
                      subtitle: 'Choose model from live Gemini catalog.',
                      selectedModel: currentModel,
                      models: models,
                      onSelected: (value) {
                        if (value == null || value.isEmpty) return;
                        setState(() {
                          _modelController.text = value;
                        });
                      },
                      onRefresh: () => ref.invalidate(availableGeminiModelsProvider(currentKey)),
                    ),
                    loading: () => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Expanded(child: Text('Loading Gemini models from ListModels...')),
                        ],
                      ),
                    ),
                    error: (error, _) => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_outlined, color: scheme.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              currentKey.isEmpty
                                  ? 'Enter Gemini API key to fetch models.'
                                  : 'Could not fetch Gemini model catalog. Manual entry still works.',
                            ),
                          ),
                          IconButton(
                            tooltip: 'Retry',
                            onPressed: currentKey.isEmpty
                                ? null
                                : () => ref.invalidate(availableGeminiModelsProvider(currentKey)),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else if (_selectedProvider == AiProviderType.sarvam) ...[
                  Text(
                    'Supported models',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _StaticModelList(
                    selectedModel: currentModel,
                    models: staticModels,
                    onSelected: (value) {
                      setState(() {
                        _modelController.text = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                ] else if (_selectedProvider == AiProviderType.flutterGemma) ...[
                  Text(
                    'Edge models on device',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  if (!_allFilesGranted) ...[
                    _AllFilesPermissionBanner(onRequest: _requestAllFilesPermission),
                    const SizedBox(height: 12),
                  ],
                  availableFlutterGemmaModelsAsync.when(
                    data: (models) => _FlutterGemmaModelList(
                      selectedPath: currentModel,
                      models: models,
                      onSelected: (path) {
                        setState(() {
                          _modelController.text = path;
                        });
                      },
                      onRefresh: () => ref.invalidate(availableFlutterGemmaModelsProvider),
                      onImport: _importing ? null : _importModelFile,
                    ),
                    loading: () => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Expanded(child: Text('Scanning device for Edge models...')),
                        ],
                      ),
                    ),
                    error: (error, _) => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.memory_outlined, color: scheme.error),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Could not scan device for Edge models.')),
                          IconButton(
                            tooltip: 'Retry',
                            onPressed: () => ref.invalidate(availableFlutterGemmaModelsProvider),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Text(
                    'LiteRT models on device',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  if (!_allFilesGranted) ...[
                    _AllFilesPermissionBanner(onRequest: _requestAllFilesPermission),
                    const SizedBox(height: 12),
                  ],
                  availableOfflineModelsAsync.when(
                    data: (models) => _OfflineModelList(
                      selectedModel: currentModel,
                      models: models,
                      onSelected: (value) {
                        setState(() {
                          _modelController.text = value;
                        });
                      },
                      onRefresh: () => ref.invalidate(availableOfflineModelsProvider),
                      onImport: _importing ? null : _importModelFile,
                    ),
                    loading: () => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Expanded(child: Text('Scanning device for `.litertlm` models...')),
                        ],
                      ),
                    ),
                    error: (error, _) => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.memory_outlined, color: scheme.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Could not read offline models from device storage.'),
                          ),
                          IconButton(
                            tooltip: 'Retry',
                            onPressed: () => ref.invalidate(availableOfflineModelsProvider),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_selectedProvider != AiProviderType.offline &&
                    _selectedProvider != AiProviderType.flutterGemma)
                  TextField(
                    controller: _modelController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: '${_selectedProvider.displayName} model name',
                      hintText: defaultModelFor(_selectedProvider),
                      helperText: _providerModelHelper(_selectedProvider),
                      prefixIcon: const Icon(Icons.tune_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Reset to default',
                        onPressed: () {
                          setState(() {
                            _modelController.text = defaultModelFor(_selectedProvider);
                          });
                        },
                        icon: const Icon(Icons.restart_alt_rounded),
                      ),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (selectedRemoteModel != null)
                  _SelectedGeminiModelCard(model: selectedRemoteModel),
                if (selectedStaticModel != null)
                  _SelectedStaticModelCard(
                    provider: _selectedProvider,
                    model: selectedStaticModel,
                  ),
                if (selectedOfflineModel != null)
                  _SelectedOfflineModelCard(model: selectedOfflineModel),
                if (selectedFlutterGemmaModel != null)
                  _SelectedFlutterGemmaModelCard(model: selectedFlutterGemmaModel),
                if (selectedRemoteModel != null || selectedStaticModel != null ||
                    selectedOfflineModel != null || selectedFlutterGemmaModel != null)
                  const SizedBox(height: 12),
                if (_selectedProvider == AiProviderType.offline ||
                    _selectedProvider == AiProviderType.flutterGemma) ...[
                  Text(
                    'Context window (tokens)',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [512, 1024, 2048, 4096, 8192].map((tokens) {
                      final selected = _onDeviceMaxTokens == tokens;
                      return ChoiceChip(
                        selected: selected,
                        label: Text('$tokens'),
                        avatar: Icon(
                          selected ? Icons.check_circle : Icons.token_outlined,
                          size: 18,
                        ),
                        onSelected: (_) => setState(() => _onDeviceMaxTokens = tokens),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sets the max context window for on-device inference. Higher = more SMS per chunk but more RAM.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.science_outlined, color: scheme.secondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Current runtime: ${_selectedProvider.displayName} / ${displayModel.isEmpty ? '(none selected)' : displayModel}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _providerFooter(_selectedProvider),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Security & Privacy',
            subtitle: 'Protect your financial data with biometrics and UI blurs.',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('App Lock'),
                  subtitle: const Text('Require Biometric/PIN on startup'),
                  value: appLockEnabled,
                  onChanged: (val) => ref.read(appLockEnabledProvider.notifier).toggle(),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Private Mode'),
                  subtitle: const Text('Blur amounts on dashboard'),
                  value: privateMode,
                  onChanged: (val) => ref.read(privateModeProvider.notifier).toggle(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Data & Backup',
            subtitle: 'Manage categories, import history, and cloud sync.',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(Icons.category_rounded, color: scheme.primary),
                  ),
                  title: const Text('Custom Categories'),
                  subtitle: const Text('Create icons and colors for your needs'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CustomCategoriesScreen()),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: scheme.secondaryContainer,
                    child: Icon(Icons.upload_file_rounded, color: scheme.secondary),
                  ),
                  title: const Text('Import Bank CSV'),
                  subtitle: const Text('Support for HDFC, ICICI, Axis, SBI, Kotak'),
                  onTap: _importing ? null : _importBankCsv,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: scheme.tertiaryContainer,
                    child: Icon(Icons.picture_as_pdf_rounded, color: scheme.tertiary),
                  ),
                  title: const Text('Monthly PDF Statement'),
                  subtitle: const Text('Generate shareable summary report'),
                  onTap: _generatePdfReport,
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _driveBackup,
                        icon: const Icon(Icons.cloud_upload_rounded),
                        label: const Text('Backup'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _driveRestore,
                        icon: const Icon(Icons.cloud_download_rounded),
                        label: const Text('Restore'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Uses Google Drive to sync your encrypted database.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Insights & Notifications',
            subtitle: 'Automated summaries and yearly recaps.',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Daily Digest'),
                  subtitle: const Text('Summary notification at 8 PM'),
                  value: dailyDigestEnabled,
                  onChanged: (val) {
                    ref.read(dailyDigestEnabledProvider.notifier).toggle();
                    if (val) {
                      NotificationService.instance.scheduleDailyDigest();
                    } else {
                      NotificationService.instance.cancelDailyDigest();
                    }
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Notification Parsing'),
                  subtitle: const Text('Parse bank push notifications for transactions'),
                  value: notifParsingEnabled,
                  onChanged: (_) =>
                      ref.read(notificationParsingEnabledProvider.notifier).toggle(),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: scheme.surfaceContainerHighest,
                    child: Icon(Icons.auto_graph_rounded, color: scheme.onSurfaceVariant),
                  ),
                  title: const Text('Year in Review'),
                  subtitle: const Text('Shareable visual spending story'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => YearInReviewScreen(year: DateTime.now().year),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Appearance',
            subtitle: 'Bolder Material 3 controls fit this app better than plain dropdown rows.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theme mode',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {_themeMode},
                  onSelectionChanged: (selection) {
                    _applyThemeMode(selection.first);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Sync window',
            subtitle: 'Use presets to control scan cost and AI workload.',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [1, 2, 3, 7, 14, 30].map((value) {
                final selected = _lookbackDays == value;
                return ChoiceChip(
                  selected: selected,
                  label: Text('$value day${value == 1 ? '' : 's'}'),
                  avatar: Icon(
                    selected ? Icons.check_circle : Icons.calendar_month_outlined,
                    size: 18,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _lookbackDays = value;
                    });
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Developer',
            subtitle: 'Inspect prompts, responses, and parsed SMS history.',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: scheme.tertiaryContainer,
                    child: Icon(Icons.bug_report_outlined, color: scheme.tertiary),
                  ),
                  title: const Text('View AI request logs'),
                  subtitle: const Text('Raw prompts, model output, and error states'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LogsScreen()),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: scheme.secondaryContainer,
                    child: Icon(Icons.sms_outlined, color: scheme.secondary),
                  ),
                  title: const Text('Parsed SMS audit'),
                  subtitle: const Text('All SMS sent to AI — with or without resulting transactions'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AuditScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _saveConfiguration,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save configuration'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
        ],
      ),
    );
  }

  String _providerSubtitle(AiProviderType provider) {
    return switch (provider) {
      AiProviderType.gemini =>
        'API access and runtime model selection. Preview model calls use API version $defaultGeminiApiVersion.',
      AiProviderType.sarvam =>
        'OpenAI-style chat completions with separate Sarvam credentials and preset 30B / 105B models.',
      AiProviderType.offline =>
        'On-device `.litertlm` models via LiteRT-LM. Scans Downloads and AI Edge Gallery. No API key.',
      AiProviderType.flutterGemma =>
        'Google AI Edge models (Gemma 4, Qwen, DeepSeek, etc.) via flutter_gemma. No API key required.',
    };
  }

  String _providerModelHelper(AiProviderType provider) {
    return switch (provider) {
      AiProviderType.gemini => 'Search Gemini catalog or type any model ID manually. Next sync uses this value.',
      AiProviderType.sarvam => 'Choose Sarvam 30B or 105B, or type another future Sarvam model ID manually.',
      AiProviderType.offline => 'Select one discovered model below. The model file must already exist on device.',
      AiProviderType.flutterGemma => 'Select a model discovered from AI Edge Gallery or Downloads.',
    };
  }

  String _providerFooter(AiProviderType provider) {
    return switch (provider) {
      AiProviderType.gemini =>
        'Remote catalog uses Gemini `models.list` on `$defaultGeminiApiVersion`. Requests also use `$defaultGeminiApiVersion` explicitly.',
      AiProviderType.sarvam =>
        'Sarvam requests use `POST /v1/chat/completions` with provider-specific API key storage.',
      AiProviderType.offline =>
        'LiteRT-LM on Android. Scans MediaStore and AI Edge Gallery paths for `.litertlm` files. Grant "All files access" to see Gallery models.',
      AiProviderType.flutterGemma =>
        'flutter_gemma wraps MediaPipe LLM Inference. Scans AI Edge Gallery and Downloads for `.task`, `.bin`, `.gguf` models. Grant "All files access" for full Gallery access.',
    };
  }

  IconData _providerIcon(AiProviderType provider) {
    return switch (provider) {
      AiProviderType.gemini => Icons.cloud_outlined,
      AiProviderType.sarvam => Icons.language_outlined,
      AiProviderType.offline => Icons.memory_outlined,
      AiProviderType.flutterGemma => Icons.device_hub_outlined,
    };
  }
}

class _HeroSettingsCard extends StatelessWidget {
  const _HeroSettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer,
            scheme.tertiaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.surface.withValues(alpha: 0.75),
            child: Icon(icon, color: scheme.primary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _ModelDropdown extends StatelessWidget {
  const _ModelDropdown({
    required this.title,
    required this.subtitle,
    required this.selectedModel,
    required this.models,
    required this.onSelected,
    required this.onRefresh,
  });

  final String title;
  final String subtitle;
  final String selectedModel;
  final List<GeminiModelCatalogItem> models;
  final ValueChanged<String?> onSelected;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: models.isEmpty ? null : () => _showModelSheet(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.surface.withValues(alpha: 0.75),
                  child: Icon(Icons.model_training_outlined, color: scheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedModel.isEmpty ? subtitle : selectedModel,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to open searchable bottom sheet.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Refresh model catalog',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    const SizedBox(height: 8),
                    Icon(Icons.keyboard_arrow_up_rounded, color: scheme.primary),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          models.isEmpty
              ? 'No `generateContent` models returned.'
              : '${models.length} generateContent models available from Gemini.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _showModelSheet(BuildContext context) async {
    final searchController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final query = searchController.text.trim().toLowerCase();
            final filtered = models.where((model) {
              if (query.isEmpty) return true;
              return model.name.toLowerCase().contains(query) ||
                  model.displayName.toLowerCase().contains(query) ||
                  model.description.toLowerCase().contains(query);
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 8,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.82,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Choose Gemini model',
                                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${filtered.length} of ${models.length} models from Gemini `ListModels`',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Refresh model catalog',
                            onPressed: () {
                              Navigator.pop(context);
                              onRefresh();
                            },
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: searchController,
                        onChanged: (_) => setModalState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search model id, display name, or description',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No models match search.',
                                  style: theme.textTheme.bodyLarge,
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final model = filtered[index];
                                  final selected = model.name == selectedModel;
                                  return _GeminiModelSheetTile(
                                    model: model,
                                    selected: selected,
                                    onTap: () {
                                      onSelected(model.name);
                                      Navigator.pop(context);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
  }
}

class _StaticModelList extends StatelessWidget {
  const _StaticModelList({
    required this.selectedModel,
    required this.models,
    required this.onSelected,
  });

  final String selectedModel;
  final List<StaticModelOption> models;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: models
          .map(
            (model) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _StaticModelTile(
                model: model,
                selected: model.id == selectedModel,
                onTap: () => onSelected(model.id),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _OfflineModelList extends StatelessWidget {
  const _OfflineModelList({
    required this.selectedModel,
    required this.models,
    required this.onSelected,
    required this.onRefresh,
    required this.onImport,
  });

  final String selectedModel;
  final List<OfflineModelInfo> models;
  final ValueChanged<String> onSelected;
  final VoidCallback onRefresh;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (models.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_open_outlined),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('No `.litertlm` models found. Import a model file or place one in Downloads and refresh.'),
            ),
            IconButton(
              tooltip: 'Import model file',
              onPressed: onImport,
              icon: const Icon(Icons.file_open_outlined),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...models.map(
          (model) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OfflineModelTile(
              model: model,
              selected: model.name == selectedModel,
              onTap: () => onSelected(model.name),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import'),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectedGeminiModelCard extends StatelessWidget {
  const _SelectedGeminiModelCard({required this.model});

  final GeminiModelCatalogItem model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.displayName,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (model.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(model.description),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (model.inputTokenLimit != null)
                _InfoChip(
                  icon: Icons.input_rounded,
                  label: 'Input ${model.inputTokenLimit}',
                ),
              if (model.outputTokenLimit != null)
                _InfoChip(
                  icon: Icons.output_rounded,
                  label: 'Output ${model.outputTokenLimit}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectedStaticModelCard extends StatelessWidget {
  const _SelectedStaticModelCard({
    required this.provider,
    required this.model,
  });

  final AiProviderType provider;
  final StaticModelOption model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.displayName,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(model.description),
          const SizedBox(height: 8),
          _InfoChip(
            icon: Icons.hub_outlined,
            label: '${provider.displayName} preset',
          ),
        ],
      ),
    );
  }
}

class _SelectedOfflineModelCard extends StatelessWidget {
  const _SelectedOfflineModelCard({required this.model});

  final OfflineModelInfo model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.name,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.sd_storage_outlined,
                label: _formatBytes(model.sizeBytes),
              ),
              _InfoChip(
                icon: Icons.schedule_outlined,
                label: _formatTimestamp(model.modifiedAtMillis),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _OfflineModelTile extends StatelessWidget {
  const _OfflineModelTile({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final OfflineModelInfo model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: selected
          ? scheme.tertiaryContainer.withValues(alpha: 0.72)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.36),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: selected
                    ? scheme.primary.withValues(alpha: 0.14)
                    : scheme.surface,
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.memory_outlined,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          icon: Icons.sd_storage_outlined,
                          label: _formatBytes(model.sizeBytes),
                        ),
                        _InfoChip(
                          icon: Icons.schedule_outlined,
                          label: _formatTimestamp(model.modifiedAtMillis),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeminiModelSheetTile extends StatelessWidget {
  const _GeminiModelSheetTile({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final GeminiModelCatalogItem model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: selected
          ? scheme.tertiaryContainer.withValues(alpha: 0.72)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.36),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: selected
                    ? scheme.primary.withValues(alpha: 0.14)
                    : scheme.surface,
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.auto_awesome_outlined,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      model.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (model.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        model.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (model.inputTokenLimit != null)
                          _InfoChip(
                            icon: Icons.input_rounded,
                            label: 'In ${model.inputTokenLimit}',
                          ),
                        if (model.outputTokenLimit != null)
                          _InfoChip(
                            icon: Icons.output_rounded,
                            label: 'Out ${model.outputTokenLimit}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaticModelTile extends StatelessWidget {
  const _StaticModelTile({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final StaticModelOption model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: selected
          ? scheme.tertiaryContainer.withValues(alpha: 0.72)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.36),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: selected
                    ? scheme.primary.withValues(alpha: 0.14)
                    : scheme.surface,
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.memory_outlined,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.id,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      model.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      model.description,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllFilesPermissionBanner extends StatelessWidget {
  const _AllFilesPermissionBanner({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_special_outlined, color: scheme.tertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '"All files access" not granted. Required to scan AI Edge Gallery and Downloads for models.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: onRequest,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            child: const Text('Grant'),
          ),
        ],
      ),
    );
  }
}

class _FlutterGemmaModelList extends StatelessWidget {
  const _FlutterGemmaModelList({
    required this.selectedPath,
    required this.models,
    required this.onSelected,
    required this.onRefresh,
    required this.onImport,
  });

  final String selectedPath;
  final List<FlutterGemmaModelInfo> models;
  final ValueChanged<String> onSelected;
  final VoidCallback onRefresh;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (models.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_open_outlined),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No Edge models found. Import a model file from AI Edge Gallery, or grant "All files access" and refresh.',
              ),
            ),
            IconButton(
              tooltip: 'Import model file',
              onPressed: onImport,
              icon: const Icon(Icons.file_open_outlined),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...models.map(
          (model) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FlutterGemmaModelTile(
              model: model,
              selected: model.path == selectedPath,
              onTap: () => onSelected(model.path),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import'),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FlutterGemmaModelTile extends StatelessWidget {
  const _FlutterGemmaModelTile({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final FlutterGemmaModelInfo model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: selected
          ? scheme.tertiaryContainer.withValues(alpha: 0.72)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.36),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: selected
                    ? scheme.primary.withValues(alpha: 0.14)
                    : scheme.surface,
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.device_hub_outlined,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      model.path,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          icon: Icons.sd_storage_outlined,
                          label: _formatBytes(model.sizeBytes),
                        ),
                        _InfoChip(
                          icon: Icons.schedule_outlined,
                          label: _formatTimestamp(model.modifiedAtMillis),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedFlutterGemmaModelCard extends StatelessWidget {
  const _SelectedFlutterGemmaModelCard({required this.model});

  final FlutterGemmaModelInfo model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.name,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(model.path, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(icon: Icons.sd_storage_outlined, label: _formatBytes(model.sizeBytes)),
              _InfoChip(icon: Icons.device_hub_outlined, label: 'Edge / MediaPipe'),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return 'Unknown size';
  const units = ['B', 'KB', 'MB', 'GB'];
  double value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return '${value.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
}

String _formatTimestamp(int millis) {
  if (millis <= 0) return 'Unknown time';
  return DateTime.fromMillisecondsSinceEpoch(millis).toLocal().toString().split('.').first;
}

// ─── CSV Import Preview Sheet ─────────────────────────────────────────────

class _CsvPreviewSheet extends StatelessWidget {
  const _CsvPreviewSheet({required this.expenses});

  final List expenses; // List<Expense> but avoid import cycle with dynamic

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Preview Import',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${expenses.length} transactions',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Review before importing. All will be saved.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: expenses.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final e = expenses[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.merchant as String? ?? '',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                e.category as String? ?? '',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${e.currency} ${(e.amount as double).toStringAsFixed(2)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Import All'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
