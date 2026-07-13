import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CapturedNotification {
  const CapturedNotification({
    required this.id,
    required this.packageName,
    required this.title,
    required this.body,
    required this.postedAt,
  });

  final String id;
  final String packageName;
  final String title;
  final String body;
  final DateTime postedAt;

  factory CapturedNotification.fromMap(Map<dynamic, dynamic> map) {
    final timestamp = (map['postedAt'] as num?)?.toInt() ?? 0;
    return CapturedNotification(
      id: map['id'] as String? ?? '',
      packageName: map['packageName'] as String? ?? '',
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      postedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
  }
}

class CapturedNotificationService {
  const CapturedNotificationService();

  static const _channel = MethodChannel(
    'com.naveen.expense_manager/notifications',
  );

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<bool> isAccessEnabled() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('isAccessEnabled') ?? false;
  }

  Future<void> openAccessSettings() async {
    if (isSupported) await _channel.invokeMethod<void>('openAccessSettings');
  }

  Future<void> setCaptureEnabled(bool enabled) async {
    if (isSupported) {
      await _channel.invokeMethod<void>('setCaptureEnabled', {
        'enabled': enabled,
      });
    }
  }

  Future<List<CapturedNotification>> getPending() async {
    if (!isSupported) return const [];
    final raw =
        await _channel.invokeListMethod<dynamic>('getPending') ?? const [];
    return [
      for (final item in raw)
        if (item is Map) CapturedNotification.fromMap(item),
    ].where((event) => event.id.isNotEmpty && event.body.isNotEmpty).toList();
  }

  Future<void> acknowledge(Iterable<String> ids) async {
    if (!isSupported) return;
    final values = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (values.isEmpty) return;
    await _channel.invokeMethod<void>('acknowledge', {'ids': values});
  }
}
