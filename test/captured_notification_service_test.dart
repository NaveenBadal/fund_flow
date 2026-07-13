import 'package:expense_manager/services/captured_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes a native captured notification event', () {
    final event = CapturedNotification.fromMap({
      'id': 'notification-key',
      'packageName': 'com.google.android.apps.messaging',
      'title': 'SBI Cards and Payment Services',
      'body': 'Rs.195.12 spent on your credit card at ZOMATO.',
      'postedAt': 1783957313441,
    });

    expect(event.id, 'notification-key');
    expect(event.packageName, 'com.google.android.apps.messaging');
    expect(event.title, 'SBI Cards and Payment Services');
    expect(event.body, contains('195.12'));
    expect(event.postedAt.millisecondsSinceEpoch, 1783957313441);
  });

  test('handles incomplete native event data safely', () {
    final event = CapturedNotification.fromMap(const {});

    expect(event.id, isEmpty);
    expect(event.body, isEmpty);
    expect(event.postedAt.millisecondsSinceEpoch, 0);
  });
}
