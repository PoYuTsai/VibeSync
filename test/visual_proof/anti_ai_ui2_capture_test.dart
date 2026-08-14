// Deterministic visual proof for the 2026-08-14 anti-AI-template pass #2
// （分析鏈路五畫面）。Renders to before/ or after/ depending on
// ANTI_AI_UI_STAGE, same contract as anti_ai_ui_capture_test.dart.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/analysis/data/providers/analysis_record_providers.dart';
import 'package:vibesync/features/analysis/data/repositories/analysis_record_store.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/screens/partner_analysis_records_screen.dart';
import 'package:vibesync/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/presentation/screens/new_conversation_screen.dart';

import '../helpers/memory_coaching_outcome_repository.dart';
import 'proof_support.dart';

const _stage = String.fromEnvironment('ANTI_AI_UI_STAGE');

String _stagePath(String name) => outPath('anti_ai_ui2/$_stage/$name');

class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository(this._conversation)
      : super(currentUserIdOverride: () => 'u-proof');

  final Conversation _conversation;

  @override
  Conversation? getConversation(String id) =>
      id == _conversation.id ? _conversation : null;

  @override
  List<Conversation> getAllConversations() => [_conversation];
}

/// 讀回空、寫入吞掉；harness 不驗紀錄行為，只求畫面可拍。
class _MemoryAnalysisRecordStore implements AnalysisRecordStore {
  @override
  AnalysisRecord? currentFor({
    required String ownerUserId,
    required String conversationId,
  }) =>
      null;

  @override
  AnalysisRecord? recordById({
    required String ownerUserId,
    required String conversationId,
    required String recordId,
  }) =>
      null;

  @override
  List<AnalysisRecord> listArchived({
    required String ownerUserId,
    required Iterable<String> conversationIds,
  }) =>
      const [];

  @override
  Future<bool> archiveCurrentRecord({
    required String ownerUserId,
    required String conversationId,
  }) async =>
      true;

  @override
  Future<AnalysisRecordSaveResult> saveSuccessfulAnalysis({
    required String ownerUserId,
    required Conversation conversation,
    required String completionKey,
    required int runStartPreviousCount,
    required int analyzedMessageCount,
    required String analyzedContentRevision,
    required String analysisSnapshotJson,
    required int enthusiasmScore,
    required String gameStageLabel,
    bool allowArchivedRefresh = false,
    String? sourcePlatform,
    DateTime? completedAt,
  }) async =>
      const AnalysisRecordSaveResult.rejected('proof harness');

  @override
  Future<bool> deleteRecord({
    required String ownerUserId,
    required String conversationId,
    required String recordId,
  }) async =>
      true;

  @override
  Future<int> removeConversation({
    required String ownerUserId,
    required String conversationId,
  }) async =>
      0;

  @override
  Future<bool> prepareConversationRemoval({
    required String ownerUserId,
    required String conversationId,
  }) async =>
      true;

  @override
  Future<bool> cancelConversationRemoval({
    required String ownerUserId,
    required String conversationId,
  }) async =>
      true;

  @override
  bool hasPendingConversationRemovals({required String ownerUserId}) => false;

  @override
  Future<int> recoverPendingConversationRemovals({
    required String ownerUserId,
    required Iterable<String> liveConversationIds,
  }) async =>
      0;

  @override
  String? conversationSource({
    required String ownerUserId,
    required String conversationId,
  }) =>
      null;

