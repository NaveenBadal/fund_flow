import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/preferences.dart';

class SecurePreferences {
  const SecurePreferences(this._storage);
  final FlutterSecureStorage _storage;

  static const _onboarding = 'greenfield.onboarding';
  static const _appearance = 'greenfield.appearance';
  static const _currency = 'greenfield.currency';
  static const _hidden = 'greenfield.hidden';
  static const _lock = 'greenfield.lock';
  static const _lookback = 'greenfield.lookback';
  static const _capture = 'greenfield.capture';
  static const _endpoint = 'greenfield.endpoint';
  static const _model = 'greenfield.model';
  static const _chatModel = 'greenfield.chat_model';
  static const apiKeyName = 'greenfield.ai_key';

  Future<AppPreferences> read() async {
    final values = await _storage.readAll();
    return AppPreferences(
      onboardingComplete: values[_onboarding] == 'true',
      appearance: AppearancePreference.values.firstWhere(
        (e) => e.name == values[_appearance],
        orElse: () => AppearancePreference.system,
      ),
      currency: values[_currency] ?? 'INR',
      hideAmounts: values[_hidden] == 'true',
      lockApp: values[_lock] == 'true',
      // Stored values may predate the 30 day ceiling, so clamp on read.
      messageLookbackDays:
          (int.tryParse(values[_lookback] ?? '') ?? maximumLookbackDays).clamp(
            minimumLookbackDays,
            maximumLookbackDays,
          ),
      captureNotifications: values[_capture] == 'true',
      aiEndpoint: values[_endpoint] ?? 'https://ollama.com',
      aiModel: switch (values[_model]) {
        null || 'gpt-oss:20b' => defaultParsingModel,
        final value => value,
      },
      // An install that saved a since-retired default would otherwise keep
      // sending every question to a model that only returns errors.
      aiChatModel: switch (values[_chatModel]) {
        null => defaultChatModel,
        final value when retiredChatModels.contains(value) => defaultChatModel,
        final value => value,
      },
    );
  }

  Future<void> write(AppPreferences value) async {
    await Future.wait([
      _storage.write(key: _onboarding, value: '${value.onboardingComplete}'),
      _storage.write(key: _appearance, value: value.appearance.name),
      _storage.write(key: _currency, value: value.currency),
      _storage.write(key: _hidden, value: '${value.hideAmounts}'),
      _storage.write(key: _lock, value: '${value.lockApp}'),
      _storage.write(key: _lookback, value: '${value.messageLookbackDays}'),
      _storage.write(key: _capture, value: '${value.captureNotifications}'),
      _storage.write(key: _endpoint, value: value.aiEndpoint),
      _storage.write(key: _model, value: value.aiModel),
      _storage.write(key: _chatModel, value: value.aiChatModel),
    ]);
  }

  Future<String> apiKey() async => await _storage.read(key: apiKeyName) ?? '';
  Future<void> writeApiKey(String value) async => value.isEmpty
      ? _storage.delete(key: apiKeyName)
      : _storage.write(key: apiKeyName, value: value);
}
