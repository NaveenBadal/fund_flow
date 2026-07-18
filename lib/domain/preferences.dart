enum AppearancePreference { system, light, dark }

class AppPreferences {
  const AppPreferences({
    this.onboardingComplete = false,
    this.appearance = AppearancePreference.system,
    this.currency = 'INR',
    this.hideAmounts = false,
    this.lockApp = false,
    this.messageLookbackDays = 30,
    this.captureNotifications = false,
    this.aiEndpoint = 'https://ollama.com',
    this.aiModel = 'gpt-oss:20b',
  });
  final bool onboardingComplete;
  final AppearancePreference appearance;
  final String currency;
  final bool hideAmounts;
  final bool lockApp;
  final int messageLookbackDays;
  final bool captureNotifications;
  final String aiEndpoint;
  final String aiModel;

  AppPreferences copyWith({
    bool? onboardingComplete,
    AppearancePreference? appearance,
    String? currency,
    bool? hideAmounts,
    bool? lockApp,
    int? messageLookbackDays,
    bool? captureNotifications,
    String? aiEndpoint,
    String? aiModel,
  }) => AppPreferences(
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    appearance: appearance ?? this.appearance,
    currency: currency ?? this.currency,
    hideAmounts: hideAmounts ?? this.hideAmounts,
    lockApp: lockApp ?? this.lockApp,
    messageLookbackDays: messageLookbackDays ?? this.messageLookbackDays,
    captureNotifications: captureNotifications ?? this.captureNotifications,
    aiEndpoint: aiEndpoint ?? this.aiEndpoint,
    aiModel: aiModel ?? this.aiModel,
  );
}
