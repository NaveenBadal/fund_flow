import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_controller.dart';
import '../app/app_state.dart';
import '../domain/ai_provider.dart';
import '../intelligence/model_catalog.dart';
import 'zero_theme.dart';

Future<void> showZeroIntelligence(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ZeroIntelligenceSheet(),
    );

class ZeroIntelligenceSheet extends ConsumerStatefulWidget {
  const ZeroIntelligenceSheet({super.key});

  @override
  ConsumerState<ZeroIntelligenceSheet> createState() =>
      _ZeroIntelligenceSheetState();
}

class _ZeroIntelligenceSheetState extends ConsumerState<ZeroIntelligenceSheet> {
  late AiProvider provider;
  final key = TextEditingController();
  final endpoint = TextEditingController();
  final parsing = TextEditingController();
  final chat = TextEditingController();
  List<String> models = const [];
  bool keyVisible = false;
  bool advanced = false;
  bool fetching = false;
  bool submitted = false;
  String? catalogNote;

  @override
  void initState() {
    super.initState();
    final preferences = ref
        .read(appControllerProvider)
        .requireValue
        .preferences;
    provider = preferences.aiProvider;
    _apply(provider, preserve: true);
  }

  void _apply(AiProvider value, {bool preserve = false}) {
    final preferences = ref
        .read(appControllerProvider)
        .requireValue
        .preferences;
    final info = providerInfo(value);
    final same = preserve && preferences.aiProvider == value;
    endpoint.text = same ? preferences.aiEndpoint : info.defaultBaseUrl;
    parsing.text = same ? preferences.aiModel : info.seedParsingModel;
    chat.text = same ? preferences.aiChatModel : info.seedChatModel;
    models = {
      parsing.text,
      chat.text,
      info.seedParsingModel,
      info.seedChatModel,
    }.toList();
    catalogNote = null;
  }

