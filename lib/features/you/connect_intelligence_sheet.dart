import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../ui/components/current_button.dart';
import '../../ui/components/current_field.dart';
import '../../ui/foundation/current_colors.dart';

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
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.current.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Connect intelligence',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'Candidate transaction text and questions are sent to this provider. '
              'Your normalized activity stays on this device.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.current.muted),
            ),
            const SizedBox(height: 22),
            CurrentField(
              controller: _key,
              label: 'Ollama API key',
              hint: 'Paste your key',
              obscureText: !_showKey,
              prefixIcon: Icons.key_rounded,
              error: error,
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
            const SizedBox(height: 24),
            CurrentButton(
              label: checking ? 'Checking connection…' : 'Connect',
              icon: Icons.link_rounded,
              expand: true,
              onPressed: checking || _key.text.trim().isEmpty
                  ? () async {
                      if (_key.text.trim().isEmpty) {
                        setState(() {});
                        return;
                      }
                    }
                  : () async {
                      final ok = await ref
                          .read(appControllerProvider.notifier)
                          .connectAi(
                            key: _key.text.trim(),
                            endpoint: _endpoint.text.trim(),
                            model: _model.text.trim(),
                          );
                      if (ok && context.mounted) Navigator.pop(context);
                    },
            ),
          ],
        ),
      ),
    );
  }
}
