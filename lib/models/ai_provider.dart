/// Configuration for the single AI backend: Ollama Cloud.
///
/// No on-device models, no provider switching — one fast, low-memory path.
const ollamaApiKeyStorageKey = 'ollama_api_key';
const ollamaBaseUrlStorageKey = 'ollama_base_url';
const ollamaModelStorageKey = 'ollama_model';

const defaultOllamaBaseUrl = 'https://ollama.com';
const defaultOllamaModel = 'gpt-oss:20b-cloud';

/// No hardcoded key. User provides the key from Settings; it is persisted in
/// secure storage and loaded on startup through the You controls.
const defaultOllamaApiKey = '';

/// Models worth surfacing in the picker, fastest → most capable.
const ollamaModelChoices = <String>[
  'gpt-oss:20b-cloud',
  'gpt-oss:120b-cloud',
  'gpt-oss:20b',
  'gpt-oss:120b',
  'qwen3:235b',
  'deepseek-v3.1:671b',
];
