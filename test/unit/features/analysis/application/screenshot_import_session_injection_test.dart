// 注入回歸：ScreenshotImportCoordinator 與 AnalysisSessionController
// 只透過具名注入的依賴工作（不碰 Riverpod、不反向依賴 presentation）。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/application/analysis_persistence_coordinator.dart';
import 'package:vibesync/features/analysis/application/analysis_session_controller.dart';
import 'package:vibesync/features/analysis/application/screenshot_import_coordinator.dart';
import 'package:vibesync/features/analysis/application/ports/analysis_record_port.dart'
    show AnalysisRecordPort;
import 'package:vibesync/features/analysis/application/ports/screenshot_recognition_ports.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/streaming_analysis_state.dart';
import 'package:vibesync/features/conversation/domain/services/conversation_content_revision.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
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
  required List<Conversation> saved,
  required List<int> invalidations,
  Partner? Function(String partnerId)? partnerById,
}) {
  return ScreenshotImportCoordinator(
    conversationId: _conversationId,
    getConversation: (id) => id == conversation.id ? conversation : null,
    createConversation: ({required name, required messages, partnerId}) =>
        throw UnimplementedError('replace-batch path must not create'),
    saveConversation: (conv) async => saved.add(conv),
    partnerById: partnerById ?? (_) => null,
    recognizeScreenshots: ({
      required images,
      sessionContext,
      knownContactName,
      onProgress,
      onTelemetry,
    }) =>
        throw UnimplementedError('commit/partner paths must not recognize'),
    recognitionCache: _ThrowingRecognitionCache(),
    invalidateConversationProvider: () => invalidations.add(1),
  );
}

class _ThrowingRecordPort implements AnalysisRecordPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('record port must not be hit');
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
        saved: [],
        invalidations: [],
        partnerById: (id) => id == 'p-1' ? partner : null,
      );

      expect(
        coordinator.expectedPartnerName(_conversation(partnerId: 'p-1')),
        '小美',
      );
      expect(coordinator.expectedPartnerName(_conversation()), isNull);
    });

    test('commitImport 取代本次片段：經注入的 save 落地、觸發 provider 失效', () async {
      final conversation = _conversation();
      final saved = <Conversation>[];
      final invalidations = <int>[];
      final coordinator = _importCoordinator(
        conversation: conversation,
        saved: saved,
        invalidations: invalidations,
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
      expect(saved.single.id, _conversationId);
      // 佔位名 + 未綁 partner → 以輸入的名字取代。
      expect(saved.single.name, '阿花');
      // 整批取代：一次 OCR 選取就是完整的一個待分析片段。
      expect(
        saved.single.messages.map((message) => message.content).toList(),
        ['嗨', '哈囉'],
      );
      expect(invalidations, hasLength(1));
    });
  });

  group('AnalysisSessionController（具名注入）', () {
    AnalysisSessionController controller(Conversation? Function() current) {
      return AnalysisSessionController(
        conversationId: _conversationId,
        startRun: ({
          required messages,
          sessionContext,
          conversationSummary,
          partnerSummary,
          effectiveStyleContext,
          knownContactName,
          previousAnalyzedCount,
          previousAnalyzedCharCount,
          confirmedOvercharge,
          conversationMessageCount,
          analyzedMessageCount,
          conversationContentRevision,
        }) =>
            throw UnimplementedError('not used here'),
        retryRun: () => throw UnimplementedError('not used here'),
        ensureServerEntitlementSynced: () async {},
        currentConversation: current,
        persistence: AnalysisPersistenceCoordinator(
          conversationId: _conversationId,
          getConversation: (_) => null,
          persistAnalysisCompleted: (_,
              {required expectedContentRevision}) async {},
          persistContentChanged: (_) async {},
          markConversationActive: (_) async {},
          archiveMarkerFor: (_) => null,
          recordPort: _ThrowingRecordPort(),
          currentRecordOwnerUserId: () => null,
          historyRepository: () => throw UnimplementedError('not used here'),
          trackFunnelOnce: (_) async {},
          lastPayloadCharCount: () => null,
          notifyStateChanged: () {},
          invalidateRecordViews: (_) {},
          afterAnalysisPersisted: (_) async {},
        ),
      );
    }

    test('staleness：以注入的 currentConversation 比對 contentRevision', () {
      final conversation = _conversation();
      final session = controller(() => conversation);

      expect(
        session.isResultStaleForCurrentConversation(
          StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            conversationContentRevision:
                conversationContentRevision(conversation),
          ),
        ),
        isFalse,
      );
      expect(
        session.isResultStaleForCurrentConversation(
          const StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            conversationContentRevision: 'edited-away',
          ),
        ),
        isTrue,
      );
    });

    test('staleness：舊 state 無修訂時退回訊息數比對', () {
      final session = controller(_conversation);

      expect(
        session.isResultStaleForCurrentConversation(
          const StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            conversationMessageCount: 1,
          ),
        ),
        isFalse,
      );
      expect(
        session.isResultStaleForCurrentConversation(
          const StreamingAnalysisState(
            phase: StreamingAnalyzePhase.done,
            conversationMessageCount: 3,
          ),
        ),
        isTrue,
      );
    });
  });
}
