import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_state.dart';
import '../../../domain/ai_provider.dart';
import '../../../intelligence/model_catalog.dart';
import '../../theme/ff_theme.dart';
import '../../widgets/ff_controls.dart';
import '../../widgets/ff_group.dart';
import '../../widgets/ff_notice.dart';
import '../../widgets/ff_pressable.dart';
import '../../widgets/ff_screen.dart';
import '../../widgets/ff_sheet.dart';

/// Connecting a model.
///
/// Two models rather than one, because reading a payment message and reasoning
/// across a year of them are different jobs with different costs. The screen
/// says which is which instead of calling them "model 1" and "model 2".
class IntelligenceScreen extends ConsumerStatefulWidget {
  const IntelligenceScreen({super.key});

  @override
  ConsumerState<IntelligenceScreen> createState() => _IntelligenceScreenState();
}

class _IntelligenceScreenState extends ConsumerState<IntelligenceScreen> {
  late AiProvider _provider;
  final _key = TextEditingController();
  final _endpoint = TextEditingController();
  var _parsing = '';
  var _chat = '';
  List<String> _models = const [];
  bool _keyVisible = false;
  bool _fetching = false;
  bool _submitted = false;
  String? _catalogNote;

  @override
  void initState() {
    super.initState();
    final preferences = ref
        .read(appControllerProvider)
        .requireValue
        .preferences;
    _provider = preferences.aiProvider;
    _apply(_provider, preserve: true);
  }

  void _apply(AiProvider value, {bool preserve = false}) {
    final preferences = ref
        .read(appControllerProvider)
        .requireValue
        .preferences;
    final info = providerInfo(value);
    final same = preserve && preferences.aiProvider == value;
    _endpoint.text = same ? preferences.aiEndpoint : info.defaultBaseUrl;
    _parsing = same ? preferences.aiModel : info.seedParsingModel;
    _chat = same ? preferences.aiChatModel : info.seedChatModel;
    _models = {
      _parsing,
      _chat,
      info.seedParsingModel,
      info.seedChatModel,
    }.toList();
    _catalogNote = null;
  }

