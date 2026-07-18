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
      // server request-level deadline 是 120s、client 是 130s；若本機仍逾時，
      // server 可能已完成並進入結算，自動重打會造成重複扣額風險。
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'TIMEOUT',
          hasImages: true,
          recognizeOnly: false,
          hasDurableRequestId: false,
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
            hasDurableRequestId: false,
          ),
          isFalse,
          reason: '$code 應由使用者手動重試，避免同批圖片背景連發',
        );
      }
    });

    test('無圖路徑的 TIMEOUT 也不自動重試，避免結算期間重複扣額', () {
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'TIMEOUT',
          hasImages: false,
          recognizeOnly: false,
          hasDurableRequestId: false,
        ),
        isFalse,
      );
    });

    test('沒有 durable requestId 的其他 transport error 也不自動重送', () {
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
            hasDurableRequestId: false,
          ),
          isFalse,
          reason: '$code 必須由使用者手動重試，避免 lost-response 重複扣額',
        );
      }
    });

    test('有 durable requestId 的暫時錯誤可安全沿用同一身份重試', () {
      for (final code in [
        'NETWORK_ERROR',
        'TIMEOUT',
        'UNEXPECTED_ERROR',
        'UPSTREAM_UNAVAILABLE',
        'OPTIMIZE_MESSAGE_SETTLEMENT_RETRYABLE',
      ]) {
        expect(
          AnalysisService.isAutoRetriableAnalysisError(
            code: code,
            hasImages: false,
            recognizeOnly: false,
            hasDurableRequestId: true,
          ),
          isTrue,
          reason: code,
        );
      }
    });

    test('非 retriable code 一律不重試', () {
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: 'QUOTA_EXCEEDED',
          hasImages: false,
          recognizeOnly: false,
          hasDurableRequestId: false,
        ),
        isFalse,
      );
      expect(
        AnalysisService.isAutoRetriableAnalysisError(
          code: null,
          hasImages: false,
          recognizeOnly: false,
          hasDurableRequestId: false,
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
