import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  final _income = TextEditingController();
  final _buffer = TextEditingController();
  int _page = 0;
  String _currency = 'INR';
  static const _steps = [
    _Step(
      number: '01',
      title: 'See your money clearly',
      body:
          'Flow keeps incoming and outgoing transactions together in one simple activity list.',
      icon: Icons.receipt_long_outlined,
    ),
    _Step(
      number: '02',
      title: 'Find transactions automatically',
      body:
          'Import supported bank messages, avoid duplicates, and review where each transaction came from.',
      icon: Icons.sms_outlined,
    ),
    _Step(
      number: '03',
      title: 'Set your preferences',
      body:
          'Choose your currency and add an optional income estimate and safety buffer.',
      icon: Icons.tune_rounded,
    ),
    _Step(
      number: '04',
      title: 'Private AI assistance',
      body:
          'Allow SMS access to import bank transactions. You choose when original messages can be shared with your configured AI.',
      icon: Icons.privacy_tip_outlined,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _income.dispose();
    _buffer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _page == _steps.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: AppRadius.all(14),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_outlined,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Flow',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _finish(requestPermission: false),
                    child: Text(last ? 'Not now' : 'Skip'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) => index == 2
                    ? _SetupView(
                        currency: _currency,
                        income: _income,
                        buffer: _buffer,
                        onCurrency: (value) =>
                            setState(() => _currency = value),
                      )
                    : _StepView(step: _steps[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: Row(
                children: [
                  for (var index = 0; index < _steps.length; index++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: index == _page ? 34 : 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 7),
                      decoration: BoxDecoration(
                        color: index == _page
                            ? scheme.primary
                            : scheme.outlineVariant,
                        borderRadius: AppRadius.all(99),
                      ),
                    ),
                  const Spacer(),
                  FloatingActionButton.extended(
                    onPressed: last
                        ? () => _finish(requestPermission: true)
                        : _next,
                    icon: Icon(
                      last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                    ),
                    label: Text(last ? 'Allow and continue' : 'Continue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _next() => _controller.nextPage(
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
  );

  Future<void> _finish({required bool requestPermission}) async {
    await ref.read(preferredCurrencyProvider.notifier).setCurrency(_currency);
    await ref
        .read(monthlyPlanProvider.notifier)
        .setPlan(
          income: double.tryParse(_income.text.trim()) ?? 0,
          buffer: double.tryParse(_buffer.text.trim()) ?? 0,
        );
    if (requestPermission) {
      await Permission.sms.request();
    }
    await markOnboardingDone(ref.read(secureStorageProvider));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    }
  }
}

class _SetupView extends StatelessWidget {
  const _SetupView({
    required this.currency,
    required this.income,
    required this.buffer,
    required this.onCurrency,
  });

  final String currency;
  final TextEditingController income;
  final TextEditingController buffer;
  final ValueChanged<String> onCurrency;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '03',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 34),
        Text(
          'Choose your money preferences',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'These are planning guides, not account balances. You can change them later.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        DropdownButtonFormField<String>(
          initialValue: currency,
          decoration: const InputDecoration(
            labelText: 'Primary currency',
            prefixIcon: Icon(Icons.language_rounded),
          ),
          items: const ['INR', 'USD', 'EUR', 'GBP', 'SGD', 'AED']
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onCurrency(value);
          },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: income,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Expected monthly income (optional)',
            prefixIcon: const Icon(Icons.south_west_rounded),
            prefixText: '$currency ',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: buffer,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Safety buffer (optional)',
            prefixIcon: const Icon(Icons.shield_outlined),
            prefixText: '$currency ',
          ),
        ),
      ],
    ),
  );
}

class _Step {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
  });
  final String number;
  final String title;
  final String body;
  final IconData icon;
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step});
  final _Step step;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.number,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 220,
            width: double.infinity,
            child: Material(
              color: scheme.primaryContainer,
              shape: ExpressiveShape.hero(),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned(
                    right: -24,
                    top: -34,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Positioned(
                    left: -18,
                    bottom: -30,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(step.icon, size: 44, color: scheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            step.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            step.body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
