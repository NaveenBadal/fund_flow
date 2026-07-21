/// The AI providers Fund Flow can connect to.
///
/// Each is spoken to through its own native wire format — no compatibility
/// shims — so every provider gets its full fidelity and feature set. OpenAI
/// and Sarvam share one adapter only because Sarvam's native chat API *is* the
/// OpenAI chat-completions shape; Ollama, Claude and Gemini each have a
/// genuinely distinct native API and a dedicated adapter.
enum AiProvider {
  ollama,
  openai,
  gemini,
  claude,
  sarvam;

  static AiProvider fromName(String? name) => AiProvider.values.firstWhere(
    (p) => p.name == name,
    orElse: () => AiProvider.ollama,
  );
}

/// How a provider is spoken to on the wire — each is that provider's own
/// native API.
enum AiWireKind {
  /// Ollama's own `/api/chat` NDJSON streaming.
  ollamaNative,

  /// OpenAI `/chat/completions`. Native for OpenAI, and also Sarvam's native
  /// shape (Sarvam publishes an OpenAI-shaped chat API as its own).
  openai,

  /// Anthropic Messages API — `x-api-key`, `anthropic-version`, content-block
  /// tools (`tool_use` / `tool_result`).
  anthropic,

  /// Google Gemini's native `generateContent` — `contents`/`parts`,
  /// `functionDeclarations`, `functionCall` / `functionResponse`.
  gemini,
}

/// Static per-provider metadata: where to reach it, how to authenticate, and
/// the seed model ids used when a live model list can't be fetched.
class AiProviderInfo {
  const AiProviderInfo({
    required this.provider,
    required this.label,
    required this.wire,
    required this.defaultBaseUrl,
    required this.keyLabel,
    required this.keyHint,
    required this.consoleUrl,
    required this.seedParsingModel,
    required this.seedChatModel,
    this.recommendedContains = const [],
  });

  final AiProvider provider;
  final String label;
  final AiWireKind wire;

  /// The effective base the adapter appends paths to. For OpenAI-compatible
  /// providers this is the chat-completions root (e.g. `.../v1`); the adapter
  /// forms `$base/chat/completions` and `$base/models`.
  final String defaultBaseUrl;

  final String keyLabel;
  final String keyHint;

  /// Where a person gets a key — shown as a hint under the field.
  final String consoleUrl;

  /// Used to seed the model dropdowns before (or instead of) a live fetch.
  final String seedParsingModel;
  final String seedChatModel;

  /// Substrings that mark a cheap, capable default within a fetched list. The
  /// first live model whose id contains one of these (earliest match wins) is
  /// pre-selected as the recommendation.
  final List<String> recommendedContains;

  bool get needsEndpoint => provider == AiProvider.ollama;
}

/// The catalog, keyed by provider. Model ids here are only seeds — the connect
/// sheet fetches the live list per provider and pre-selects a recommendation.
const Map<AiProvider, AiProviderInfo> kAiProviders = {
  AiProvider.ollama: AiProviderInfo(
    provider: AiProvider.ollama,
    label: 'Ollama',
    wire: AiWireKind.ollamaNative,
    defaultBaseUrl: 'https://ollama.com',
    keyLabel: 'Ollama API key',
    keyHint: 'Paste your key',
    consoleUrl: 'ollama.com',
    seedParsingModel: 'gpt-oss:20b-cloud',
    seedChatModel: 'gpt-oss:120b-cloud',
    recommendedContains: ['gpt-oss:20b', 'gpt-oss'],
  ),
  AiProvider.openai: AiProviderInfo(
    provider: AiProvider.openai,
    label: 'OpenAI (ChatGPT)',
    wire: AiWireKind.openai,
    defaultBaseUrl: 'https://api.openai.com/v1',
    keyLabel: 'OpenAI API key',
    keyHint: 'sk-…',
    consoleUrl: 'platform.openai.com/api-keys',
    // Nano is the cheapest tool-calling tier; mini is the value chat tier.
    seedParsingModel: 'gpt-5-nano',
    seedChatModel: 'gpt-5-mini',
    recommendedContains: ['nano', 'mini'],
  ),
  AiProvider.gemini: AiProviderInfo(
    provider: AiProvider.gemini,
    label: 'Google Gemini',
    wire: AiWireKind.gemini,
    // Gemini's native generateContent root; the adapter forms
    // `$base/models/$model:streamGenerateContent`.
    defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    keyLabel: 'Gemini API key',
    keyHint: 'AIza…',
    consoleUrl: 'aistudio.google.com/apikey',
    // The `-latest` aliases stay valid as Google rolls model versions.
    seedParsingModel: 'gemini-flash-lite-latest',
    seedChatModel: 'gemini-flash-latest',
    recommendedContains: ['flash-lite', 'flash'],
  ),
  AiProvider.claude: AiProviderInfo(
    provider: AiProvider.claude,
    label: 'Claude (Anthropic)',
    wire: AiWireKind.anthropic,
    defaultBaseUrl: 'https://api.anthropic.com',
    keyLabel: 'Anthropic API key',
    keyHint: 'sk-ant-…',
    consoleUrl: 'console.anthropic.com/settings/keys',
    // Haiku is the cheapest; Sonnet reaches an answer in fewer agent turns.
    seedParsingModel: 'claude-haiku-4-5',
    seedChatModel: 'claude-sonnet-5',
    recommendedContains: ['haiku', 'sonnet'],
  ),
  AiProvider.sarvam: AiProviderInfo(
    provider: AiProvider.sarvam,
    label: 'Sarvam',
    wire: AiWireKind.openai,
    defaultBaseUrl: 'https://api.sarvam.ai/v1',
    keyLabel: 'Sarvam API subscription key',
    keyHint: 'Paste your key',
    consoleUrl: 'dashboard.sarvam.ai',
    // sarvam-m is deprecated; 30b is the cost-efficient current tier, 105b the
    // larger one.
    seedParsingModel: 'sarvam-30b',
    seedChatModel: 'sarvam-105b',
    recommendedContains: ['sarvam-30b', 'sarvam'],
  ),
};

AiProviderInfo providerInfo(AiProvider provider) => kAiProviders[provider]!;
