// 最低 App 版本閘門（Eric 2026-10-18）：伺服器回 426＋APP_UPDATE_REQUIRED，或
// 沒帶 clientBuild 時串流回一則同代碼的 analysis.error，App 都要變成「只能
// 更新」：不是內容錯誤、不給重試、不自動接續。
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/data/services/analysis_transport_support.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

const _gateMessage = '這個版本已經停止支援，請到 App Store 更新到最新版。';

Message _msg(String content) {
  return Message(
    id: content,
    content: content,
    isFromMe: false,
    timestamp: DateTime(2026, 10, 18, 12),
  );
}

void _expectUpdateRequired(Object error) {
  expect(error, isA<AppUpdateRequiredException>());
  expect(error, isNot(isA<StreamModeException>()));
  final exception = error as AnalysisException;
  expect(exception.code, 'APP_UPDATE_REQUIRED');
  expect(exception.suggestedAction, AnalysisErrorAction.updateApp);
  expect(exception.message, _gateMessage);
}

AnalyzeStreamClient _streamClient(http.Response response) {
  return AnalyzeStreamClient(
    displayMapper: const AnalysisStreamContentDisplayMapper(),
    clientFactory: () => MockClient((_) async => response),
    accessTokenProvider: () => 'fake-token',
    expectedTierProvider: () => null,
    revenueCatAppUserIdProvider: () async => null,
    clientBuildProvider: () async => 339,
  );
}

Future<Object> _streamError(http.Response response) async {
  try {
    await _streamClient(response)
        .stream(AnalyzeStreamRequest(messages: [_msg('今天好累喔')]))
        .toList();
  } catch (error) {
    return error;
  }
  fail('expected the stream to fail');
}

/// 一開始就丟出指定錯誤，不送任何事件（閘門擋在任何工作之前）。
class _ThrowingStreamClient extends AnalyzeStreamClient {
  _ThrowingStreamClient(this.error)
      : super(displayMapper: const AnalysisStreamContentDisplayMapper());

  final Exception error;
  int calls = 0;

  @override
  Stream<AnalysisStreamUpdate> stream(AnalyzeStreamRequest request) async* {
    calls++;
    throw error;
  }
}

void main() {
  group('mapAnalysisHttpError', () {
    test('426 一律對到「只能更新」，不看草稿／截圖旗標、不當內容錯誤', () {
      for (final hasImages in [false, true]) {
        for (final hasUserDraft in [false, true]) {
          final error = mapAnalysisHttpError(
            statusCode: 426,
            errorCode: 'APP_UPDATE_REQUIRED',
            rawMessage: _gateMessage,
            hasImages: hasImages,
            recognizeOnly: false,
            hasUserDraft: hasUserDraft,
            hasRefineInstruction: false,
          );
          _expectUpdateRequired(error);
          expect(error.message, isNot(contains('內容有誤')));
        }
      }
    });
  });

  group('AnalyzeStreamClient', () {
    test('426＋APP_UPDATE_REQUIRED → 只能更新，不是可重試的串流錯誤', () async {
      _expectUpdateRequired(
        await _streamError(
          http.Response(
            jsonEncode({
              'error': _gateMessage,
              'code': 'APP_UPDATE_REQUIRED',
              'message': _gateMessage,
              'shouldChargeQuota': false,
            }),
            426,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
    });

    test('串流 analysis.error 帶 APP_UPDATE_REQUIRED → 同樣只能更新（就算標成可接續）', () async {
      for (final recoverable in [false, true]) {
        _expectUpdateRequired(
          await _streamError(
            http.Response.bytes(
              utf8.encode(jsonEncode({
                'type': 'analysis.error',
                'code': 'APP_UPDATE_REQUIRED',
                'message': _gateMessage,
                'recoverable': recoverable,
                'retriesRemaining': 0,
              })),
              200,
              headers: {'content-type': 'application/x-ndjson'},
            ),
          ),
        );
      }
    });
  });

  group('AnalysisAuxiliaryClient', () {
    test('輔助入口目前不擋；萬一收到 426 也對到只能更新、不自動重送', () async {
      var calls = 0;
      final client = AnalysisAuxiliaryClient(
        clientFactory: () => MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({'code': 'APP_UPDATE_REQUIRED', 'error': _gateMessage}),
            426,
            headers: {'content-type': 'application/json'},
          );
        }),
        accessTokenProvider: () => 'fake-token',
        expectedTierProvider: () => null,
        revenueCatAppUserIdProvider: () async => null,
        clientBuildProvider: () async => 339,
      );
      Object? caught;
      try {
        await client.optimizeDraft(
          messages: [_msg('最近有空嗎？')],
          userDraft: '要不要喝咖啡',
          requestId: '123e4567-e89b-42d3-a456-426614174000',
        );
      } catch (error) {
        caught = error;
      }
      _expectUpdateRequired(caught!);
      expect(calls, 1);
    });
  });

  group('StreamingAnalyzeNotifier', () {
    test('被擋 → 新分析失敗、帶 APP_UPDATE_REQUIRED、不自動接續、沒有重試次數', () async {
      final fake = _ThrowingStreamClient(AppUpdateRequiredException());
      final container = ProviderContainer(overrides: [
        analyzeStreamClientProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      await container
          .read(streamingAnalyzeProvider('conv-1').notifier)
          .start(messages: [_msg('今天好累喔')]);

      final state = container.read(streamingAnalyzeProvider('conv-1'));
      expect(state.phase, StreamingAnalyzePhase.failedBeforeRecommendation);
      expect(state.recommendationPreviewErrorCode, 'APP_UPDATE_REQUIRED');
      expect(state.recommendationPreviewErrorMessage, _gateMessage);
      expect(state.retriesRemaining, 0);
      expect(state.quotaExceeded, isNull);
      expect(state.analysisRunId, isNull);
      expect(fake.calls, 1);
    });
  });
}
