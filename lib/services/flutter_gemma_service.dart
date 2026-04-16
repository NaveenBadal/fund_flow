import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

import '../models/flutter_gemma_model_info.dart';

class FlutterGemmaService {
  const FlutterGemmaService();

  static const _supportedExtensions = {'task', 'bin', 'gguf', 'litertlm'};

  static Future<Directory> modelsDir() async {
    // App's own external files dir — always accessible, no permission needed.
    // path: /storage/emulated/0/Android/data/<package>/files/models/
    final base = await getExternalStorageDirectory();
    final dir = Directory('${base!.path}/models');
    await dir.create(recursive: true);
    return dir;
  }

  // Tracks which model + token limit the FlutterGemmaPlugin singleton has loaded.
  static String? _loadedModelPath;
  static int? _loadedMaxTokens;

  Future<List<FlutterGemmaModelInfo>> listModels() async {
    final models = <FlutterGemmaModelInfo>[];
    final seenPaths = <String>{};

    // Primary: app's own external files dir (no permission needed)
    try {
      await _scanDir(await modelsDir(), models, seenPaths);
    } catch (_) {}

    // Fallback: public Downloads (accessible on older Android / with storage permission)
    for (final path in [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Downloads',
    ]) {
      try {
        await _scanDir(Directory(path), models, seenPaths);
      } catch (_) {}
    }

    return models;
  }

  Future<void> _scanDir(
    Directory dir,
    List<FlutterGemmaModelInfo> out,
    Set<String> seen,
  ) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final ext = entity.path.split('.').last.toLowerCase();
      if (!_supportedExtensions.contains(ext)) continue;
      if (!seen.add(entity.path)) continue;
      try {
        final stat = await entity.stat();
        out.add(FlutterGemmaModelInfo(
          name: entity.path.split('/').last,
          path: entity.path,
          sizeBytes: stat.size,
          modifiedAtMillis: stat.modified.millisecondsSinceEpoch,
        ));
      } catch (_) {}
    }
  }

  Future<String> infer({
    required String modelPath,
    required String prompt,
    int maxTokens = 4096,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('flutter_gemma inference is currently Android-only.');
    }

    // Re-init if model path changed.
    if (_loadedModelPath != modelPath) {
      // In 0.13.2, installModel with fromFile for absolute paths
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(modelPath)
          .install();
      _loadedModelPath = modelPath;
    }

    final model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
    );

    final chat = await model.createChat(
      temperature: 0.2,
      randomSeed: 1,
    );

    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    final response = await chat.generateChatResponse();
    
    if (response is TextResponse) {
      return response.token.trim();
    }
    return '[]';
  }
}
