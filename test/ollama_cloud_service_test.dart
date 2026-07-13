import 'dart:convert';

import 'package:expense_manager/services/ollama_cloud_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses an out-of-order AI batch using stable ids', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'message': {
            'content': jsonEncode({
              'results': [
                {
                  'id': 1,
                  'type': 'not_financial',
                  'amount': null,
                  'merchant': null,
                  'category': null,
                },
                {
                  'id': 0,
                  'type': 'expense',
                  'amount': '1,249.50',
                  'merchant': 'SWIGGY',
                  'category': 'food',
                },
              ],
            }),
          },
        }),
        200,
      );
    });

    final service = OllamaCloudService(
      apiKey: 'test',
      model: 'gpt-oss:20b-cloud',
      client: client,
    );
    final results = await service.parseBatch(['debit sms', 'otp sms']);

    expect(results[0]?.amount, 1249.5);
    expect(results[0]?.category, 'Food');
    expect(results[1]?.type, 'not_financial');
    expect(requestBody['think'], 'low');
    expect(requestBody['stream'], false);
  });

  test('rejects batches above the optimized maximum', () async {
    final service = OllamaCloudService(
      apiKey: 'test',
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(
      () => service.parseBatch(List.filled(13, 'sms')),
      throwsArgumentError,
    );
  });
}
