import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../flow_os/foundation/flow_color.dart';
import '../flow_os/primitives/coordinate_label.dart';
import '../flow_os/primitives/cut_surface.dart';
import '../flow_os/primitives/loom_mark.dart';
import '../models/ai_provider.dart';
import '../providers/expense_provider.dart';
import '../services/ollama_cloud_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _pageCount = 4;
  final _pages = PageController();
  final _key = TextEditingController();
  final _endpoint = TextEditingController(text: defaultOllamaBaseUrl);
  int _page = 0;
  bool _working = false;
  bool _restoring = true;
  bool _showKey = false;
  bool _showAdvanced = false;
  bool _continuedWithoutAi = false;
  String _model = defaultOllamaModel;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _key.text = ref.read(ollamaApiKeyProvider);
    _endpoint.text = ref.read(ollamaBaseUrlProvider);
    _model = ref.read(ollamaModelProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreStage());
  }

  @override
  void dispose() {
    _pages.dispose();
    _key.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncProvider);
    return Scaffold(
      body: ColoredBox(
        color: FlowColor.canvas(context),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.lg,
                  AppSpacing.page,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    LoomMark(
                      size: 42,
                      state: _working || sync.isAnalyzing
                          ? LoomState.checking
                          : LoomState.ready,
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: CoordinateLabel('COMMISSION / FLOW AGENT'),
                    ),
                    Text(
                      '0${_page + 1}:0$_pageCount',
                      style: TextStyle(
                        color: FlowColor.proof,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .7,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.page,
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < _pageCount; index++) ...[
                      Expanded(
                        child: Container(
                          height: index == _page ? 3 : 1,
                          color: index <= _page
                              ? FlowColor.proof
                              : FlowColor.rule(context),
                        ),
                      ),
                      if (index != _pageCount - 1) const SizedBox(width: 5),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) => setState(() => _page = page),
                  children: [
                    const _PromiseStage(),
                    _ConnectionStage(
                      keyController: _key,
                      endpointController: _endpoint,
                      model: _model,
                      showKey: _showKey,
                      showAdvanced: _showAdvanced,
                      error: _connectionError,
                      onToggleKey: () => setState(() => _showKey = !_showKey),
                      onToggleAdvanced: () =>
                          setState(() => _showAdvanced = !_showAdvanced),
                      onModelChanged: (value) => setState(() => _model = value),
                    ),
                    _SmsStage(aiReady: !_continuedWithoutAi),
                    _AnalysisStage(sync: sync, aiReady: !_continuedWithoutAi),
                  ],
                ),
              ),
              _BottomAction(
                page: _page,
                working: _working || _restoring,
                sync: sync,
                onBack: _back,
                onPrimary: _primaryAction,
                onSkipAi: _page == 1 && !_working ? _skipAi : null,
                onSkipSms: _page == 2 && !_working ? _skipSms : null,
                onStop: sync.isAnalyzing
                    ? () => ref.read(syncProvider.notifier).cancel()
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _primaryAction() async {
    switch (_page) {
      case 0:
        await _saveStage(1);
        _next();
      case 1:
        await _connectAi();
      case 2:
        await _analyzeSms();
      case 3:
        final phase = ref.read(syncProvider).phase;
        if (phase == SyncPhase.error || phase == SyncPhase.idle) {
          if (_continuedWithoutAi) {
            _back();
          } else {
            await _analyzeSms(fromAnalysis: true);
          }
        } else if (phase == SyncPhase.complete) {
          await _finish();
        }
    }
  }

  Future<void> _connectAi() async {
    final key = _key.text.trim();
    if (key.isEmpty) {
      setState(
        () => _connectionError = 'Enter your Ollama API key to connect Flow.',
      );
      return;
    }
    setState(() {
      _working = true;
      _connectionError = null;
    });
    final endpoint = _endpoint.text.trim().isEmpty
        ? defaultOllamaBaseUrl
        : _endpoint.text.trim();
    final service = OllamaCloudService(
      apiKey: key,
      baseUrl: endpoint,
      model: _model,
    );
    final connected = await service.validateKey();
    service.close();
    if (!mounted) return;
    if (!connected) {
      setState(() {
        _working = false;
        _connectionError =
            'Flow could not connect. Check the key, endpoint, and internet connection.';
      });
      return;
    }
    await Future.wait([
      ref
          .read(secureStorageProvider)
          .write(key: ollamaApiKeyStorageKey, value: key),
      ref
          .read(secureStorageProvider)
          .write(key: ollamaBaseUrlStorageKey, value: endpoint),
      ref
          .read(secureStorageProvider)
          .write(key: ollamaModelStorageKey, value: _model),
    ]);
    ref.read(ollamaApiKeyProvider.notifier).set(key);
    ref.read(ollamaBaseUrlProvider.notifier).set(endpoint);
    ref.read(ollamaModelProvider.notifier).set(_model);
    if (!mounted) return;
    setState(() {
      _working = false;
      _continuedWithoutAi = false;
    });
    await _saveStage(2);
    _next();
  }

  void _skipAi() {
    setState(() {
      _continuedWithoutAi = true;
      _connectionError = null;
    });
    _saveStage(2);
    _next();
  }

  Future<void> _analyzeSms({bool fromAnalysis = false}) async {
    if (_continuedWithoutAi) {
      if (!fromAnalysis) _next();
      return;
    }
    if (!fromAnalysis) {
      await _saveStage(3);
      _next();
    }
    await ref.read(syncProvider.notifier).sync();
  }

  Future<void> _skipSms() async {
    _next();
    await _finish();
  }

  Future<void> _finish() async {
    await ref.read(secureStorageProvider).delete(key: 'onboarding_stage');
    await markOnboardingDone(ref.read(secureStorageProvider));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const AppShell()),
    );
  }

  void _next() => _pages.nextPage(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.medium,
    curve: AppMotion.emphasizedDecelerate,
  );

  void _back() => _pages.previousPage(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.fast,
    curve: AppMotion.standard,
  );

  Future<void> _saveStage(int stage) async {
    try {
      await ref
          .read(secureStorageProvider)
          .write(key: 'onboarding_stage', value: '$stage')
          .timeout(const Duration(milliseconds: 500));
    } catch (_) {
      // Persistence improves recovery but must never block activation.
    }
  }

  Future<void> _restoreStage() async {
    String? raw;
    try {
      raw = await ref
          .read(secureStorageProvider)
          .read(key: 'onboarding_stage')
          .timeout(const Duration(milliseconds: 500));
    } catch (_) {
      raw = null;
    }
    if (!mounted) return;
    final saved = int.tryParse(raw ?? '') ?? 0;
    // An interrupted network/permission task resumes at explicit SMS consent
    // so work is never silently repeated on launch.
    final target = saved >= 3 ? 2 : saved.clamp(0, 2);
    if (target > 0 && _pages.hasClients) _pages.jumpToPage(target);
    if (mounted) setState(() => _restoring = false);
  }
}

