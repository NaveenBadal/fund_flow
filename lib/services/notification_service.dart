import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'database_helper.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _dailyDigestId = 1;
  static const _budgetAlertBaseId = 100;
  static const _syncReminderId = 200;

  Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings: initSettings);
    _initialized = true;
  }

  Future<void> scheduleDailyDigest() async {
    await _ensureInit();
    await _plugin.cancel(id: _dailyDigestId);

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      20, // 8 PM
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id: _dailyDigestId,
      title: 'Daily Spend Summary',
      body: "Tap to see today's expenses",
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_digest',
          'Daily Digest',
          channelDescription: 'Daily spending summary at 8 PM',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDailyDigest() async {
    await _ensureInit();
    await _plugin.cancel(id: _dailyDigestId);
  }

  Future<void> sendBudgetProximityAlert(String category, double pct) async {
    await _ensureInit();
    final id = _budgetAlertBaseId + category.hashCode % 50;
    await _plugin.show(
      id: id,
      title: 'Budget alert: $category',
      body: '${pct.toStringAsFixed(0)}% of your monthly $category budget used.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'budget_alerts',
          'Budget Alerts',
          channelDescription: 'Alerts when budget thresholds are crossed',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> checkAndSendSyncReminder() async {
    await _ensureInit();
    final lastSyncStr = await DatabaseHelper.instance.getAppMetadata('last_sync_at');
    if (lastSyncStr == null) return;

    final lastSync = DateTime.tryParse(lastSyncStr);
    if (lastSync == null) return;

    final daysSince = DateTime.now().difference(lastSync).inDays;
    if (daysSince >= 5) {
      await _plugin.show(
        id: _syncReminderId,
        title: 'Expenses untracked',
        body: "You haven't synced in $daysSince days — some transactions may be missing.",
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'sync_reminders',
            'Sync Reminders',
            channelDescription: 'Reminders to sync SMS expenses',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    }
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }
}