  @override
  Future<bool> setConversationSource({
    required String ownerUserId,
    required String conversationId,
    required String? sourcePlatform,
    bool relabelCurrent = false,
  }) async =>
      true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubCoachChatRepository implements CoachChatRepository {
  @override
  List<CoachChatResult> listByConversation(String conversationId) => const [];

  @override
  CoachChatResult? latestForConversation(String conversationId) => null;

  @override
  Future<void> put(CoachChatResult result) async {}

  @override
  Future<ConversationDeleteOutcome> deleteConversation(
    String conversationId,
  ) async =>
      const ConversationDeleteOutcome(
        deleted: true,
        deletedOwnerUserId: 'stub-owner',
      );

  @override
  Future<void> clearAll() async {}

  @override
  List<UnifiedCoachResult> listByScope(String scopeType, String scopeId) =>
      const [];

  @override
  UnifiedCoachResult? latestForScope(String scopeType, String scopeId) => null;

  @override
  Future<void> putUnified(UnifiedCoachResult result) async {}

  @override
  Future<void> deleteScope(String scopeType, String scopeId) async {}
}

Conversation _seededConversation({required bool withResult}) {
  final messages = [
    Message(
      id: 'm1',
      content: '蛤 他要去喔',
      isFromMe: false,
      timestamp: DateTime(2026, 8, 13, 21, 2),
    ),
    Message(
      id: 'm2',
      content: '對啊 我隊友臨時說要衝',
      isFromMe: true,
      timestamp: DateTime(2026, 8, 13, 21, 4),
    ),
    Message(
      id: 'm3',
      content: '就下週了',
      isFromMe: false,
      timestamp: DateTime(2026, 8, 13, 21, 6),
    ),
  ];
  final conversation = Conversation(
    id: 'proof-c1',
    name: '在',
    messages: withResult ? messages : <Message>[],
    createdAt: DateTime(2026, 8, 10),
    updatedAt: DateTime(2026, 8, 13),
    ownerUserId: 'u-proof',
  );
  if (!withResult) return conversation;

  conversation.lastAnalyzedMessageCount = messages.length;
  final snapshot = <String, dynamic>{
    'enthusiasm': {'score': 72, 'level': 'warm'},
    'strategy': 'extend',
    'dimensions': {
      'heat': 72,
      'engagement': 70,
      'topicDepth': 58,
      'replyWillingness': 76,
      'emotionalConnection': 62,
    },
    'replies': {'extend': '對啊哈哈 臨時決定的'},
    'finalRecommendation': {
      'pick': 'extend',
      'content': '',
      'reason': '這是實務協調對話，清楚回應比玩梗更重要，同時保留一點輕鬆語氣',
      'psychology': '',
      'replySegments': [
        {
          'sourceIndex': 1,
          'sourceMessage': '蛤 他要去喔',
          'reply': '對啊哈哈 臨時決定的',
          'reason': '接住她的驚訝，簡短帶過原委',
        },
        {
          'sourceIndex': 3,
          'sourceMessage': '就下週了',
          'reply': '下週那我這邊也提早喬一下',
          'reason': '回應具體時間安排，展現主動配合',
        },
      ],
    },
  };
  snapshot['__vibesync_snapshot_meta_v1'] = <String, Object>{
    'contentRevision': conversationContentRevision(
      conversation,
      messageCount: messages.length,
    ),
    'messageCount': messages.length,
  };
  conversation.lastAnalysisSnapshotJson = jsonEncode(snapshot);
  return conversation;
}

List<Override> _analysisOverrides(Conversation conversation) => [
      coachingOutcomeRepositoryProvider
          .overrideWithValue(MemoryCoachingOutcomeRepository()),
      conversationRepositoryProvider
          .overrideWithValue(_FakeConversationRepository(conversation)),
      authConversationScopeProvider.overrideWith(
        (_) => Stream.value('u-proof'),
      ),
      analysisRecordStoreProvider
          .overrideWithValue(_MemoryAnalysisRecordStore()),
      coachChatRepositoryProvider
          .overrideWithValue(_StubCoachChatRepository()),
    ];

const _recognizedForConfirm = RecognizedConversation(
  contactName: '安',
  messageCount: 3,
  summary: '識別到 3 則訊息',
  classification: 'valid_chat',
  importPolicy: 'allow',
  confidence: 'high',
  sideConfidence: 'high',
  messages: [
    RecognizedMessage(
      side: 'left',
      isFromMe: false,
      content: '[Photo of a drink bottle held in hand]',
    ),
    RecognizedMessage(
      side: 'left',
      isFromMe: false,
      content: '還好今晚也是有快樂的小事💚',
      quotedReplyPreview: '🙂 👰',
      quotedReplyPreviewIsFromMe: true,
    ),
    RecognizedMessage(
      side: 'left',
      isFromMe: false,
      content: '先去康是美～',
      quotedReplyPreview: '我回到永春啦～',
      quotedReplyPreviewIsFromMe: true,
    ),
  ],
);

void main() {
  if (_stage.isEmpty) {
    test('anti-ai-ui2 proof（需 --dart-define=ANTI_AI_UI_STAGE）', () {
      markTestSkipped('未指定 ANTI_AI_UI_STAGE，跳過產圖');
    });
    return;
  }
  setUpAll(loadProofFonts);

  testWidgets('anti-ai-ui2 ocr confirm sheet', (tester) async {
    final conversation = _seededConversation(withResult: false);
    // Dialog 開在 navigator overlay，RepaintBoundary 要包在 MaterialApp 外
    // 才拍得到——走真正 showDialog 流程。
    await tester.binding.setSurfaceSize(kPhone);
    final rootKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
          home: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'AppTC'),
            child: Scaffold(
              backgroundColor: const Color(0xFF120B1F),
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => ScreenshotRecognitionDialog(
                        recognized: _recognizedForConfirm,
                        warningMessage: '辨識到的名字和目前對象不同，請先確認是不是同一人。',
                        initialName: 'gg',
                        initialMeetingContext: null,
                        initialDuration: null,
                        initialGoal: null,
                        initialAnalysisContextNote: '',
                        currentConversation: conversation,
                        expectedPartnerName: 'gg',
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      (File(_stagePath('ocr_confirm.png'))..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('anti-ai-ui2 analysis result top', (tester) async {
    final conversation = _seededConversation(withResult: true);
    await pumpAndCapture(
      tester,
      rasterDecodeWait: const Duration(milliseconds: 600),
      child: ProviderScope(
        overrides: _analysisOverrides(conversation),
        child: const AnalysisScreen(conversationId: 'proof-c1'),
      ),
      beforeCapture: (t) async {
        await t.scrollUntilVisible(
          find.text('AI 推薦回覆').first,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
      },
      outPath: _stagePath('analysis_result_top.png'),
    );
  });

  testWidgets('anti-ai-ui2 analysis result bottom', (tester) async {
    final conversation = _seededConversation(withResult: true);
    await pumpAndCapture(
      tester,
      rasterDecodeWait: const Duration(milliseconds: 600),
      child: ProviderScope(
        overrides: _analysisOverrides(conversation),
        child: const AnalysisScreen(conversationId: 'proof-c1'),
      ),
      beforeCapture: (t) async {
        // 「分析新片段」在固定底欄、一開始就 visible，錨點要抓捲動區內的字。
        await t.scrollUntilVisible(
          find.text('複製整組訊息').first,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
      },
      outPath: _stagePath('analysis_result_bottom.png'),
    );
  });

  testWidgets('anti-ai-ui2 new segment empty', (tester) async {
    final conversation = _seededConversation(withResult: false);
    await pumpAndCapture(
      tester,
      rasterDecodeWait: const Duration(milliseconds: 600),
      child: ProviderScope(
        overrides: _analysisOverrides(conversation),
        child: const AnalysisScreen(conversationId: 'proof-c1'),
      ),
      outPath: _stagePath('new_segment_empty.png'),
    );
  });

  testWidgets('anti-ai-ui2 manual input (partner-bound)', (tester) async {
    await pumpAndCapture(
      tester,
      child: const ProviderScope(
        child: NewConversationScreen(partnerId: 'p-proof'),
      ),
      outPath: _stagePath('manual_input.png'),
    );
  });

  testWidgets('anti-ai-ui2 analysis records sheet', (tester) async {
    await pumpAndCapture(
      tester,
      child: ColoredBox(
        color: const Color(0xB7000000),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.74,
            child: PartnerAnalysisRecordsScreen(
              subjectName: 'gg',
              records: const [],
              platformForRecord: (_) => null,
              onSetMetVia: (_) {},
            ),
          ),
        ),
      ),
      outPath: _stagePath('analysis_records.png'),
    );
  });
}
