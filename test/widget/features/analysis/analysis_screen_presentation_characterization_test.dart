// Work C C0：AnalyzeChat presentation 模組化前的特徵化測試。
//
// 鎖住 AnalysisScreen 目前可觀察的 UI 行為——widget key、可見文案、
// 回覆卡張數/順序/對映、進場動畫時間軸、語意標籤——讓 C1–C4 的
// 同 commit 切換有行為證據可對拍。這些期望值描述的是「現狀」，
// 不是新規格；抽出後全部必須原樣通過。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/analysis/data/notifiers/streaming_analyze_notifier.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_recommendation_preview.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/analysis/presentation/screens/analysis_screen.dart';
import 'package:vibesync/features/analysis/presentation/widgets/reply_style_card.dart';
import 'package:vibesync/features/analysis/presentation/widgets/swipe_hint_nudge.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_usage_summary_line.dart';
import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_scope.dart';
import 'package:vibesync/features/coach_chat/domain/entities/unified_coach_result.dart';
import 'package:vibesync/features/coach_chat/domain/repositories/coach_chat_repository.dart';
import 'package:vibesync/features/coaching_memory/data/providers/coaching_outcome_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_repository.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/shared/widgets/image_picker_widget.dart';
import 'package:vibesync/shared/widgets/scroll_card_ticks.dart';

import '../../../helpers/memory_analysis_history_repository.dart';
import '../../../helpers/memory_coaching_outcome_repository.dart';

const _conversationId = 'characterization-test';

class _SeededStreamingAnalyzeNotifier extends StreamingAnalyzeNotifier {
  _SeededStreamingAnalyzeNotifier(this.seed);
  final StreamingAnalysisState seed;

  @override
  StreamingAnalysisState build(String conversationId) => seed;
}

class _InertAnalyzeStreamClient extends AnalyzeStreamClient {
  _InertAnalyzeStreamClient()
      : super(displayMapper: const AnalysisStreamContentDisplayMapper());

  @override
  Stream<AnalysisStreamUpdate> stream(AnalyzeStreamRequest request) =>
      const Stream.empty();
}

class _StubConversationRepository extends ConversationRepository {
  _StubConversationRepository(this._conversation);
  Conversation _conversation;

  @override
  Conversation? getConversation(String id) =>
      id == _conversation.id ? _conversation : null;

  @override
  Future<void> updateConversation(Conversation c) async {
    _conversation = c;
  }
}

class _MemoryConversationArchiveStore implements ConversationArchiveStore {
  final Map<String, ConversationArchiveEntry> entries = {};

  @override
  ConversationArchiveEntry? entryFor(Conversation conversation) =>
      entries[conversation.id];

  @override
  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
    String? analyzedContentRevision,
  }) async {
    entries[conversation.id] = ConversationArchiveEntry.active(
      changedAt: changedAt ?? DateTime.now(),
      contentRevision: analyzedContentRevision,
    );
  }

  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) async {}

  @override
  Future<void> remove(Conversation conversation) async {}
}

class _EmptyCoachChatRepository extends CoachChatRepository {
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
  @override
  Future<bool> deleteUnified(String id) async => false;
}

Conversation _conversation({List<Message>? messages}) {
  return Conversation(
    id: _conversationId,
    name: '小雲',
    messages: messages ??
        [
          Message(
            id: 'm1',
            content: '今天加班好累喔',
            isFromMe: false,
            timestamp: DateTime(2026, 5, 28, 12),
          ),
        ],
    createdAt: DateTime(2026, 5, 28, 12),
    updatedAt: DateTime(2026, 5, 28, 12),
  );
}

AnalysisRecommendationPreview _preview(String runId) {
  return AnalysisRecommendationPreview(
    analysisRunId: runId,
    pick: 'resonate',
    nextStep: '先接住情緒再延伸',
    recommendedReply: '聽起來累，要不要週末喝杯咖啡？',
    shortReason: '情緒先接住',
    insufficientContext: false,
    confidence: 'high',
    estimatedReportSeconds: 17,
  );
}