class _OnboardingSignal extends StatelessWidget {
  const _OnboardingSignal();

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final details = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MESSAGE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: FlowColor.quiet(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        const _SignalLine(widthFactor: .82),
        const SizedBox(height: 7),
        const _SignalLine(widthFactor: .58),
        const SizedBox(height: 18),
        Text(
          'UNDERSTOOD AS',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: FlowPalette.signalCyan,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '₹ 1,240  ·  FOOD',
          style: AppTheme.money(
            Theme.of(context).textTheme.titleLarge?.copyWith(
              color: FlowColor.content(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'PROOF ATTACHED',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: FlowColor.mint,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
          ),
        ),
      ],
    );
    return SizedBox(
      height: largeText ? 520 : 224,
      width: double.infinity,
      child: CutSurface(
        cut: 20,
        color: FlowColor.plane(context),
        accent: FlowColor.proof,
        padding: const EdgeInsets.all(22),
        child: largeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LoomMark(size: 64, state: LoomState.proven),
                  const SizedBox(height: 18),
                  Expanded(child: details),
                ],
              )
            : Row(
                children: [
                  const LoomMark(size: 86, state: LoomState.proven),
                  const SizedBox(width: 20),
                  Expanded(child: details),
                ],
              ),
      ),
    );
  }
}

class _SignalLine extends StatelessWidget {
  const _SignalLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: widthFactor,
    child: Container(height: 7, color: FlowColor.rule(context)),
  );
}

