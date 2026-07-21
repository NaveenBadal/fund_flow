import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../domain/ai_provider.dart';
import '../../intelligence/model_catalog.dart';
import '../components/flow_field.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';

/// Connecting the AI provider.
///
/// A provider is chosen first; the key label, endpoint and model choices all
/// follow from it. Models are fetched live from the provider and offered as
/// dropdowns with a cost-efficient default pre-selected, so nobody has to type
/// an error-prone model id.
class ConnectIntelligenceSheet extends ConsumerStatefulWidget {
  const ConnectIntelligenceSheet({super.key});

  @override
  ConsumerState<ConnectIntelligenceSheet> createState() => _State();
}

class _State extends ConsumerState<ConnectIntelligenceSheet> {
  late AiProvider _provider;
  final _key = TextEditingController();
  late final _endpoint = TextEditingController();

  List<String> _models = const [];
  String _parsingModel = '';
  String _chatModel = '';

  bool _showKey = false;
  bool _advanced = false;
  bool _keyMissing = false;
  bool _fetching = false;
  String? _fetchNote;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(appControllerProvider).value?.preferences;
    _provider = prefs?.aiProvider ?? AiProvider.ollama;
    _applyProvider(_provider, preserve: prefs);
  }

  /// Resets the endpoint and seed models to the provider's defaults. When
  /// [preserve] matches the current provider, the stored models are kept.
  void _applyProvider(AiProvider provider, {dynamic preserve}) {
    final info = providerInfo(provider);
    final sameAsStored = preserve != null && preserve.aiProvider == provider;
    _endpoint.text = sameAsStored ? preserve.aiEndpoint : info.defaultBaseUrl;
    _parsingModel = sameAsStored ? preserve.aiModel : info.seedParsingModel;
    _chatModel = sameAsStored ? preserve.aiChatModel : info.seedChatModel;
    _models = {
      _parsingModel,
      _chatModel,
      info.seedParsingModel,
      info.seedChatModel,
    }.toList();
    _fetchNote = null;
  }

  @override
  void dispose() {
    _key.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    if (_key.text.trim().isEmpty) {
      setState(() => _keyMissing = true);
      return;
    }
    setState(() {
      _fetching = true;
      _fetchNote = null;
    });
    final fetched = await const ModelCatalog().fetch(
      provider: _provider,
      base: _endpoint.text.trim(),
      apiKey: _key.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _fetching = false;
      if (fetched.isEmpty) {
        _fetchNote = 'Could not list models — check the key. Using defaults.';
      } else {
        final info = providerInfo(_provider);
        _models = {...fetched, _parsingModel, _chatModel}.toList()..sort();
        _parsingModel = ModelCatalog.recommend(
          provider: _provider,
          models: fetched,
          seed: info.seedParsingModel,
        );
        _chatModel = ModelCatalog.recommend(
          provider: _provider,
          models: fetched,
          seed: info.seedChatModel,
        );
        _fetchNote = '${fetched.length} models · recommended pre-selected';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final text = Theme.of(context).textTheme;
    final info = providerInfo(_provider);
    final async = ref.watch(appControllerProvider);
    final checking = async.value?.aiConnection == AiConnection.checking;
    final error = async.value?.error;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FlowSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connect intelligence', style: text.titleLarge),
            const SizedBox(height: FlowSpace.sm),
            Text(
              'Choose a provider and connect the AI you trust. Questions and '
              'unseen message text you choose to analyze are sent to it; your '
              'normalized activity stays on this device.',
              style: text.bodyMedium?.copyWith(color: flow.inkSoft),
            ),
            const SizedBox(height: FlowSpace.lg),

            Text(
              'Provider',
              style: text.labelSmall?.copyWith(color: flow.inkSoft),
            ),
            const SizedBox(height: FlowSpace.sm),
            _Dropdown<AiProvider>(
              value: _provider,
              items: [
                for (final p in AiProvider.values)
                  DropdownMenuItem(
                    value: p,
                    child: Text(providerInfo(p).label),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _applyProvider(_provider = value));
              },
            ),
            const SizedBox(height: FlowSpace.md),

            FlowField(
              controller: _key,
              label: info.keyLabel,
              hint: info.keyHint,
              helper: 'Get a key at ${info.consoleUrl}',
              obscureText: !_showKey,
              error: _keyMissing ? 'Enter an API key.' : error,
              onChanged: (_) {
                if (_keyMissing) setState(() => _keyMissing = false);
              },
              suffix: IconButton(
                tooltip: _showKey ? 'Hide key' : 'Show key',
                onPressed: () => setState(() => _showKey = !_showKey),
                icon: Icon(
                  _showKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: flow.inkSoft,
                ),
              ),
            ),
            const SizedBox(height: FlowSpace.sm),

            OutlinedButton.icon(
              onPressed: _fetching ? null : _fetchModels,
              style: OutlinedButton.styleFrom(
                foregroundColor: flow.ink,
                side: BorderSide(color: flow.line),
                shape: const RoundedRectangleBorder(
                  borderRadius: FlowRadius.sm,
                ),
              ),
              icon: _fetching
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: flow.accent,
                      ),
                    )
                  : Icon(
                      Icons.cloud_sync_outlined,
                      size: 18,
                      color: flow.accent,
                    ),
              label: Text(_fetching ? 'Loading models…' : 'Load models'),
            ),
            if (_fetchNote != null) ...[
              const SizedBox(height: FlowSpace.xs),
              Text(
                _fetchNote!,
                style: text.bodySmall?.copyWith(color: flow.inkSoft),
              ),
            ],
            const SizedBox(height: FlowSpace.md),

            Text(
              'Parsing model',
              style: text.labelSmall?.copyWith(color: flow.inkSoft),
            ),
            const SizedBox(height: FlowSpace.sm),
            _Dropdown<String>(
              value: _models.contains(_parsingModel)
                  ? _parsingModel
                  : _models.first,
              items: [
                for (final m in _models)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (value) =>
                  setState(() => _parsingModel = value ?? _parsingModel),
            ),
            const SizedBox(height: 4),
            Text(
              'Reads transaction messages. A small fast model is best.',
              style: text.bodySmall?.copyWith(color: flow.inkFaint),
            ),
            const SizedBox(height: FlowSpace.md),

            Text(
              'Chat model',
              style: text.labelSmall?.copyWith(color: flow.inkSoft),
            ),
            const SizedBox(height: FlowSpace.sm),
            _Dropdown<String>(
              value: _models.contains(_chatModel) ? _chatModel : _models.first,
              items: [
                for (final m in _models)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (value) =>
                  setState(() => _chatModel = value ?? _chatModel),
            ),
            const SizedBox(height: 4),
            Text(
              'Answers your questions and runs the agent. A stronger model '
              'reaches an answer in fewer turns.',
              style: text.bodySmall?.copyWith(color: flow.inkFaint),
            ),
            const SizedBox(height: FlowSpace.sm),

            if (info.needsEndpoint) ...[
              TextButton.icon(
                onPressed: () => setState(() => _advanced = !_advanced),
                style: TextButton.styleFrom(
                  foregroundColor: flow.inkSoft,
                  padding: const EdgeInsets.symmetric(horizontal: FlowSpace.sm),
                ),
                icon: Icon(
                  _advanced
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(_advanced ? 'Hide advanced' : 'Advanced options'),
              ),
              if (_advanced) ...[
                const SizedBox(height: FlowSpace.sm),
                FlowField(
                  controller: _endpoint,
                  label: 'Endpoint',
                  hint: info.defaultBaseUrl,
                  keyboardType: TextInputType.url,
                  helper: 'Point at a self-hosted Ollama if needed.',
                ),
              ],
            ],
            const SizedBox(height: FlowSpace.xl),

            FilledButton.icon(
              onPressed: checking ? null : _connect,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(FlowDensity.minimumTarget),
                backgroundColor: flow.accent,
                foregroundColor: flow.onAccent,
                shape: const RoundedRectangleBorder(
                  borderRadius: FlowRadius.sm,
                ),
              ),
              icon: checking
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: flow.onAccent,
                      ),
                    )
                  : const Icon(Icons.link_rounded, size: 18),
              label: Text(checking ? 'Checking connection…' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect() async {
    if (_key.text.trim().isEmpty) {
      setState(() => _keyMissing = true);
      return;
    }
    final ok = await ref
        .read(appControllerProvider.notifier)
        .connectAi(
          provider: _provider,
          key: _key.text.trim(),
          endpoint: _endpoint.text.trim(),
          model: _parsingModel,
          chatModel: _chatModel.isEmpty ? null : _chatModel,
        );
    if (ok && mounted) Navigator.pop(context);
  }
}

/// A theme-consistent dropdown wrapped in the same field chrome as [FlowField].
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md),
      decoration: BoxDecoration(
        color: flow.sunken,
        borderRadius: FlowRadius.sm,
        border: Border.all(color: flow.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: flow.raised,
          icon: Icon(Icons.expand_more_rounded, color: flow.inkSoft),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: flow.ink),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
