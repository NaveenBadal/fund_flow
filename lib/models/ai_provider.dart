enum AiProviderType { gemini, sarvam, offline, flutterGemma }

const selectedAiProviderStorageKey = 'selected_ai_provider';

extension AiProviderTypeX on AiProviderType {
  String get id => switch (this) {
        AiProviderType.gemini => 'gemini',
        AiProviderType.sarvam => 'sarvam',
        AiProviderType.offline => 'offline',
        AiProviderType.flutterGemma => 'flutter_gemma',
      };

  String get displayName => switch (this) {
        AiProviderType.gemini => 'Gemini',
        AiProviderType.sarvam => 'Sarvam',
        AiProviderType.offline => 'LiteRT',
        AiProviderType.flutterGemma => 'Edge',
      };

  String get apiKeyStorageKey => 'api_key_$id';

  String get modelStorageKey => 'model_$id';
}

AiProviderType aiProviderFromId(String? raw) {
  return AiProviderType.values.firstWhere(
    (provider) => provider.id == raw,
    orElse: () => AiProviderType.gemini,
  );
}

const defaultGeminiModel = 'gemini-3.1-flash';
const defaultSarvamModel = 'sarvam-30b';

String defaultModelFor(AiProviderType provider) {
  return switch (provider) {
    AiProviderType.gemini => defaultGeminiModel,
    AiProviderType.sarvam => defaultSarvamModel,
    AiProviderType.offline => '',
    AiProviderType.flutterGemma => '',
  };
}

class StaticModelOption {
  const StaticModelOption({
    required this.id,
    required this.displayName,
    required this.description,
  });

  final String id;
  final String displayName;
  final String description;
}

List<StaticModelOption> staticModelsFor(AiProviderType provider) {
  return switch (provider) {
    AiProviderType.gemini => const [
        StaticModelOption(
          id: defaultGeminiModel,
          displayName: 'Gemini 3.1 Flash',
          description: 'Default Gemini runtime. Live Gemini catalog can override this.',
        ),
      ],
    AiProviderType.sarvam => const [
        StaticModelOption(
          id: 'sarvam-30b',
          displayName: 'Sarvam 30B',
          description: 'Balanced latency and cost. Good default for production sync.',
        ),
        StaticModelOption(
          id: 'sarvam-105b',
          displayName: 'Sarvam 105B',
          description: 'Higher quality reasoning model for harder extraction cases.',
        ),
      ],
    AiProviderType.offline => const [],
    AiProviderType.flutterGemma => const [],
  };
}
