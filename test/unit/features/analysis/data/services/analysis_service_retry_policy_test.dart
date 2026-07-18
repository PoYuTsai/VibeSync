import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

void main() {
  group('AnalysisService.isAutoRetriableAnalysisError', () {
    test('圖片完整分析（已扣費路徑）的 TIMEOUT 不自動重試', () {
      // server Claude timeout 120s（parse retry 最壞再 +120s）＞ client 120s，
      // client timeout 時 server 很可能已完成並扣費；自動重打會重複扣 2-3 則。
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'TIMEOUT',
          hasImages: true,
          recognizeOnly: false,
        ),
        isFalse,
      );
    });

    test('recognizeOnly（免費 OCR）所有暫時性錯誤都不在背景自動重送', () {
      for (final code in [
        'TIMEOUT',
        'NETWORK_ERROR',
        'UNEXPECTED_ERROR',
        'UPSTREAM_UNAVAILABLE',
      ]) {
        expect(
          AnalysisService.isAutoRetriableAnalysisError(
            code: code,
            hasImages: true,
            recognizeOnly: true,
          ),
          isFalse,
          reason: '$code 應由使用者手動重試，避免同批圖片背景連發',
        );
      }
    });

    test('無圖路徑的 TIMEOUT 維持自動重試', () {
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'TIMEOUT',
          hasImages: false,
          recognizeOnly: false,
        ),
        isTrue,
      );
    });

    test('圖片路徑的其他 retriable code 不受影響', () {
      for (final code in [
        'NETWORK_ERROR',
        'UNEXPECTED_ERROR',
        'UPSTREAM_UNAVAILABLE',
      ]) {
        expect(
          AnalysisService.isAutoRetriableAnalysisError(
            code: code,
            hasImages: true,
            recognizeOnly: false,
          ),
          isTrue,
          reason: '$code 應維持自動重試',
        );
      }
    });

    test('非 retriable code 一律不重試', () {
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'QUOTA_EXCEEDED',
          hasImages: false,
          recognizeOnly: false,
        ),
        isFalse,
      );
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: null,
          hasImages: false,
          recognizeOnly: false,
        ),
        isFalse,
      );
    });

    test('recognizeOnly 收到 AI_RESPONSE_INVALID 時整個操作只送一次 HTTP', () async {
      var calls = 0;
      final service = AnalysisService(
        clientFactory: () => MockClient((request) async {
          calls += 1;
          return http.Response(
            jsonEncode({
              'error': 'AI_RESPONSE_INVALID',
              'code': 'AI_RESPONSE_INVALID',
              'message': '這次辨識結果格式異常，請再試一次。本次不會扣額度。',
              'retryable': false,
              'shouldChargeQuota': false,
            }),
            502,
            headers: {'content-type': 'application/json'},
          );
        }),
        accessTokenProvider: () => 'fake-token',
        expectedTierProvider: () => null,
        revenueCatAppUserIdProvider: () async => null,
      );

      await expectLater(
        () => service.analyzeConversation(
          const <Message>[],
          images: [
            Uint8List.fromList([1, 2, 3])
          ],
          recognizeOnly: true,
        ),
        throwsA(
          isA<AnalysisException>()
              .having((error) => error.code, 'code', 'AI_RESPONSE_INVALID')
              .having(
                (error) => error.message,
                'message',
                contains('本次不會扣額度'),
              ),
        ),
      );
      expect(calls, 1, reason: '一次 OCR 點擊不得背景重送圖片');
    });
  });
}
