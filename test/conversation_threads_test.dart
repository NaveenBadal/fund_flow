import 'package:flutter_test/flutter_test.dart';
import 'package:fund_flow/domain/conversation.dart';

void main() {
  group('thread titles', () {
    test('uses the question when it is short', () {
      expect(
        ConversationThread.titleFrom('How much did I spend on food?'),
        'How much did I spend on food?',
      );
    });

    test('collapses whitespace', () {
      expect(ConversationThread.titleFrom('  a\n\n  b  '), 'a b');
    });

    test('truncates on a word boundary rather than mid-word', () {
      final title = ConversationThread.titleFrom(
        'Please summarise absolutely everything that happened across all of '
        'my accounts during the whole of last month',
      );
      expect(title.length, lessThanOrEqualTo(62));
      expect(title, endsWith('…'));
      // The cut lands between words, so no fragment is left dangling.
      expect(title, isNot(contains('  ')));
      final body = title.substring(0, title.length - 1);
      expect(body.trimRight(), body);
    });

    test('falls back for an empty question', () {
      expect(ConversationThread.titleFrom('   '), 'New chat');
    });
  });

  group('thread rows', () {
    test('reads aggregate columns from the history query', () {
      final thread = ConversationThread.fromMap({
        'id': 3,
        'title': 'Groceries',
        'created_at': '2026-07-19T10:00:00.000Z',
        'updated_at': '2026-07-19T11:00:00.000Z',
        'message_count': 4,
        'preview': '  You spent less this month.  ',
      });
      expect(thread.id, 3);
      expect(thread.messageCount, 4);
      expect(thread.preview, 'You spent less this month.');
      expect(thread.updatedAt.isAfter(thread.createdAt), isTrue);
    });

    test('survives a missing title from an older row', () {
      final thread = ConversationThread.fromMap({
        'id': 1,
        'title': null,
        'created_at': '2026-07-19T10:00:00.000Z',
        'updated_at': '2026-07-19T10:00:00.000Z',
        'message_count': 1,
      });
      expect(thread.title, 'Untitled chat');
      expect(thread.preview, isNull);
    });
  });
}
