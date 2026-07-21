import 'ai_provider.dart';

enum AppearancePreference { system, light, dark }

/// Ceiling for historical message scanning. Kept deliberately small: real
/// inbox volume is ~250 messages/month, so a 30 day window keeps the first
/// import inside a couple of minutes while notification capture handles
/// everything arriving after setup.
const int maximumLookbackDays = 30;
const int minimumLookbackDays = 7;

/// Extraction runs one structured pass per batch and never orchestrates
/// tools, so the small fast model is the right default. Chat drives a
/// multi-tool agent loop where a stronger model reaches an answer in fewer
/// turns, which is usually faster end to end despite the larger size.
///
/// Both defaults are verified against the live provider rather than chosen
/// from familiarity. Hosted models are retired on a schedule, and naming a
/// retired one makes every request fail with no way for someone to tell
/// that the model, rather than their question, was the problem.
const String defaultParsingModel = 'gpt-oss:20b-cloud';
const String defaultChatModel = 'gpt-oss:120b-cloud';

/// Chat models that were shipped as defaults and have since been retired by
/// the provider. Stored preferences are migrated off these on read, so an
/// install that already saved one is not stranded on a model that can only
/// return errors.
const Set<String> retiredChatModels = {
  'qwen3-coder:480b-cloud',
  'qwen3-coder:480b',
  'deepseek-v3.1:671b-cloud',
  'glm-4.6:cloud',
  'glm-4.6',
  'kimi-k2:1t-cloud',
  'minimax-m2:cloud',
};

class AppPreferences {
  const AppPreferences({
    this.onboardingComplete = false,
    // Dark is what this interface was designed in, not a variant of it, so
    // it is what someone sees before they have expressed a preference.
    // Choosing "system" or "light" in settings still does exactly that.
    this.appearance = AppearancePreference.dark,
    this.currency = 'INR',
    this.hideAmounts = false,
    this.lockApp = false,
    this.messageLookbackDays = maximumLookbackDays,
    this.captureNotifications = false,
    this.aiProvider = AiProvider.ollama,
    this.aiEndpoint = 'https://ollama.com',
    this.aiModel = defaultParsingModel,
    this.aiChatModel = defaultChatModel,
  });
  final bool onboardingComplete;
  final AppearancePreference appearance;
  final String currency;
  final bool hideAmounts;
  final bool lockApp;
  final int messageLookbackDays;
  final bool captureNotifications;

  /// Which provider the agent and extraction talk to.
  final AiProvider aiProvider;

  /// The provider's wire base URL (paths are appended by the adapter).
  final String aiEndpoint;

  /// Model used for structured SMS extraction.
  final String aiModel;

  /// Model used for the conversational agent loop.
  final String aiChatModel;

  AppPreferences copyWith({
    bool? onboardingComplete,
    AppearancePreference? appearance,
    String? currency,
    bool? hideAmounts,
    bool? lockApp,
    int? messageLookbackDays,
    bool? captureNotifications,
    AiProvider? aiProvider,
    String? aiEndpoint,
    String? aiModel,
    String? aiChatModel,
  }) => AppPreferences(
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    appearance: appearance ?? this.appearance,
    currency: currency ?? this.currency,
    hideAmounts: hideAmounts ?? this.hideAmounts,
    lockApp: lockApp ?? this.lockApp,
    messageLookbackDays: (messageLookbackDays ?? this.messageLookbackDays)
        .clamp(minimumLookbackDays, maximumLookbackDays),
    captureNotifications: captureNotifications ?? this.captureNotifications,
    aiProvider: aiProvider ?? this.aiProvider,
    aiEndpoint: aiEndpoint ?? this.aiEndpoint,
    aiModel: aiModel ?? this.aiModel,
    aiChatModel: aiChatModel ?? this.aiChatModel,
  );
}