class _PromiseStage extends StatelessWidget {
  const _PromiseStage();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.narrative,
        AppSpacing.page,
        AppSpacing.section,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _OnboardingSignal(),
          const SizedBox(height: AppSpacing.region),
          const CoordinateLabel('PROMISE / EVIDENCE-BACKED AI'),
          const SizedBox(height: 10),
          Text(
            'YOUR MONEY\nLEARNS TO ANSWER.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: FlowColor.content(context),
              fontWeight: FontWeight.w900,
              height: .98,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Flow turns bank messages into a private evidence network, reasons across it, and shows the proof behind every financial answer.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: FlowColor.quiet(context),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStage extends StatelessWidget {
  const _ConnectionStage({
    required this.keyController,
    required this.endpointController,
    required this.model,
    required this.showKey,
    required this.showAdvanced,
    required this.error,
    required this.onToggleKey,
    required this.onToggleAdvanced,
    required this.onModelChanged,
  });

  final TextEditingController keyController;
  final TextEditingController endpointController;
  final String model;
  final bool showKey;
  final bool showAdvanced;
  final String? error;
  final VoidCallback onToggleKey;
  final VoidCallback onToggleAdvanced;
  final ValueChanged<String> onModelChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          const CoordinateLabel('INTELLIGENCE / ATTACH'),
          const SizedBox(height: 9),
          Text(
            'ATTACH THE\nREASONING ENGINE.',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: FlowColor.content(context),
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Flow needs an Ollama connection to understand messages and answer questions. Your credential is stored securely on this device.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: FlowColor.quiet(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          TextField(
            controller: keyController,
            obscureText: !showKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Ollama API key',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                tooltip: showKey ? 'Hide API key' : 'Show API key',
                onPressed: onToggleKey,
                icon: Icon(showKey ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton.icon(
            onPressed: onToggleAdvanced,
            icon: Icon(showAdvanced ? Icons.expand_less : Icons.tune_rounded),
            label: Text(showAdvanced ? 'Hide advanced' : 'Advanced connection'),
          ),
          if (showAdvanced) ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: endpointController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Endpoint',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: model,
              decoration: const InputDecoration(
                labelText: 'Model',
                prefixIcon: Icon(Icons.memory_rounded),
              ),
              items: ollamaModelChoices
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onModelChanged(value);
              },
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            _InlineMessage(
              icon: Icons.cloud_off_rounded,
              text: error!,
              error: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _SmsStage extends StatelessWidget {
  const _SmsStage({required this.aiReady});
  final bool aiReady;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          LoomMark(
            size: 58,
            state: aiReady ? LoomState.review : LoomState.offline,
          ),
          const SizedBox(height: AppSpacing.section),
          const CoordinateLabel('CHANNEL / TRANSACTION SMS'),
          const SizedBox(height: 8),
          Text(
            'OPEN AN EVIDENCE\nCHANNEL.',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: FlowColor.content(context),
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            aiReady
                ? 'Flow will scan recent messages on this device for supported bank and payment transactions, then analyze those candidates with your connected AI.'
                : 'AI is not connected, so Flow cannot analyze transaction messages yet. You can connect it from Flow after setup.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: FlowColor.quiet(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.region),
          const _TrustRow(
            icon: Icons.filter_alt_outlined,
            title: 'Financial candidates only',
            body: 'Unrelated conversations are ignored by the import flow.',
          ),
          const _TrustRow(
            icon: Icons.cloud_outlined,
            title: 'Clear processing boundary',
            body:
                'Candidate message text is sent to your configured Ollama endpoint for extraction.',
          ),
          const _TrustRow(
            icon: Icons.phone_android_rounded,
            title: 'Records stay local',
            body:
                'Structured transactions, provenance, and conversation history are stored on this device.',
          ),
          const SizedBox(height: AppSpacing.md),
          _InlineMessage(
            icon: Icons.shield_outlined,
            text: aiReady
                ? 'Android will ask for SMS access after you choose Analyze messages.'
                : 'Return to the previous step to connect AI before analysis.',
          ),
        ],
      ),
    );
  }
}

class _AnalysisStage extends StatelessWidget {
  const _AnalysisStage({required this.sync, required this.aiReady});
  final SyncState sync;
  final bool aiReady;

  @override
  Widget build(BuildContext context) {
    final progress = sync.total == 0 ? null : sync.current / sync.total;
    final complete = sync.phase == SyncPhase.complete;
    final error = sync.phase == SyncPhase.error;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          LoomMark(
            size: 64,
            state: complete
                ? LoomState.proven
                : error
                ? LoomState.review
                : aiReady
                ? LoomState.checking
                : LoomState.offline,
            progress: progress,
          ),
          const SizedBox(height: AppSpacing.section),
          CoordinateLabel(
            complete
                ? 'COMMISSION / COMPLETE'
                : error
                ? 'COMMISSION / INTERRUPTED'
                : 'COMMISSION / BUILDING PROOF',
            color: error ? FlowColor.amber : FlowColor.proof,
          ),
          const SizedBox(height: 8),
          Text(
            complete
                ? 'Your first brief is ready'
                : error
                ? 'Flow needs your help'
                : aiReady
                ? 'Understanding your messages'
                : 'Connect AI to start analysis',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: FlowColor.content(context),
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            complete
                ? 'Flow has finished checking recent transaction messages. Open the agent to explore what it understood.'
                : error
                ? sync.errorMessage ?? 'Analysis could not finish.'
                : aiReady
                ? sync.detail ??
                      'Preparing a private financial picture from your transaction messages.'
                : 'The core SMS analysis and Flow agent require an AI connection.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: error ? FlowColor.amber : FlowColor.quiet(context),
            ),
          ),
          const SizedBox(height: AppSpacing.region),
          if (!complete && !error && aiReady) ...[
            if (progress != null) ...[
              LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Container(height: 6, color: FlowColor.plane(context)),
                    Container(
                      width: constraints.maxWidth * progress.clamp(0, 1),
                      height: 6,
                      color: FlowColor.proof,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              sync.total > 0
                  ? '${sync.current} of ${sync.total} messages analyzed'
                  : _phaseLabel(sync.phase),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
          if (complete)
            _InlineMessage(
              icon: Icons.verified_rounded,
              text: sync.detail ?? 'Analysis complete.',
            ),
          if (error)
            const _InlineMessage(
              icon: Icons.info_outline_rounded,
              text:
                  'Nothing is deleted. Retry is duplicate-safe, or adjust access and try again.',
            ),
        ],
      ),
    );
  }

  static String _phaseLabel(SyncPhase phase) => switch (phase) {
    SyncPhase.requestingPermissions => 'Waiting for SMS access',
    SyncPhase.fetchingSms => 'Finding recent transaction messages',
    SyncPhase.analyzing => 'Analyzing with Flow intelligence',
    _ => 'Preparing analysis',
  };
}

class _TrustRow extends StatelessWidget {
  const _TrustRow({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: CutSurface(
      cut: 8,
      color: FlowColor.plane(context),
      padding: const EdgeInsets.all(13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            color: FlowColor.raised(context),
            child: Icon(icon, size: 17, color: FlowColor.proof),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: FlowColor.content(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: FlowColor.quiet(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.text,
    this.error = false,
  });
  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final signal = error ? FlowColor.amber : FlowColor.proof;
    return CutSurface(
      cut: 8,
      color: FlowColor.plane(context),
      accent: signal,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: signal),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: FlowColor.quiet(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.page,
    required this.working,
    required this.sync,
    required this.onBack,
    required this.onPrimary,
    this.onSkipAi,
    this.onSkipSms,
    this.onStop,
  });
  final int page;
  final bool working;
  final SyncState sync;
  final VoidCallback onBack;
  final VoidCallback onPrimary;
  final VoidCallback? onSkipAi;
  final VoidCallback? onSkipSms;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final running =
        sync.phase == SyncPhase.requestingPermissions ||
        sync.phase == SyncPhase.fetchingSms ||
        sync.phase == SyncPhase.analyzing;
    final primaryEnabled = !working && !running;
    final label = switch (page) {
      0 => 'Set up Flow',
      1 => working ? 'Checking connection…' : 'Connect intelligence',
      2 => 'Allow and analyze',
      3 when sync.phase == SyncPhase.complete => 'Open Flow',
      3 when sync.phase == SyncPhase.error => 'Try analysis again',
      3 => 'Connect AI',
      _ => 'Continue',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.section,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (page > 0 && !running)
                Semantics(
                  button: true,
                  label: 'Back',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: working ? null : onBack,
                    child: Container(
                      width: 48,
                      height: 56,
                      alignment: Alignment.center,
                      color: FlowColor.plane(context),
                      child: Text(
                        '←',
                        style: TextStyle(
                          color: FlowColor.content(context),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(width: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Semantics(
                  button: true,
                  enabled: primaryEnabled,
                  label: label,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: primaryEnabled ? onPrimary : null,
                    child: CutSurface(
                      cut: 10,
                      color: primaryEnabled
                          ? FlowColor.loom
                          : FlowColor.plane(context),
                      accent: primaryEnabled
                          ? FlowColor.proof
                          : FlowColor.rule(context),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LoomMark(
                            size: 24,
                            state: working
                                ? LoomState.checking
                                : primaryEnabled
                                ? LoomState.ready
                                : LoomState.offline,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              '${label.toUpperCase()} →',
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: primaryEnabled
                                    ? Colors.white
                                    : FlowColor.quiet(context),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (onStop != null)
            _QuietAction(label: 'STOP SAFELY', onTap: onStop!)
          else if (onSkipAi != null)
            _QuietAction(
              label: 'CONTINUE WITH LIMITED CAPABILITIES',
              onTap: onSkipAi!,
            )
          else if (onSkipSms != null)
            _QuietAction(label: 'KEEP SMS CLOSED', onTap: onSkipSms!),
        ],
      ),
    );
  }
}

class _QuietAction extends StatelessWidget {
  const _QuietAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        label,
        style: TextStyle(
          color: FlowColor.quiet(context),
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .65,
        ),
      ),
    ),
  );
}