  @override
  void dispose() {
    _key.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final controller = ref.read(appControllerProvider.notifier);
    final info = providerInfo(_provider);
    final checking = app.aiConnection == AiConnection.checking;
    final connected = app.aiConnection == AiConnection.connected;
    final c = context.ff;

    return FFScreen(
      title: 'Intelligence',
      large: false,
      slivers: [
        if (connected)
          SliverToBoxAdapter(
            child: FFNotice(
              icon: Icons.check_circle_rounded,
              tone: FFNoticeTone.positive,
              title: 'Connected to ${info.label}',
              message:
                  'Questions and message text you have read are sent here. '
                  'Your transactions stay on this device.',
            ),
          )
        else if (app.aiConnection == AiConnection.rejected)
          SliverToBoxAdapter(
            child: FFNotice(
              icon: Icons.error_rounded,
              tone: FFNoticeTone.problem,
              title: 'That connection was refused',
              message: app.error,
            ),
          ),
        SliverToBoxAdapter(
          child: FFGroup(
            header: 'Provider',
            footer: 'Create a key at ${info.consoleUrl}',
            children: [
              FFRow(
                title: 'Service',
                value: info.label,
                onTap: checking
                    ? null
                    : () async {
                        final choice = await showFFPicker<AiProvider>(
                          context,
                          title: 'Provider',
                          current: _provider,
                          options: [
                            for (final value in AiProvider.values)
                              (value, providerInfo(value).label),
                          ],
                        );
                        if (choice == null || choice == _provider) return;
                        setState(() {
                          _provider = choice;
                          _apply(choice);
                        });
                      },
              ),
              Padding(
                padding: const EdgeInsets.all(FFSpace.md),
                child: FFField(
                  controller: _key,
                  obscure: !_keyVisible,
                  placeholder: info.keyHint,
                  onChanged: (_) => setState(() {}),
                  prefix: Icon(
                    Icons.key_rounded,
                    size: 18,
                    color: c.tertiaryLabel,
                  ),
                  suffix: FFPressable(
                    onTap: () => setState(() => _keyVisible = !_keyVisible),
                    semanticLabel: _keyVisible ? 'Hide key' : 'Show key',
                    child: Icon(
                      _keyVisible
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 19,
                      color: c.tertiaryLabel,
                    ),
                  ),
                ),
              ),
              if (_submitted && _key.text.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FFSpace.lg,
                    0,
                    FFSpace.lg,
                    FFSpace.md,
                  ),
                  child: Text(
                    'Enter an API key',
                    style: FFText.footnote.copyWith(color: c.red),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FFSpace.md,
                  0,
                  FFSpace.md,
                  FFSpace.md,
                ),
                child: FFField(
                  controller: _endpoint,
                  keyboardType: TextInputType.url,
                  placeholder: 'Endpoint',
                  style: FFText.footnote,
                  prefix: Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: c.tertiaryLabel,
                  ),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FFGroup(
            header: 'Models',
            footer:
                _catalogNote ??
                'The reader runs once per batch of messages, so a small fast '
                    'model suits it. The assistant reasons across many steps, '
                    'so a stronger one usually answers sooner overall.',
            children: [
              FFRow(
                title: 'Message reader',
                value: _parsing,
                onTap: () async {
                  final choice = await _pickModel('Message reader', _parsing);
                  if (choice != null) setState(() => _parsing = choice);
                },
              ),
              FFRow(
                title: 'Money assistant',
                value: _chat,
                onTap: () async {
                  final choice = await _pickModel('Money assistant', _chat);
                  if (choice != null) setState(() => _chat = choice);
                },
              ),
              FFRow(
                title: _fetching ? 'Finding models…' : 'Find my models',
                tinted: true,
                chevron: false,
                trailing: _fetching ? const FFSpinner(size: 17) : null,
                onTap: _fetching || _key.text.trim().isEmpty
                    ? null
                    : _loadModels,
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FFSpace.gutter,
              0,
              FFSpace.gutter,
              FFSpace.xl,
            ),
            child: FFButton(
              checking ? 'Checking…' : 'Connect securely',
              icon: Icons.lock_rounded,
              busy: checking,
              onTap: checking ? null : () => _connect(controller),
            ),
          ),
        ),
        if (connected)
          SliverToBoxAdapter(
            child: FFGroup(
              footer:
                  'Asking questions and reading new messages stop. Everything '
                  'already recorded stays.',
              children: [
                FFRow(
                  title: 'Disconnect',
                  destructive: true,
                  centered: true,
                  chevron: false,
                  onTap: () async {
                    final approved = await ffConfirm(
                      context,
                      title: 'Disconnect ${info.label}?',
                      message:
                          'Questions and message reading will stop until you '
                          'connect again.',
                      confirm: 'Disconnect',
                    );
                    if (!approved) return;
                    await controller.disconnectAi();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<String?> _pickModel(String title, String current) {
    final custom = TextEditingController(text: current);
    return showFFSheet<String>(
      context,
      builder: (sheet) => FFSheetScaffold(
        title: title,
        trailing: FFSheetAction(
          label: 'Use',
          emphasis: true,
          onTap: () => Navigator.of(sheet).pop(custom.text.trim()),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FFGroup(
              margin: const EdgeInsets.all(FFSpace.gutter),
              header: 'Model id',
              children: [
                Padding(
                  padding: const EdgeInsets.all(FFSpace.md),
                  child: FFField(
                    controller: custom,
                    placeholder: 'provider/model-name',
                    style: FFText.footnote,
                  ),
                ),
              ],
            ),
            if (_models.isNotEmpty)
              FFGroup(
                margin: const EdgeInsets.fromLTRB(
                  FFSpace.gutter,
                  0,
                  FFSpace.gutter,
                  FFSpace.gutter,
                ),
                header: 'Available',
                children: [
                  for (final model in _models)
                    FFRow(
                      title: model,
                      chevron: false,
                      trailing: model == current
                          ? Icon(
                              Icons.check_rounded,
                              size: 19,
                              color: sheet.ff.tint,
                            )
                          : null,
                      onTap: () => Navigator.of(sheet).pop(model),
                    ),
                ],
              ),
          ],
        ),
      ),
    ).whenComplete(custom.dispose);
  }

  Future<void> _loadModels() async {
    setState(() {
      _fetching = true;
      _catalogNote = null;
    });
    final result = await const ModelCatalog().fetch(
      provider: _provider,
      base: _endpoint.text.trim(),
      apiKey: _key.text.trim(),
    );
    if (!mounted) return;
    final info = providerInfo(_provider);
    setState(() {
      _fetching = false;
      if (result.isEmpty) {
        _catalogNote =
            'No models came back. Check the key and endpoint — the '
            'recommended defaults are still selected.';
      } else {
        _models = result..sort();
        _parsing = ModelCatalog.recommend(
          provider: _provider,
          models: _models,
          seed: info.seedParsingModel,
        );
        _chat = ModelCatalog.recommend(
          provider: _provider,
          models: _models,
          seed: info.seedChatModel,
        );
        _catalogNote =
            '${_models.length} models found · recommendations selected.';
      }
    });
  }

  Future<void> _connect(AppController controller) async {
    setState(() => _submitted = true);
    if (_key.text.trim().isEmpty || _parsing.isEmpty || _chat.isEmpty) return;
    final success = await controller.connectAi(
      provider: _provider,
      key: _key.text.trim(),
      endpoint: _endpoint.text.trim(),
      model: _parsing,
      chatModel: _chat,
    );
    if (success && mounted) Navigator.of(context).pop();
  }
}
