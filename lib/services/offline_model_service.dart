import 'dart:io';

import 'package:flutter/services.dart';

class OfflineModelInfo {
  const OfflineModelInfo({
    required this.name,
    required this.sizeBytes,
    required this.modifiedAtMillis,
  });

  final String name;
  final int sizeBytes;
  final int modifiedAtMillis;

  factory OfflineModelInfo.fromMap(Map<dynamic, dynamic> map) {
    return OfflineModelInfo(
      name: (map['name'] as String? ?? '').trim(),
      sizeBytes: (map['sizeBytes'] as num? ?? 0).toInt(),
      modifiedAtMillis: (map['modifiedAtMillis'] as num? ?? 0).toInt(),
    );
  }
}

class OfflineModelService {
  const OfflineModelService();

  static const MethodChannel _channel = MethodChannel('expense_manager/offline_models');

  Future<List<OfflineModelInfo>> listModels() async {
    if (!Platform.isAndroid) return const [];

    final raw = await _channel.invokeMethod<List<dynamic>>('listModels');
    if (raw == null) return const [];

    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(OfflineModelInfo.fromMap)
        .where((model) => model.name.isNotEmpty)
        .toList();
  }

  Future<String> infer({
    required String modelName,
    required String prompt,
    int maxTokens = 4096,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Offline model inference is currently supported on Android only.');
    }

    final response = await _channel.invokeMethod<String>('infer', {
      'modelName': modelName,
      'prompt': prompt,
      'maxTokens': maxTokens,
    });

    return response?.trim() ?? '[]';
  }
}
