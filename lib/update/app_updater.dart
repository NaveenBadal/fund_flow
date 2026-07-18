import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

enum UpdateAvailability { unsupported, current, available }

class AppUpdate {
  const AppUpdate({
    required this.availability,
    required this.versionName,
    required this.buildNumber,
    required this.installedBuildNumber,
    required this.releaseNotes,
    required this.publishedAt,
    required this.apkUrl,
    required this.sha256,
    required this.mandatory,
    required this.downloadSize,
  });

  final UpdateAvailability availability;
  final String versionName;
  final int buildNumber;
  final int installedBuildNumber;
  final String releaseNotes;
  final DateTime publishedAt;
  final Uri apkUrl;
  final String sha256;
  final bool mandatory;
  final int downloadSize;
}

class AppUpdater {
  AppUpdater({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _channel = MethodChannel('fund_flow/updater');
  static final _releases = Uri.parse(
    'https://api.github.com/repos/NaveenBadal/fund_flow/releases?per_page=10',
  );

  Future<AppUpdate> check({PackageInfo? installedPackage}) async {
    final package = installedPackage ?? await PackageInfo.fromPlatform();
    final installed = int.tryParse(package.buildNumber) ?? 0;
    if (!package.packageName.endsWith('.dev')) {
      return AppUpdate(
        availability: UpdateAvailability.unsupported,
        versionName: package.version,
        buildNumber: installed,
        installedBuildNumber: installed,
        releaseNotes:
            'In-app updates are available only in development builds.',
        publishedAt: DateTime.fromMillisecondsSinceEpoch(0),
        apkUrl: Uri(),
        sha256: '',
        mandatory: false,
        downloadSize: 0,
      );
    }
    final releasesResponse = await _client
        .get(
          _releases,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'Fund-Flow-Android-Updater',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (releasesResponse.statusCode != 200) {
      throw UpdateException('GitHub returned ${releasesResponse.statusCode}.');
    }
    final releases = jsonDecode(releasesResponse.body) as List;
    Uri? manifestUrl;
    var downloadSize = 0;
    for (final raw in releases) {
      final release = raw as Map<String, dynamic>;
      if (release['draft'] == true || release['prerelease'] != true) continue;
      for (final rawAsset in release['assets'] as List? ?? const []) {
        final asset = rawAsset as Map<String, dynamic>;
        if (asset['name'] == 'update.json') {
          manifestUrl = Uri.parse(asset['browser_download_url'] as String);
        } else if (asset['name'] == 'fund-flow-development.apk') {
          downloadSize = asset['size'] as int? ?? 0;
        }
      }
      if (manifestUrl != null) break;
    }
    if (manifestUrl == null) {
      throw const UpdateException('No development update manifest was found.');
    }
    final manifestResponse = await _client
        .get(manifestUrl)
        .timeout(const Duration(seconds: 20));
    if (manifestResponse.statusCode != 200) {
      throw const UpdateException(
        'The update manifest could not be downloaded.',
      );
    }
    final manifest = jsonDecode(manifestResponse.body) as Map<String, dynamic>;
    _validateManifest(manifest);
    final build = manifest['buildNumber'] as int;
    return AppUpdate(
      availability: build > installed
          ? UpdateAvailability.available
          : UpdateAvailability.current,
      versionName: manifest['versionName'] as String,
      buildNumber: build,
      installedBuildNumber: installed,
      releaseNotes: manifest['releaseNotes'] as String,
      publishedAt: DateTime.parse(manifest['publishedAt'] as String).toLocal(),
      apkUrl: Uri.parse(manifest['apkUrl'] as String),
      sha256: (manifest['sha256'] as String).toLowerCase(),
      mandatory: manifest['mandatory'] as bool,
      downloadSize: downloadSize,
    );
  }

  Future<File> download(
    AppUpdate update, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (update.availability != UpdateAvailability.available) {
      throw const UpdateException('There is no newer update to download.');
    }
    final request = http.Request('GET', update.apkUrl);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw UpdateException(
        'The APK download returned ${response.statusCode}.',
      );
    }
    final cache = Directory(
      path.join((await getTemporaryDirectory()).path, 'fund_flow_updates'),
    );
    await cache.create(recursive: true);
    final file = File(
      path.join(cache.path, 'fund-flow-${update.buildNumber}.apk'),
    );
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final bytes in response.stream) {
        sink.add(bytes);
        received += bytes.length;
        onProgress?.call(received, response.contentLength ?? 0);
      }
    } finally {
      await sink.close();
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString().toLowerCase() != update.sha256) {
      await file.delete();
      throw const UpdateException(
        'The downloaded APK failed SHA-256 verification.',
      );
    }
    return file;
  }

  Future<void> install(File apk) async {
    final allowed =
        await _channel.invokeMethod<bool>('canRequestInstalls') ?? false;
    if (!allowed) {
      await _channel.invokeMethod<void>('openInstallPermission');
      throw const InstallPermissionRequired();
    }
    await _channel.invokeMethod<void>('installApk', {'path': apk.path});
  }

  void close() => _client.close();

  static void _validateManifest(Map<String, dynamic> value) {
    const required = {
      'schemaVersion',
      'channel',
      'versionName',
      'buildNumber',
      'apkUrl',
      'sha256',
      'releaseNotes',
      'publishedAt',
      'mandatory',
    };
    if (value.keys.any((key) => !required.contains(key)) ||
        !required.every(value.containsKey) ||
        value['schemaVersion'] != 1 ||
        value['channel'] != 'development' ||
        value['buildNumber'] is! int ||
        value['mandatory'] is! bool ||
        value['sha256'] is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value['sha256'] as String) ||
        value['versionName'] is! String ||
        value['releaseNotes'] is! String ||
        value['publishedAt'] is! String ||
        DateTime.tryParse(value['publishedAt'] as String) == null ||
        Uri.tryParse(value['apkUrl']?.toString() ?? '')?.host != 'github.com') {
      throw const UpdateException('The update manifest is not trusted.');
    }
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class InstallPermissionRequired extends UpdateException {
  const InstallPermissionRequired()
    : super('Allow Fund Flow to install updates, then tap Install again.');
}