AnalysisResult _paidResult({
  Map<String, String>? replies,
  FinalRecommendation? recommendation,
}) {
  return AnalysisResult(
    enthusiasmScore: 72,
    strategy: '保持沉穩',
    gameStage: const GameStageInfo(
      current: GameStage.premise,
      status: GameStageStatus.normal,
      nextStep: '繼續',
    ),
    psychology: const PsychologyAnalysis(
      subtext: '有興趣',
      qualificationSignal: true,
    ),
    topicDepth: const TopicDepth(
      current: TopicDepthLevel.personal,
      suggestion: '可深入',
    ),
    replies: replies ??
        const {
          'extend': '延展回覆內容',
          'resonate': '共鳴回覆內容',
          'tease': '調情回覆內容',
          'humor': '幽默回覆內容',
          'coldRead': '冷讀回覆內容',
        },
    replyOptions: const {},
    recommendation: recommendation ??
        const FinalRecommendation(
          pick: 'tease',
          content: '調情回覆內容',
          reason: '推薦理由文案',
          psychology: '推薦心理判斷',
        ),
    reminder: '記得用你的方式說',
  );
}

StreamingAnalysisState _doneSeed(AnalysisResult result, {String? runId}) {
  final id = runId ?? 'run_char';
  return StreamingAnalysisState(
    phase: StreamingAnalyzePhase.done,
    recommendationPreview: _preview(id),
    result: result,
    analysisRunId: id,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required StreamingAnalysisState seed,
  Conversation? conversation,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final conv = conversation ?? _conversation();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachingOutcomeRepositoryProvider
            .overrideWithValue(MemoryCoachingOutcomeRepository()),
        analysisHistoryRepositoryProvider
            .overrideWithValue(MemoryAnalysisHistoryRepository()),
        conversationArchiveStoreProvider
            .overrideWithValue(_MemoryConversationArchiveStore()),
        conversationRepositoryProvider
            .overrideWithValue(_StubConversationRepository(conv)),
        conversationProvider(_conversationId).overrideWithValue(conv),
        analyzeStreamClientProvider
            .overrideWithValue(_InertAnalyzeStreamClient()),
        coachChatRepositoryProvider
            .overrideWithValue(_EmptyCoachChatRepository()),
        coachChatHistoryProvider(const CoachScope.conversation(_conversationId))
            .overrideWithValue(const []),
        streamingAnalyzeProvider
            .overrideWith(() => _SeededStreamingAnalyzeNotifier(seed)),
      ],
      child: const MaterialApp(
        home: AnalysisScreen(conversationId: _conversationId),
      ),
    ),
  );
  // initState 的 post-frame hydration callback 落地。
  await tester.pump();
  await tester.pump();
  // 詳細分析樹的既知 Hive 例外（同 hydration 測試）。
  tester.takeException();
}

/// 依畫面樹順序取出回覆卡橫列的 CardTickTarget（含推薦卡與風格卡）。
List<CardTickTarget> _replyZoneCardTargets(WidgetTester tester) {
  return tester
      .widgetList<CardTickTarget>(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-reply-zone')),
          matching: find.byType(CardTickTarget),
        ),
      )
      .toList();
}

