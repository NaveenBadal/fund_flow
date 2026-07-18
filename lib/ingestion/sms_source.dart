import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

import 'message_candidate.dart';

enum MessagePermission { undecided, granted, denied, permanentlyDenied }

class SmsSource {
  SmsSource({SmsQuery? query}) : _query = query ?? SmsQuery();
  final SmsQuery _query;

  Future<MessagePermission> permission({bool request = false}) async {
    var status = await Permission.sms.status;
    if (request && !status.isGranted) status = await Permission.sms.request();
    if (status.isGranted) return MessagePermission.granted;
    if (status.isPermanentlyDenied) return MessagePermission.permanentlyDenied;
    if (status.isDenied) return MessagePermission.denied;
    return MessagePermission.undecided;
  }

  Future<List<MessageCandidate>> recent(int days) async {
    final after = DateTime.now().subtract(Duration(days: days));
    final messages = await _query.querySms(
      kinds: [SmsQueryKind.inbox],
      sort: true,
      start: 0,
      count: 500,
    );
    return messages
        .where(
          (m) =>
              (m.date ?? DateTime.fromMillisecondsSinceEpoch(0)).isAfter(after),
        )
        .map(
          (m) => MessageCandidate(
            body: m.body ?? '',
            receivedAt: m.date ?? DateTime.now(),
            sender: m.sender,
          ),
        )
        .toList();
  }
}
