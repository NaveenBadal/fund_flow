import 'package:flutter/material.dart';

import '../ui/components/current_button.dart';
import '../ui/components/current_field.dart';
import '../ui/foundation/current_colors.dart';
import '../ui/foundation/current_theme.dart';
import '../ui/layout/current_shell.dart';

class FundFlowApp extends StatelessWidget {
  const FundFlowApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fund Flow',
    debugShowCheckedModeBanner: false,
    theme: CurrentTheme.light(),
    darkTheme: CurrentTheme.dark(),
    themeMode: ThemeMode.system,
    home: const _FoundationPreview(),
  );
}

class _FoundationPreview extends StatefulWidget {
  const _FoundationPreview();
  @override
  State<_FoundationPreview> createState() => _FoundationPreviewState();
}

class _FoundationPreviewState extends State<_FoundationPreview> {
  RootDestination _destination = RootDestination.ask;
  final _question = TextEditingController();
  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CurrentShell(
    destination: _destination,
    onDestinationChanged: (value) => setState(() => _destination = value),
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(switch (_destination) {
                  RootDestination.ask => 'Ask',
                  RootDestination.activity => 'Activity',
                  RootDestination.you => 'You',
                }, style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text(
                  'The new Fund Flow foundation is ready.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: context.current.muted),
                ),
                const SizedBox(height: 160),
                if (_destination == RootDestination.ask) ...[
                  CurrentField(
                    controller: _question,
                    hint: 'Ask about your money',
                    helper: 'Answers use only the activity you allow',
                    minLines: 1,
                    maxLines: 4,
                    suffix: Icon(
                      Icons.arrow_upward_rounded,
                      color: context.current.intelligence,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CurrentButton(
                    label: 'Connect intelligence',
                    onPressed: () {},
                    icon: Icons.link_rounded,
                    expand: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
