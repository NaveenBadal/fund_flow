import 'package:flutter/material.dart';
import '../tokens/precision_tokens.dart';
import '../widgets/precision_components.dart';

class YouScreen extends StatelessWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? PrecisionTokens.backgroundDark : PrecisionTokens.backgroundLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PrecisionTokens.space24),
              child: PrecisionHeader(title: 'You', subtitle: 'Preferences & Intelligence'),
            ),
            const PrecisionDivider(),
            Expanded(
              child: ListView(
                children: [
                  _SectionHeader(title: 'INTELLIGENCE'),
                  _SettingRow(title: 'AI Provider', value: 'OpenAI GPT-4'),
                  const PrecisionDivider(),
                  _SettingRow(title: 'Local Context', value: 'Active'),
                  
                  _SectionHeader(title: 'MONEY SOURCES'),
                  _SettingRow(title: 'Bank Sync', value: 'Connected (3)'),
                  const PrecisionDivider(),
                  _SettingRow(title: 'SMS Parsing', value: 'Enabled'),
                  
                  _SectionHeader(title: 'PREFERENCES'),
                  _SettingRow(title: 'Appearance', value: 'Dark (Precision)'),
                  const PrecisionDivider(),
                  _SettingRow(title: 'Currency', value: 'USD (\$)'),
                  
                  const SizedBox(height: PrecisionTokens.space48),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PrecisionTokens.space24),
                    child: PrecisionButton(
                      label: 'Sign Out',
                      isPrimary: false,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(height: PrecisionTokens.space48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: PrecisionTokens.space24, 
        right: PrecisionTokens.space24,
        top: PrecisionTokens.space32, 
        bottom: PrecisionTokens.space8,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String title;
  final String value;

  const _SettingRow({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PrecisionTokens.space24, 
        vertical: PrecisionTokens.space16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: theme.textTheme.bodyLarge),
          Text(
            value, 
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.brightness == Brightness.dark 
                  ? PrecisionTokens.textSecondaryDark 
                  : PrecisionTokens.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