  @override
  void dispose() {
    key.dispose();
    endpoint.dispose();
    parsing.dispose();
    chat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final info = providerInfo(provider);
    final checking = app.aiConnection == AiConnection.checking;
    final connected = app.aiConnection == AiConnection.connected;
    final z = context.zero;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .94,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Handle(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Intelligence',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  if (connected)
                    _Status(
                      label: 'Connected',
                      color: z.positive,
                      icon: Icons.check_rounded,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Your transactions stay on this device. Questions and message text you choose to analyze are sent to this provider.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: z.muted),
              ),
              const SizedBox(height: 28),
              DropdownButtonFormField<AiProvider>(
                initialValue: provider,
                decoration: const InputDecoration(
                  labelText: 'AI provider',
                  prefixIcon: Icon(Icons.memory_outlined),
                ),
                items: [
                  for (final value in AiProvider.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(providerInfo(value).label),
                    ),
                ],
                onChanged: checking
                    ? null
                    : (value) {
                        if (value == null || value == provider) return;
                        setState(() {
                          provider = value;
                          _apply(value);
                        });
                      },
              ),
              const SizedBox(height: 18),
              TextField(
                controller: key,
                obscureText: !keyVisible,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: info.keyLabel,
                  hintText: info.keyHint,
                  helperText: 'Create one at ${info.consoleUrl}',
                  errorText: submitted && key.text.trim().isEmpty
                      ? 'Enter an API key'
                      : app.aiConnection == AiConnection.rejected
                      ? app.error
                      : null,
                  suffixIcon: IconButton(
                    tooltip: keyVisible ? 'Hide API key' : 'Show API key',
                    onPressed: () => setState(() => keyVisible = !keyVisible),
                    icon: Icon(
                      keyVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: fetching || key.text.trim().isEmpty
                    ? null
                    : _loadModels,
                icon: fetching
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(fetching ? 'Finding models…' : 'Find my models'),
              ),
              if (catalogNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    catalogNote!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: z.muted),
                  ),
                ),
              const SizedBox(height: 24),
              _ModelField(
                label: 'Message reader',
                explanation: 'A fast, economical model is best.',
                controller: parsing,
                models: models,
              ),
              const SizedBox(height: 16),
              _ModelField(
                label: 'Money assistant',
                explanation:
                    'A stronger model gives better multi-step answers.',
                controller: chat,
                models: models,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() => advanced = !advanced),
                icon: Icon(
                  advanced
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                label: Text(
                  advanced ? 'Hide advanced settings' : 'Advanced settings',
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                child: advanced
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextField(
                          controller: endpoint,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Provider endpoint',
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: checking ? null : _connect,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                icon: checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_outline_rounded),
                label: Text(
                  checking ? 'Checking securely…' : 'Connect securely',
                ),
              ),
              if (connected) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    final accepted = await zeroConfirm(
                      context,
                      title: 'Disconnect intelligence?',
                      body:
                          'Asking questions and analyzing new messages will stop. Your existing transactions remain.',
                      action: 'Disconnect',
                    );
                    if (!accepted) return;
                    await ref
                        .read(appControllerProvider.notifier)
                        .disconnectAi();
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(foregroundColor: z.negative),
                  child: const Text('Disconnect provider'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadModels() async {
    setState(() {
      fetching = true;
      catalogNote = null;
    });
    final result = await const ModelCatalog().fetch(
      provider: provider,
      base: endpoint.text.trim(),
      apiKey: key.text.trim(),
    );
    if (!mounted) return;
    final info = providerInfo(provider);
    setState(() {
      fetching = false;
      if (result.isEmpty) {
        catalogNote =
            'No models were returned. Check the key and endpoint; the recommended defaults remain selected.';
      } else {
        models = result..sort();
        parsing.text = ModelCatalog.recommend(
          provider: provider,
          models: models,
          seed: info.seedParsingModel,
        );
        chat.text = ModelCatalog.recommend(
          provider: provider,
          models: models,
          seed: info.seedChatModel,
        );
        catalogNote =
            '${models.length} models found · recommendations selected';
      }
    });
  }

  Future<void> _connect() async {
    setState(() => submitted = true);
    if (key.text.trim().isEmpty ||
        parsing.text.trim().isEmpty ||
        chat.text.trim().isEmpty) {
      return;
    }
    final success = await ref
        .read(appControllerProvider.notifier)
        .connectAi(
          provider: provider,
          key: key.text.trim(),
          endpoint: endpoint.text.trim(),
          model: parsing.text.trim(),
          chatModel: chat.text.trim(),
        );
    if (success && mounted) Navigator.pop(context);
  }
}

class _ModelField extends StatelessWidget {
  const _ModelField({
    required this.label,
    required this.explanation,
    required this.controller,
    required this.models,
  });
  final String label;
  final String explanation;
  final TextEditingController controller;
  final List<String> models;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Autocomplete<String>(
        initialValue: TextEditingValue(text: controller.text),
        optionsBuilder: (value) => models.where(
          (model) =>
              value.text.isEmpty ||
              model.toLowerCase().contains(value.text.toLowerCase()),
        ),
        onSelected: (value) => controller.text = value,
        fieldViewBuilder: (context, field, focus, onSubmitted) {
          field.addListener(() => controller.text = field.text);
          return TextField(
            controller: field,
            focusNode: focus,
            autocorrect: false,
            decoration: InputDecoration(labelText: label),
          );
        },
      ),
      const SizedBox(height: 5),
      Text(
        explanation,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.zero.muted),
      ),
    ],
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.label, required this.color, required this.icon});
  final String label;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 5),
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    ],
  );
}

class _Handle extends StatelessWidget {
  const _Handle();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 34,
      height: 3,
      decoration: BoxDecoration(
        color: context.zero.line,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

Future<bool> zeroConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(sheet).textTheme.headlineMedium),
            const SizedBox(height: 10),
            Text(
              body,
              style: Theme.of(
                sheet,
              ).textTheme.bodyMedium?.copyWith(color: sheet.zero.muted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(sheet, true),
              style: FilledButton.styleFrom(
                backgroundColor: sheet.zero.negative,
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(action),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheet, false),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Center(child: Text('Cancel')),
            ),
          ],
        ),
      ),
    ) ??
    false;
