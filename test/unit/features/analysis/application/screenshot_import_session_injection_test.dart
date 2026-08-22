// 注入回歸：ScreenshotImportCoordinator 只透過具名注入的依賴工作
//（不碰 Riverpod、不反向依賴 presentation）。匯入落地走單一深 write
// operation（save＋freshness 的 exactly-once 語意由
// imported_conversation_writer_test 驗證）；OCR 辨識的快取命中／未命中
// ／強制重讀、135s 圍籬與 progress/telemetry 等價在本檔驗證。
// session controller 的 narrow run seam 行為在
// analysis_session_run_seam_test.dart。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/application/screenshot_import_coordinator.dart';
import 'package:vibesync/features/analysis/application/ports/screenshot_recognition_ports.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_telemetry.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

const _conversationId = 'inject-conv';

Conversation _conversation({String name = '新對話', String? partnerId}) {
  return Conversation(
    id: _conversationId,
    name: name,
    messages: [
      Message(
        id: 'm1',
        content: '今天加班好累喔',
        isFromMe: false,
        timestamp: DateTime(2026, 5, 28, 12),
      ),
    ],
    createdAt: DateTime(2026, 5, 28, 12),
    updatedAt: DateTime(2026, 5, 28, 12),
    partnerId: partnerId,
  );
}

ScreenshotImportCoordinator _importCoordinator({
  required Conversation conversation,
  required List<Conversation> persisted,
  Partner? Function(String partnerId)? partnerById,
  RecognizeScreenshots? recognizeScreenshots,
  OcrRecognitionCachePort? recognitionCache,
}) {
  return ScreenshotImportCoordinator(
    conversationId: _conversationId,
    getConversation: (id) => id == conversation.id ? conversation : null,
    createConversation: ({required name, required messages, partnerId}) =>
        throw UnimplementedError('replace-batch path must not create'),
    persistImportedConversation: (conv) async => persisted.add(conv),
    partnerById: partnerById ?? (_) => null,
    recognizeScreenshots: recognizeScreenshots ??
        ({
          required images,
          sessionContext,
          knownContactName,
          onProgress,
          onTelemetry,
        }) =>
            throw UnimplementedError('commit/partner paths must not recognize'),
    recognitionCache: recognitionCache ?? _ThrowingRecognitionCache(),
  );
}

SessionContext _sessionContext() => SessionContext(
      meetingContext: MeetingContext.datingApp,
      duration: AcquaintanceDuration.justMet,
      goal: UserGoal.dateInvite,
    );

class _RecordingRecognitionCache implements OcrRecognitionCachePort {
  _RecordingRecognitionCache({required this.cached});

  final RecognizedConversation? cached;
  int invalidates = 0;
  int reads = 0;
  final writes = <RecognizedConversation>[];

  @override
  Future<void> invalidate(images, String conversationId) async {
    invalidates++;
  }

  @override
  Future<RecognizedConversation?> read(images, String conversationId) async {
    reads++;
    return cached;
  }

  @override
  Future<void> write({
    required images,
    required RecognizedConversation recognizedConversation,
    required String conversationId,
  }) async {
    writes.add(recognizedConversation);
  }
}

class _ThrowingRecognitionCache implements OcrRecognitionCachePort {
  @override
  Future<void> invalidate(images, String conversationId) =>
      throw UnimplementedError('cache must not be hit');

  @override
  Future<RecognizedConversation?> read(images, String conversationId) =>
      throw UnimplementedError('cache must not be hit');

  @override
  Future<void> write({
    required images,
    required RecognizedConversation recognizedConversation,
    required String conversationId,
  }) =>
      throw UnimplementedError('cache must not be hit');
}

