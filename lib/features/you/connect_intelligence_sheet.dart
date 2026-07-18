import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../ui/components/current_button.dart';
import '../../ui/components/current_field.dart';
import '../../ui/components/current_sheet.dart';

class ConnectIntelligenceSheet extends ConsumerStatefulWidget {
  const ConnectIntelligenceSheet({super.key});
  @override
  ConsumerState<ConnectIntelligenceSheet> createState() => _State();
}

class _State extends ConsumerState<ConnectIntelligenceSheet> {
  final _key = TextEditingController();
  late final _endpoint = TextEditingController(
    text: ref.read(appControllerProvider).value?.preferences.aiEndpoint,
  );
  late final _model = TextEditingController(
    text: ref.read(appControllerProvider).value?.preferences.aiModel,
  );
  bool _showKey = false;
  bool _advanced = false;
  bool _keyMissing = false;
  @override
  void dispose() {
    _key.dispose();
    _endpoint.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appControllerProvider);
    final checking = async.value?.aiConnection == AiConnection.checking;
    final error = async.value?.error;
    return CurrentSheet(
      title: 'Connect intelligence',
      explanation:
          'Questions and unseen message text you choose to analyze are sent to this provider. '
          'Your normalized activity stays on this device.',
      actions: CurrentButton(
        label: checking ? 'Checking connection…' : 'Connect',
        icon: Icons.link_rounded,
        expand: true,
        onPressed: checking ? null : _connect,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CurrentField(
            controller: _key,
            label: 'Ollama API key',
            hint: 'Paste your key',
            obscureText: !_showKey,
            prefixIcon: Icons.key_rounded,
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
              ),
            ),
          ),
          const SizedBox(height: 12),
          CurrentButton(
            label: _advanced ? 'Hide advanced options' : 'Advanced options',
            style: CurrentButtonStyle.text,
            icon: Icons.tune_rounded,
            onPressed: () => setState(() => _advanced = !_advanced),
          ),
          if (_advanced) ...[
            const SizedBox(height: 8),
            CurrentField(
              controller: _endpoint,
              label: 'Endpoint',
              hint: 'https://ollama.com',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            CurrentField(
              controller: _model,
              label: 'Model',
              hint: 'gpt-oss:20b',
            ),
          ],
        ],
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
          key: _key.text.trim(),
          endpoint: _endpoint.text.trim(),
          model: _model.text.trim(),
        );
    if (ok && mounted) Navigator.pop(context);
  }
}