List<String> _styleCardTypesInOrder(WidgetTester tester) {
  return tester
      .widgetList<ReplyStyleCard>(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-reply-zone')),
          matching: find.byType(ReplyStyleCard),
        ),
      )
      .map((card) => card.type)
      .toList();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('回覆區卡組：張數／順序／對映（canonical）', () {
    testWidgets('付費完整結果 pick=tease → 推薦卡在首位＋4 張風格卡（tease 併入推薦卡）',
        (tester) async {
      await _pumpScreen(tester, seed: _doneSeed(_paidResult()));

      expect(find.text('AI 推薦回覆'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('analysis-recommended-reply-card')),
        findsOneWidget,
      );

      final targets = _replyZoneCardTargets(tester);
      expect(targets.length, 5, reason: '推薦卡 1 張＋風格卡 4 張（tease 去重）');
      expect(
        targets.map((t) => t.index).toList(),
        [0, 1, 2, 3, 4],
        reason: 'stagger index 依卡序遞增',
      );

      // 首張是推薦卡。
      expect(
        find.descendant(
          of: find.byWidget(targets.first.child),
          matching: find.byKey(
            const ValueKey('analysis-recommended-reply-card'),
          ),
        ),
        findsOneWidget,
      );

      expect(
        _styleCardTypesInOrder(tester),
        ['extend', 'resonate', 'humor', 'coldRead'],
        reason: '風格卡照固定順序，推薦 pick 型別不重複出現',
      );
      for (final card in tester.widgetList<ReplyStyleCard>(
        find.byType(ReplyStyleCard),
      )) {
        expect(card.isRecommended, isFalse,
            reason: '推薦型別已併入推薦卡，其餘風格卡不得標記推薦');
      }

      // 多於一張卡 → 顯示橫滑提示。
      expect(find.byType(SwipeHintChip), findsOneWidget);
      // 單段推薦內容 → 整段複製按鈕與再調一下。
      expect(find.text('複製推薦回覆'), findsOneWidget);
      expect(find.text('再調一下'), findsWidgets);
      // 推薦理由與心理判斷都渲染。
      expect(find.text('推薦理由文案'), findsOneWidget);
      expect(find.text('推薦心理判斷'), findsOneWidget);
    });

    testWidgets('免費結果（extend+tease，pick=extend）→ 推薦卡＋1 張風格卡',
        (tester) async {
      final result = _paidResult(
        replies: const {
          'extend': '免費延展回覆',
          'tease': '免費調情回覆',
        },
        recommendation: const FinalRecommendation(
          pick: 'extend',
          content: '免費延展回覆',
          reason: '免費理由',
          psychology: '免費心理',
        ),
      );
      await _pumpScreen(tester, seed: _doneSeed(result));

      final targets = _replyZoneCardTargets(tester);
      expect(targets.length, 2);
      expect(_styleCardTypesInOrder(tester), ['tease']);
      expect(find.byType(SwipeHintChip), findsOneWidget);
      // 免費層回覆區尾端顯示升級提示。
      expect(
        find.textContaining('升級解鎖共鳴、幽默、冷讀等完整 5 種風格'),
        findsOneWidget,
      );
    });

    testWidgets('pick 不在回覆鍵內 → 不去重，推薦卡＋5 張風格卡', (tester) async {
      final result = _paidResult(
        recommendation: const FinalRecommendation(
          pick: 'unknownStyle',
          content: '推薦內容獨立存在',
          reason: '理由',
          psychology: '心理',
        ),
      );
      await _pumpScreen(tester, seed: _doneSeed(result));

      expect(_replyZoneCardTargets(tester).length, 6);
      expect(
        _styleCardTypesInOrder(tester),
        ['extend', 'resonate', 'tease', 'humor', 'coldRead'],
      );
    });

    testWidgets('推薦內容為空 → 無推薦卡，pick 型別風格卡標記推薦', (tester) async {
      final result = _paidResult(
        recommendation: const FinalRecommendation(
          pick: 'tease',
          content: '',
          reason: '',
          psychology: '',
        ),
      );
      await _pumpScreen(tester, seed: _doneSeed(result));

      expect(
        find.byKey(const ValueKey('analysis-recommended-reply-card')),
        findsNothing,
      );
      final types = _styleCardTypesInOrder(tester);
      expect(types, ['extend', 'resonate', 'tease', 'humor', 'coldRead']);
      final teaseCard = tester
          .widgetList<ReplyStyleCard>(find.byType(ReplyStyleCard))
          .firstWhere((card) => card.type == 'tease');
      expect(teaseCard.isRecommended, isTrue);
    });
  });

  group('回覆區進場動畫時間軸', () {
    testWidgets('570ms stagger：起始末卡透明，跑完全部落定', (tester) async {
      await _pumpScreen(tester, seed: _doneSeed(_paidResult()));

      FadeTransition nearestFade(Widget of) => tester.widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byWidget(of),
                  matching: find.byType(FadeTransition),
                )
                .first,
          );

      final targets = _replyZoneCardTargets(tester);
      // 進場剛開始：最後一張卡的 stagger fade 尚未升到 1。
      final lastEarly = nearestFade(targets.last.child).opacity.value;
      expect(lastEarly, lessThan(1.0), reason: '末卡 stagger 延遲 4×50ms 起跑');

      await tester.pump(const Duration(milliseconds: 570));
      for (final target in _replyZoneCardTargets(tester)) {
        expect(nearestFade(target.child).opacity.value, 1.0,
            reason: '總時間軸 570ms 後全部卡落定');
      }
    });
  });

  group('詳細分析折疊', () {
    testWidgets('預設收起，點擊展開；語意標籤與 pill 對映', (tester) async {
      await _pumpScreen(tester, seed: _doneSeed(_paidResult()));

      Finder toggleSemantics(String label) => find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == label,
          );

      expect(find.text('詳細分析'), findsOneWidget);
      expect(find.text('展開'), findsOneWidget);
      expect(find.text('收起'), findsNothing);
      expect(toggleSemantics('展開詳細分析'), findsOneWidget);
      expect(find.text('本次投入 72'), findsOneWidget);

      // 折疊卡在長捲動內容深處；直接觸發 GestureDetector.onTap，
      // 避免捲動視窗命中不穩造成假紅。
      tester
          .widget<GestureDetector>(
            find
                .ancestor(
                  of: find.text('詳細分析'),
                  matching: find.byType(GestureDetector),
                )
                .first,
          )
          .onTap!();
      await tester.pump();
      tester.takeException();

      expect(find.text('收起'), findsOneWidget);
      expect(toggleSemantics('收起詳細分析'), findsOneWidget);
      expect(find.text('她話裡的意思'), findsOneWidget);
      expect(find.text('有興趣'), findsOneWidget);
      expect(find.text('保持沉穩'), findsOneWidget);
      expect(find.textContaining('話題深度:'), findsOneWidget);
    });
  });

  group('反饋區', () {
    testWidgets('倒讚展開表單：分類 chips 與說明文案', (tester) async {
      await _pumpScreen(tester, seed: _doneSeed(_paidResult()));

      expect(find.text('這個建議有幫助嗎？'), findsOneWidget);
      // 倒讚 IconButton 深藏在長捲動內容底部；直接觸發 onPressed，
      // 避免捲動視窗邊緣命中不穩造成假紅。
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.thumb_down_outlined),
          )
          .onPressed!();
      await tester.pump();
      tester.takeException();

      expect(find.text('哪裡需要改進？'), findsOneWidget);
      for (final label in ['太直接', '不自然', '回覆太長', '不符合我的風格', '其他']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('預設只送評分類別與結構化分析資訊，不附原始對話。'), findsOneWidget);
      expect(find.text('送出反饋'), findsOneWidget);
      expect(
        find.text('附上最後 6 則對話片段，幫助我們排查（選填）'),
        findsOneWidget,
      );
    });
  });

  group('完成結果畫面固定表面', () {
    testWidgets('草稿潤飾入口、問教練 CTA、額度摘要列、一致性提醒', (tester) async {
      await _pumpScreen(tester, seed: _doneSeed(_paidResult()));

      expect(find.byKey(const ValueKey('draft-polish-entry')), findsOneWidget);
      expect(find.text('我已有草稿，幫我修自然'), findsOneWidget);
      expect(find.byKey(const Key('analysis_coach_cta')), findsOneWidget);
      expect(find.byType(AnalysisUsageSummaryLine), findsOneWidget);
      expect(find.text('記得用你的方式說'), findsOneWidget);
      expect(find.text('問教練：我現在該怎麼做？'), findsOneWidget);
      expect(find.text('分析新片段'), findsOneWidget);
    });
  });

  group('串流內容卡', () {
    testWidgets('streamingReport 內容項與 icon 對映', (tester) async {
      final seed = StreamingAnalysisState(
        phase: StreamingAnalyzePhase.streamingReport,
        recommendationPreview: _preview('run_stream_char'),
        analysisRunId: 'run_stream_char',
        streamProgressLabel: '整理語意重點',
        streamContents: const [
          AnalysisStreamContent(
            kind: AnalysisStreamContentKind.decision,
            title: '下一步策略',
            body: '先承接情緒，再自然延伸。',
            rawEvent: {'type': 'analysis.decision'},
          ),
          AnalysisStreamContent(
            kind: AnalysisStreamContentKind.replyOption,
            title: '回覆選項',
            body: '直接關心她的疲累。',
            rawEvent: {'type': 'analysis.reply_option'},
          ),
        ],
      );
      await _pumpScreen(tester, seed: seed);

      expect(find.text('完整分析即時整理中'), findsOneWidget);
      // 進度標籤同時渲染在 StreamingAnalysisLoader 與串流卡標頭。
      expect(find.text('整理語意重點'), findsNWidgets(2));
      expect(find.text('下一步策略'), findsOneWidget);
      expect(find.text('先承接情緒，再自然延伸。'), findsOneWidget);
      expect(find.byIcon(Icons.route_outlined), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsWidgets);
    });
  });

  group('空片段起始畫面', () {
    testWidgets('截圖小提醒、選圖入口與價值主張', (tester) async {
      await _pumpScreen(
        tester,
        seed: StreamingAnalysisState(phase: StreamingAnalyzePhase.idle),
        conversation: _conversation(messages: const []),
      );

      expect(find.text('還沒有訊息'), findsOneWidget);
      expect(
        find.text('先上傳 1–3 張聊天截圖，確認文字後作為本次片段。'),
        findsOneWidget,
      );
      expect(find.byType(ImagePickerWidget), findsOneWidget);
      expect(find.text('截圖小提醒'), findsOneWidget);
      expect(find.text('請保留標題列、訊息泡泡與前後文'), findsOneWidget);
      expect(find.text('每張建議 15 則內；過長可拆成 2-3 張'), findsOneWidget);
      expect(
        find.text('AI 會分析對方投入度、讀懂語意，教你最適合的回覆方式'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('analysis-source-pill')), findsOneWidget);
    });
  });
}
