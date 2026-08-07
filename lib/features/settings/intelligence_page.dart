import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../design/flux.dart';
import '../../domain/ai_provider.dart';
import '../../intelligence/model_catalog.dart';

/// Which provider answers questions and reads messages, and which models.
class IntelligencePage extends ConsumerWidget {
  const IntelligencePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final prefs = app?.preferences;
    if (prefs == null) {
      return const FluxDetailPage(title: 'Intelligence', slivers: []);
    }
    final info = providerInfo(prefs.aiProvider);
    final connected = app?.aiConnection == AiConnection.connected;

    return FluxDetailPage(
      title: 'Intelligence',
      slivers: [
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: FluxCard(
            border: connected
                ? palette.income.withValues(alpha: 0.3)
                : palette.attention.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(
                  connected
                      ? Icons.check_circle_outline
                      : Icons.link_off_rounded,
                  size: 20,
                  color: connected ? palette.income : palette.attention,
                ),
                const SizedBox(width: FluxSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected ? 'Connected' : 'Not connected',
                        style: FluxType.subtitle.copyWith(color: palette.text),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        connected
                            ? '${info.label} · key stored in the device keystore'
                            : 'Reading messages and answering questions both '
                                  'need a key',
                        style: FluxType.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'Provider',
            footer:
                'Each provider is spoken to in its own native API, so nothing '
                'is lost to a compatibility layer. Get a key at '
                '${info.consoleUrl}.',
            children: [
              FluxRow(
                title: 'Provider',
                value: info.label,
                chevron: true,
                onTap: () => showConnectSheet(
                  context: context,
                  ref: ref,
                  initialProvider: prefs.aiProvider,
                ),
              ),
              FluxRow(
                title: connected ? 'Replace key' : 'Add key',
                value: connected ? '••••••••' : 'Required',
                icon: Icons.key_outlined,
                chevron: true,
                onTap: () => showConnectSheet(
                  context: context,
                  ref: ref,
                  initialProvider: prefs.aiProvider,
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'Models',
            footer:
                'Reading messages is one structured pass, so a small fast model '
                'suits it. A question drives a multi-step tool loop, where a '
                'stronger model usually reaches the answer in fewer turns and '
                'less total time.',
            children: [
              FluxRow(
                title: 'Reading messages',
                value: prefs.aiModel,
                icon: Icons.bolt_outlined,
                chevron: true,
                onTap: () => showConnectSheet(
                  context: context,
                  ref: ref,
                  initialProvider: prefs.aiProvider,
                ),
              ),
              FluxRow(
                title: 'Answering questions',
                value: prefs.aiChatModel,
                icon: Icons.auto_awesome_outlined,
                chevron: true,
                onTap: () => showConnectSheet(
                  context: context,
                  ref: ref,
                  initialProvider: prefs.aiProvider,
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'What the agent may do',
            footer:
                'The agent reads your ledger freely and can prepare changes, '
                'but nothing is written until you approve the card it puts in '
                'the conversation. It answers questions about your money and '
                'declines everything else.',
            children: const [
              FluxRow(
                title: 'Reads your transactions',
                value: 'Always',
                icon: Icons.visibility_outlined,
              ),
              FluxRow(
                title: 'Changes anything',
                value: 'Only with approval',
                icon: Icons.lock_outline_rounded,
              ),
              FluxRow(
                title: 'Answers off-topic questions',
                value: 'Never',
                icon: Icons.block_rounded,
              ),
            ],
          ),
        ),
        if (connected)
          SliverToBoxAdapter(
            child: FluxGroup(
              children: [
                FluxRow(
                  title: 'Disconnect',
                  subtitle: 'Deletes the stored key. Your records stay.',
                  icon: Icons.logout_rounded,
                  danger: true,
                  onTap: () async {
                    final confirmed = await fluxConfirm(
                      context: context,
                      title: 'Disconnect the provider?',
                      message:
                          'The key is deleted from this device. Importing and '
                          'asking questions stop working until you add one '
                          'again. Nothing in your ledger is touched.',
                      confirmLabel: 'Disconnect',
                    );
                    if (confirmed) {
                      await ref
                          .read(appControllerProvider.notifier)
                          .disconnectAi();
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Connect or reconfigure a provider.
///
/// The key is validated against the live provider before it is stored, and the
/// model lists are fetched rather than typed. A wrong key or a retired model
/// discovered later shows up as a failed import with no clue which of the two
/// was wrong — checking here is the difference.
Future<void> showConnectSheet({
  required BuildContext context,
  required WidgetRef ref,
  required AiProvider initialProvider,
}) => showFluxSheet<void>(
  context: context,
  builder: (context) => _ConnectSheet(initialProvider: initialProvider),
);

class _ConnectSheet extends ConsumerStatefulWidget {
  const _ConnectSheet({required this.initialProvider});
  final AiProvider initialProvider;

  @override
  ConsumerState<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends ConsumerState<_ConnectSheet> {
  late AiProvider _provider = widget.initialProvider;
  late final TextEditingController _key = TextEditingController();
  late final TextEditingController _endpoint = TextEditingController(
    text: providerInfo(widget.initialProvider).defaultBaseUrl,
  );
  String? _parsingModel;
  String? _chatModel;
  List<String> _models = const [];
  bool _fetching = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(appControllerProvider).value?.preferences;
    if (prefs != null && prefs.aiProvider == widget.initialProvider) {
      _parsingModel = prefs.aiModel;
      _chatModel = prefs.aiChatModel;
      _endpoint.text = prefs.aiEndpoint;
    } else {
      final info = providerInfo(_provider);
      _parsingModel = info.seedParsingModel;
      _chatModel = info.seedChatModel;
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  void _switchProvider(AiProvider next) {
    final info = providerInfo(next);
    setState(() {
      _provider = next;
      _endpoint.text = info.defaultBaseUrl;
      _parsingModel = info.seedParsingModel;
      _chatModel = info.seedChatModel;
      _models = const [];
      _error = null;
    });
  }

  Future<void> _fetchModels() async {
    if (_key.text.trim().isEmpty) {
      setState(
        () => _error =
            'Paste a key first — the list comes from the '
            'provider.',
      );
      return;
    }
    setState(() {
      _fetching = true;
      _error = null;
    });
    final ids = await const ModelCatalog().fetch(
      provider: _provider,
      base: _endpoint.text.trim(),
      apiKey: _key.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _fetching = false;
      _models = ids;
      if (ids.isEmpty) {
        _error =
            'The provider did not return a model list. The seed models '
            'below still work.';
        return;
      }
      // Pre-select the provider's own cheap-and-capable tier rather than
      // whatever sorts first alphabetically.
      final info = providerInfo(_provider);
      for (final hint in info.recommendedContains) {
        final match = ids.where((id) => id.contains(hint));
        if (match.isNotEmpty) {
          _parsingModel = match.first;
          break;
        }
      }
      if (!ids.contains(_chatModel)) {
        _chatModel = ids.contains(info.seedChatModel)
            ? info.seedChatModel
            : ids.first;
      }
      if (!ids.contains(_parsingModel)) _parsingModel = ids.first;
    });
  }

  Future<void> _connect() async {
    if (_key.text.trim().isEmpty) {
      setState(() => _error = 'A key is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await ref
        .read(appControllerProvider.notifier)
        .connectAi(
          provider: _provider,
          key: _key.text.trim(),
          endpoint: _endpoint.text.trim(),
          model: _parsingModel ?? providerInfo(_provider).seedParsingModel,
          chatModel: _chatModel ?? providerInfo(_provider).seedChatModel,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error =
            ref.read(appControllerProvider).value?.error ??
            'The provider did not accept that key.';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final info = providerInfo(_provider);

    return FluxSheetBody(
      title: 'Connect intelligence',
      subtitle: 'Validated against the provider before it is saved',
      actions: FluxButton(
        label: 'Test and connect',
        busy: _saving,
        onPressed: _connect,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: FluxSpace.x2,
            runSpacing: FluxSpace.x2,
            children: [
              for (final provider in AiProvider.values)
                FluxChip(
                  label: providerInfo(provider).label,
                  selected: provider == _provider,
                  onTap: () => _switchProvider(provider),
                ),
            ],
          ),
          const SizedBox(height: FluxSpace.x5),
          FluxField(
            controller: _key,
            label: info.keyLabel,
            hint: info.keyHint,
            obscure: true,
            helper: 'Stored in the Android keystore, never in the database.',
            error: _error,
          ),
          if (info.needsEndpoint) ...[
            const SizedBox(height: FluxSpace.x4),
            FluxField(
              controller: _endpoint,
              label: 'Endpoint',
              hint: info.defaultBaseUrl,
            ),
          ],
          const SizedBox(height: FluxSpace.x4),
          FluxButton(
            label: _models.isEmpty ? 'Fetch model list' : 'Refresh model list',
            kind: FluxButtonKind.secondary,
            icon: Icons.cloud_download_outlined,
            compact: true,
            busy: _fetching,
            onPressed: _fetchModels,
          ),
          const SizedBox(height: FluxSpace.x4),
          _ModelPicker(
            label: 'Reading messages',
            value: _parsingModel ?? info.seedParsingModel,
            options: _models,
            onChanged: (value) => setState(() => _parsingModel = value),
          ),
          const SizedBox(height: FluxSpace.x3),
          _ModelPicker(
            label: 'Answering questions',
            value: _chatModel ?? info.seedChatModel,
            options: _models,
            onChanged: (value) => setState(() => _chatModel = value),
          ),
          const SizedBox(height: FluxSpace.x4),
          Text(
            'Your key goes only to ${info.label}. Message text is sent to it '
            'for reading; nothing is sent anywhere else.',
            style: FluxType.caption.copyWith(color: palette.textFaint),
          ),
        ],
      ),
    );
  }
}

class _ModelPicker extends StatelessWidget {
  const _ModelPicker({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return FluxPressable(
      onTap: options.isEmpty
          ? null
          : () async {
              final chosen = await showFluxPicker<String>(
                context: context,
                title: label,
                selected: value,
                options: [for (final id in options) (id, id)],
              );
              if (chosen != null) onChanged(chosen);
            },
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: palette.isDark ? palette.surface : palette.surfaceHighest,
          shape: FluxRadius.shape(
            FluxRadius.sm,
            side: BorderSide(color: palette.line, width: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FluxSpace.x4,
            vertical: FluxSpace.x3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: FluxType.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluxType.body.copyWith(color: palette.text),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: options.isEmpty ? palette.line : palette.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
