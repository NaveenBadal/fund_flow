import 'package:expense_manager/providers/expense_provider.dart';
import 'package:expense_manager/services/sms_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync state preserves structured analysis counts', () {
    const state = SyncState(
      phase: SyncPhase.analyzing,
      current: 12,
      total: 24,
      imported: 7,
      skipped: 5,
    );

    final next = state.copyWith(current: 18, imported: 10, skipped: 8);
    expect(next.total, 24);
    expect(next.current, 18);
    expect(next.imported, 10);
    expect(next.skipped, 8);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/sms_history');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'requests the complete Android inbox range using the selected cutoff',
    () async {
      final cutoff = DateTime(2026, 1, 14);
      MethodCall? capturedCall;
      final rows = List.generate(250, (index) {
        return {
          '_id': index,
          'address': 'BANK',
          'body': 'Transaction $index',
          'date': cutoff.millisecondsSinceEpoch + index,
        };
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            capturedCall = call;
            return rows;
          });

      final messages = await SmsService(
        historyChannel: channel,
        isAndroid: true,
      ).getMessages(since: cutoff);

      expect(capturedCall?.method, 'querySince');
      expect(
        (capturedCall?.arguments as Map)['since'],
        cutoff.millisecondsSinceEpoch,
      );
      expect(messages, hasLength(250));
      expect(messages.last.body, 'Transaction 249');
    },
  );
}
