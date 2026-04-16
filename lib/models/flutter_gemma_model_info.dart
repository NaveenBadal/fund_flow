class FlutterGemmaModelInfo {
  const FlutterGemmaModelInfo({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modifiedAtMillis,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final int modifiedAtMillis;
}
