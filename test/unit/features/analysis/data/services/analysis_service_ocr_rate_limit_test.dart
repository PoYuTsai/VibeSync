import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

// recognizeOnly OCR 限流 429 的 client 側契約
// （docs/plans/2026-07-02-ocr-rate-limit-design.md I4/I5）。
//
// server 對免費 OCR 入口新增 6/分、60/天限流，429 帶 code: OCR_RATE_LIMITED
// 且**不帶** monthlyLimit/dailyLimit 鍵——client 必須：
//   1. 不落 Monthly/DailyLimitExceededException（那會誤導升級 paywall CTA）
//   2. 映射成 wait 動作的限流文案（不是 retry 的「暫時失敗」）
//   3. 不自動重試（重試只會繼續 429，養出 retry storm）

AnalysisService _service(MockClient client) {
  return AnalysisService(
    clientFactory: () => client,
    accessTokenProvider: () => 'fake-token',
    expectedTierProvider: () => null,
    revenueCatAppUserIdProvider: () async => null,
  );
}

Map<String, dynamic> _ocrRateLimitedBody({required String message}) {
  return {
    'error': 'OCR rate limited',
    'code': 'OCR_RATE_LIMITED',
    'message': message,
    'retryable': false,
  };
}

void main() {
  group('recognizeOnly request isolation', () {
    test('never serializes discarded conversation rows but keeps contact name',
        () async {
      Map<String, dynamic>? capturedBody;
      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(_ocrRateLimitedBody(message: '截圖辨識太頻繁，請稍後再試。')),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      try {
        await _service(mockClient).analyzeConversation(
          [
            Message(
              id: 'discarded-old-batch',
              content: '這句舊內容不可出現在 OCR request',
              isFromMe: false,
              timestamp: DateTime(2026, 7, 16),
            ),
          ],
          images: [
            Uint8List.fromList([1, 2, 3])
          ],
          knownContactName: 'Bruce',
          recognizeOnly: true,
        );
        fail('expected AnalysisException');
      } on AnalysisException {
        // The non-retriable 429 is only used to stop after the captured request.
      }

      expect(capturedBody?['messages'], isEmpty);
      expect(capturedBody?['knownContactName'], 'Bruce');
      expect(capturedBody?['recognizeOnly'], isTrue);
      expect(jsonEncode(capturedBody), isNot(contains('這句舊內容')));
    });
  });

  group('recognizeOnly 429 OCR_RATE_LIMITED mapping', () {
    test('maps to wait action with server message, single request (no retry)',
        () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode(
            _ocrRateLimitedBody(message: '截圖辨識太頻繁，請稍等一分鐘再試。'),
          ),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      AnalysisException? caught;
      try {
        await _service(mockClient).analyzeConversation(
          const [],
          images: [
            Uint8List.fromList([1, 2, 3])
          ],
          recognizeOnly: true,
        );
        fail('expected AnalysisException');
      } on AnalysisException catch (error) {
        caught = error;
      }

      expect(caught.code, 'OCR_RATE_LIMITED');
      expect(caught.suggestedAction, AnalysisErrorAction.wait);
      expect(caught.message, '截圖辨識太頻繁，請稍等一分鐘再試。');
      // I5：限流 429 絕不自動重試
      expect(requestCount, 1);
    });

    test('falls back to zh-TW copy when server message unreadable', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(_ocrRateLimitedBody(message: 'rate limited (minute)')),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      AnalysisException? caught;
      try {
        await _service(mockClient).analyzeConversation(
          const [],
          images: [
            Uint8List.fromList([1, 2, 3])
          ],
          recognizeOnly: true,
        );
        fail('expected AnalysisException');
      } on AnalysisException catch (error) {
        caught = error;
      }

      expect(caught.code, 'OCR_RATE_LIMITED');
      expect(caught.suggestedAction, AnalysisErrorAction.wait);
      expect(caught.message, contains('太頻繁'));
    });

    test('does NOT become Monthly/DailyLimitExceededException (I4)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(
            _ocrRateLimitedBody(message: '今日截圖辨識次數已達上限，明天早上 8 點恢復。'),
          ),
          429,
          headers: {'content-type': 'application/json'},
        );
      });

      AnalysisException? caught;
      try {
        await _service(mockClient).analyzeConversation(
          const [],
          images: [
            Uint8List.fromList([1, 2, 3])
          ],
          recognizeOnly: true,
        );
        fail('expected AnalysisException');
      } on AnalysisException catch (error) {
        caught = error;
      }

      expect(caught, isNot(isA<MonthlyLimitExceededException>()));
      expect(caught, isNot(isA<DailyLimitExceededException>()));
    });

    test('OCR_RATE_LIMITED is not auto-retriable (I5 pin)', () {
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'OCR_RATE_LIMITED',
          hasImages: true,
          recognizeOnly: true,
          hasDurableRequestId: false,
        ),
        isFalse,
      );
    });
  });
}