void main() {
  group('ScreenshotImportCoordinator（具名注入）', () {
    test('expectedPartnerName 走注入的 partnerById，不再依賴 presentation provider', () {
      final partner = Partner(
        id: 'p-1',
        name: ' 小美 ',
        createdAt: DateTime(2026, 5, 28),
        updatedAt: DateTime(2026, 5, 28),
      );
      final coordinator = _importCoordinator(
        conversation: _conversation(partnerId: 'p-1'),
        persisted: [],
        partnerById: (id) => id == 'p-1' ? partner : null,
      );

      expect(
        coordinator.expectedPartnerName(_conversation(partnerId: 'p-1')),
        '小美',
      );
      expect(coordinator.expectedPartnerName(_conversation()), isNull);
    });

    test('commitImport 取代本次片段：經注入的深 write operation 恰好落地一次', () async {
      final conversation = _conversation();
      final persisted = <Conversation>[];
      final coordinator = _importCoordinator(
        conversation: conversation,
        persisted: persisted,
      );

      final commit = await coordinator.commitImport(
        editedRecognizedMessages: const [
          RecognizedMessage(content: '嗨', isFromMe: false),
          RecognizedMessage(content: '哈囉', isFromMe: true),
        ],
        newName: '阿花',
        meeting: null,
        duration: null,
        goal: null,
        analysisContextNote: null,
        recognized: const RecognizedConversation(
          messageCount: 2,
          summary: '兩則',
        ),
        hasLoadedAnalysisResult: false,
      );

      expect(commit.kind, ScreenshotImportCommitKind.replacedBatch);
      expect(commit.updatedRecognized?.contactName, '阿花');
      expect(persisted.single.id, _conversationId);
      // 佔位名 + 未綁 partner → 以輸入的名字取代。
      expect(persisted.single.name, '阿花');
      // 整批取代：一次 OCR 選取就是完整的一個待分析片段。
      expect(
        persisted.single.messages.map((message) => message.content).toList(),
        ['嗨', '哈囉'],
      );
    });

    test('commitImport：對話缺席回 conversationMissing，深 write 不得被觸發', () async {
      final persisted = <Conversation>[];
      final coordinator = ScreenshotImportCoordinator(
        conversationId: _conversationId,
        getConversation: (_) => null,
        createConversation: ({required name, required messages, partnerId}) =>
            throw UnimplementedError('missing path must not create'),
        persistImportedConversation: (conv) async => persisted.add(conv),
        partnerById: (_) => null,
        recognizeScreenshots: ({
          required images,
          sessionContext,
          knownContactName,
          onProgress,
          onTelemetry,
        }) =>
            throw UnimplementedError('missing path must not recognize'),
        recognitionCache: _ThrowingRecognitionCache(),
      );

      final commit = await coordinator.commitImport(
        editedRecognizedMessages: const [
          RecognizedMessage(content: '嗨', isFromMe: false),
        ],
        newName: '阿花',
        meeting: null,
        duration: null,
        goal: null,
        analysisContextNote: null,
        recognized:
            const RecognizedConversation(messageCount: 1, summary: '一則'),
        hasLoadedAnalysisResult: false,
      );

      expect(commit.kind, ScreenshotImportCommitKind.conversationMissing);
      expect(persisted, isEmpty);
    });
  });

  group('recognize（快取／圍籬／telemetry 等價）', () {
    RecognizedConversation recognized({String name = '小美'}) =>
        RecognizedConversation(
          contactName: name,
          messageCount: 1,
          summary: '一則',
          messages: const [RecognizedMessage(content: '嗨', isFromMe: false)],
        );

    AnalysisResult recognizeResult() => AnalysisResult.fromJson({
          'recognizedConversation': recognized().toJson(),
        });

    test('快取命中：不打網路、合成 cacheHit telemetry、fromCache=true', () async {
      final cache = _RecordingRecognitionCache(cached: recognized());
      final telemetry = <AnalysisTelemetry>[];
      final coordinator = _importCoordinator(
        conversation: _conversation(),
        persisted: [],
        recognitionCache: cache,
        recognizeScreenshots: ({
          required images,
          sessionContext,
          knownContactName,
          onProgress,
          onTelemetry,
        }) =>
            throw UnimplementedError('cache hit must not hit network'),
      );

      final outcome = await coordinator.recognize(
        images: [
          Uint8List.fromList([1])
        ],
        conversation: _conversation(),
        sessionContext: _sessionContext(),
        forceRefresh: false,
        totalCompressedImageBytes: 77,
        onTelemetry: telemetry.add,
      );

      expect(outcome.fromCache, isTrue);
      expect(outcome.result.recognizedConversation?.contactName, '小美');
      expect(cache.invalidates, 0);
      expect(cache.reads, 1);
      expect(cache.writes, isEmpty);
      expect(telemetry.single.cacheHit, isTrue);
      expect(telemetry.single.totalCompressedImageBytes, 77);
      expect(telemetry.single.requestType, 'recognize_only');
    });

    test('快取未命中：打一次網路、成功結果回寫快取、fromCache=false', () async {
      final cache = _RecordingRecognitionCache(cached: null);
      var recognizeCalls = 0;
      final coordinator = _importCoordinator(
        conversation: _conversation(),
        persisted: [],
        recognitionCache: cache,
        recognizeScreenshots: ({
          required images,
          sessionContext,
          knownContactName,
          onProgress,
          onTelemetry,
        }) async {
          recognizeCalls++;
          return recognizeResult();
        },
      );

      final outcome = await coordinator.recognize(
        images: [
          Uint8List.fromList([1])
        ],
        conversation: _conversation(),
        sessionContext: _sessionContext(),
        forceRefresh: false,
        totalCompressedImageBytes: 0,
      );

      expect(outcome.fromCache, isFalse);
      expect(recognizeCalls, 1);
      expect(cache.reads, 1);
      expect(cache.writes.single.contactName, '小美');
    });

    test('強制重讀：先失效快取、跳過讀取、直接打網路', () async {
      final cache = _RecordingRecognitionCache(cached: recognized());
      var recognizeCalls = 0;
      final coordinator = _importCoordinator(
        conversation: _conversation(),
        persisted: [],
        recognitionCache: cache,
        recognizeScreenshots: ({
          required images,
          sessionContext,
          knownContactName,
          onProgress,
          onTelemetry,
        }) async {
          recognizeCalls++;
          return recognizeResult();
        },
      );

      await coordinator.recognize(
        images: [
          Uint8List.fromList([1])
        ],
        conversation: _conversation(),
        sessionContext: _sessionContext(),
        forceRefresh: true,
        totalCompressedImageBytes: 0,
      );

      expect(cache.invalidates, 1);
      expect(cache.reads, 0);
      expect(recognizeCalls, 1);
    });

    test('網路結果沒有辨識內容：不回寫快取', () async {
      final cache = _RecordingRecognitionCache(cached: null);
      final coordinator = _importCoordinator(
        conversation: _conversation(),
        persisted: [],
        recognitionCache: cache,
        recognizeScreenshots: ({
          required images,
          sessionContext,
          knownContactName,
          onProgress,
          onTelemetry,
        }) async =>
            const AnalysisResult(
          enthusiasmScore: 0,
          strategy: '',
          gameStage: GameStageInfo(
            current: GameStage.opening,
            status: GameStageStatus.normal,
            nextStep: '',
          ),
          psychology: PsychologyAnalysis(subtext: ''),
          topicDepth: TopicDepth(
            current: TopicDepthLevel.event,
            suggestion: '',
          ),
          replies: {},
          replyOptions: {},
          recommendation: FinalRecommendation(
            pick: 'extend',
            content: '',
            reason: '',
            psychology: '',
          ),
        ),
      );

      await coordinator.recognize(
        images: [
          Uint8List.fromList([1])
        ],
        conversation: _conversation(),
        sessionContext: _sessionContext(),
        forceRefresh: false,
        totalCompressedImageBytes: 0,
      );

      expect(cache.writes, isEmpty);
    });

    test('progress／telemetry callback 原樣傳遞給傳輸呼叫', () async {
      final cache = _RecordingRecognitionCache(cached: null);
      AnalysisProgressCallback? seenProgress;
      AnalysisTelemetryCallback? seenTelemetry;
      void progress(AnalysisProgressUpdate update) {}
      void telemetry(AnalysisTelemetry value) {}

      final coordinator = _importCoordinator(
        conversation: _conversation(),
        persisted: [],
        recognitionCache: cache,
        recognizeScreenshots: ({
          required images,
          sessionContext,
          knownContactName,
          onProgress,
          onTelemetry,
        }) async {
          seenProgress = onProgress;
          seenTelemetry = onTelemetry;
          return recognizeResult();
        },
      );

      await coordinator.recognize(
        images: [
          Uint8List.fromList([1])
        ],
        conversation: _conversation(),
        sessionContext: _sessionContext(),
        forceRefresh: false,
        totalCompressedImageBytes: 0,
        onProgress: progress,
        onTelemetry: telemetry,
      );

      expect(identical(seenProgress, progress), isTrue);
      expect(identical(seenTelemetry, telemetry), isTrue);
    });

    testWidgets('135s 畫面圍籬：傳輸永不回應時拋 TimeoutException', (tester) async {
      final cache = _RecordingRecognitionCache(cached: null);
      final coordinator = _importCoordinator(
        conversation: _conversation(),
        persisted: [],
        recognitionCache: cache,
        recognizeScreenshots: ({
          required images,
          sessionContext,
          knownContactName,
          onProgress,
          onTelemetry,
        }) =>
            Completer<AnalysisResult>().future,
      );

      Object? caught;
      final future = coordinator.recognize(
        images: [
          Uint8List.fromList([1])
        ],
        conversation: _conversation(),
        sessionContext: _sessionContext(),
        forceRefresh: false,
        totalCompressedImageBytes: 0,
      ).catchError((Object error) {
        caught = error;
        return (
          result: AnalysisResult.fromJson({
            'recognizedConversation': recognized().toJson(),
          }),
          fromCache: false,
        );
      });

      await tester.pump(const Duration(seconds: 134));
      expect(caught, isNull, reason: '圍籬不得早於 135 秒觸發');
      await tester.pump(const Duration(seconds: 2));
      await future;
      expect(caught, isA<TimeoutException>());
    });
  });
}
