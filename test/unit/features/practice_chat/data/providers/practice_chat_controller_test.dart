import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_draw_draft_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_pending_draw_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_pending_hint_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_draw_draft.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_hint.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_learning_mode.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_profile.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_temperature.dart';

import '../../../../../helpers/memory_analysis_history_repository.dart';

class _FakeApi extends PracticeChatApiService {
  Future<PracticeChatReply> Function(
    List<PracticeTurnDto> turns, {
    PracticeProfileDto? profile,
  })? sendHandler;
  Future<PracticeHintResult> Function(
    List<PracticeTurnDto> turns, {
    PracticeProfileDto? profile,
  })? hintHandler;
  Future<PracticeDebrief> Function(
    List<PracticeTurnDto> turns, {
    PracticeProfileDto? profile,
  })? debriefHandler;
  Future<PracticeDrawResult> Function({String? currentProfileId})? drawHandler;

  // 續玩 metadata 捕捉。
  int? lastRoundIndex;
  String? lastVisibleThreadId;
  PracticeLearningMode? lastPracticeMode;
  int? lastTemperatureScore;
  int? lastFamiliarityScore;
  String? lastMemorySummary;
  String? lastHintMemorySummary;
  String? lastDebriefMemorySummary;
  PracticePartnerState? lastContinuationPartnerState;
  PracticePartnerState? lastHintContinuationPartnerState;
  PracticePartnerState? lastDebriefContinuationPartnerState;
  PracticeHintReplyType? lastAppliedHintType;
  String? lastAppliedHintText;
  List<PracticeAppliedHintTurnDto>? lastDebriefAppliedHintTurns;
  int? lastDebriefRoundIndex;
  String? lastDebriefThreadId;
  int? lastHintRoundIndex;
  String? lastHintThreadId;
  String? lastHintRequestId;
  PracticeLearningMode? lastHintPracticeMode;
  int hintCallCount = 0;

  // 翻牌捕捉。
  int drawCallCount = 0;
  String? lastDrawRequestId;
  String? lastDrawCurrentProfileId;
  String? lastDrawVisibleThreadId;

  @override
  Future<PracticeChatReply> sendMessage({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    PracticeLearningMode practiceMode = PracticeLearningMode.standard,
    int? temperatureScore,
    int? familiarityScore,
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
    PracticeHintReplyType? appliedHintType,
    String? appliedHintText,
  }) {
    lastRoundIndex = roundIndex;
    lastVisibleThreadId = visiblePracticeThreadId;
    lastPracticeMode = practiceMode;
    lastTemperatureScore = temperatureScore;
    lastFamiliarityScore = familiarityScore;
    lastMemorySummary = memorySummary;
    lastContinuationPartnerState = continuationPartnerState;
    lastAppliedHintType = appliedHintType;
    lastAppliedHintText = appliedHintText;
    return sendHandler!(turns, profile: profile);
  }

  @override
  Future<PracticeHintResult> requestHint({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
    String? requestId,
    PracticeLearningMode practiceMode = PracticeLearningMode.beginner,
  }) {
    hintCallCount++;
    lastHintRoundIndex = roundIndex;
    lastHintThreadId = visiblePracticeThreadId;
    lastHintMemorySummary = memorySummary;
    lastHintContinuationPartnerState = continuationPartnerState;
    lastHintRequestId = requestId;
    lastHintPracticeMode = practiceMode;
    return hintHandler!(turns, profile: profile);
  }

  @override
  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    PracticeLearningMode practiceMode = PracticeLearningMode.standard,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
    List<PracticeAppliedHintTurnDto> appliedHintTurns = const [],
  }) {
    lastDebriefRoundIndex = roundIndex;
    lastDebriefThreadId = visiblePracticeThreadId;
    lastDebriefMemorySummary = memorySummary;
    lastDebriefContinuationPartnerState = continuationPartnerState;
    lastDebriefAppliedHintTurns = appliedHintTurns;
    return debriefHandler!(turns, profile: profile);
  }

  @override
  Future<PracticeDrawResult> drawProfile({
    required String requestId,
    String? currentProfileId,
    String? visiblePracticeThreadId,
  }) {
    drawCallCount++;
    lastDrawRequestId = requestId;
    lastDrawCurrentProfileId = currentProfileId;
    lastDrawVisibleThreadId = visiblePracticeThreadId;
    return drawHandler!(currentProfileId: currentProfileId);
  }
}

void main() {
  late Box<PracticeSession> box;
  late PracticeSessionRepository repo;
  late InMemoryPracticeDrawDraftStore draftStore;
  late _FakeApi api;
  late List<List<int>> synced;
  late MemoryAnalysisHistoryRepository history;

  setUp(() async {
    Hive.init('./.dart_tool/test_hive_practice_ctrl');
    if (!Hive.isAdapterRegistered(22)) {
      Hive.registerAdapter(PracticeMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(23)) {
      Hive.registerAdapter(PracticeSessionAdapter());
    }
    final ts = DateTime.now().microsecondsSinceEpoch;
    box = await Hive.openBox<PracticeSession>('practice_ctrl_$ts');
    repo = PracticeSessionRepository(box);
    draftStore = InMemoryPracticeDrawDraftStore();
    api = _FakeApi();
    synced = [];
    history = MemoryAnalysisHistoryRepository();
    // 預設翻牌回一位固定對象（far-future reset → 草稿不過期）。
    api.drawHandler = ({currentProfileId}) async => drawResult();
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  PracticeChatController makeController({
    PracticePendingHintStore? pendingHintStore,
    PracticePendingDrawStore? pendingDrawStore,
    Duration? hintRequestTimeout,
    Duration? sendMessageTimeout,
  }) {
    final c = PracticeChatController(
      api: api,
      repository: repo,
      draftStore: draftStore,
      pendingHintStore: pendingHintStore,
      pendingDrawStore: pendingDrawStore,
      onUsageSynced: ({required monthlyRemaining, required dailyRemaining}) {
        synced.add([monthlyRemaining, dailyRemaining]);
      },
      historyRepository: history,
      sessionId: 'sess-1',
      createdAt: DateTime(2026, 6, 26, 13, 0),
      hintRequestTimeout: hintRequestTimeout,
      sendMessageTimeout: sendMessageTimeout,
    );
    addTearDown(c.dispose);
    return c;
  }

  PracticeChatController makeControllerFrom(
    PracticeSession session, {
    PracticePendingHintStore? pendingHintStore,
  }) {
    final c = PracticeChatController(
      api: api,
      repository: repo,
      draftStore: draftStore,
      pendingHintStore: pendingHintStore,
      onUsageSynced: ({required monthlyRemaining, required dailyRemaining}) {
        synced.add([monthlyRemaining, dailyRemaining]);
      },
      historyRepository: history,
      initialSession: session,
    );
    addTearDown(c.dispose);
    return c;
  }

  /// 進到 revealed（翻好一張牌）的 controller，給「需要先有對象才能聊天」的測試用。
  Future<PracticeChatController> makeRevealed({
    PracticePendingHintStore? pendingHintStore,
    PracticePendingDrawStore? pendingDrawStore,
    Duration? hintRequestTimeout,
    Duration? sendMessageTimeout,
  }) async {
    final c = makeController(
      pendingHintStore: pendingHintStore,
      pendingDrawStore: pendingDrawStore,
      hintRequestTimeout: hintRequestTimeout,
      sendMessageTimeout: sendMessageTimeout,
    );
    await c.drawNewPracticeGirl();
    expect(c.currentState.drawStatus, PracticeDrawStatus.revealed);
    return c;
  }

  PracticeChatReply reply({
    String text = '嗯？',
    int aiTurnCount = 1,
    bool complete = false,
    int cost = 1,
    int? monthly = 29,
    int? daily = 14,
    PracticeTemperature? temperature,
    PracticePartnerState? partnerState,
    int? hintUsedCount,
  }) =>
      PracticeChatReply(
        reply: text,
        aiTurnCount: aiTurnCount,
        sessionComplete: complete,
        costDeducted: cost,
        monthlyRemaining: monthly,
        dailyRemaining: daily,
        temperature: temperature,
        partnerState: partnerState,
        hintUsedCount: hintUsedCount,
      );

  PracticeHintResult hintResult({
    int cost = 1,
    int hintUsedCount = 1,
    int? monthly = 28,
    int? daily = 13,
  }) =>
      PracticeHintResult(
        replies: const [
          PracticeHintReply(
            type: PracticeHintReplyType.warmUp,
            label: '加分回覆',
            text: '我也想聽你多講一點，這件事聽起來很有趣。',
          ),
          PracticeHintReply(
            type: PracticeHintReplyType.steady,
            label: '不扣分回覆',
            text: '聽起來你今天過得很充實，最累的是哪一段？',
          ),
        ],
        coaching: '先接住情緒，再丟一個好回答的小問題。',
        costDeducted: cost,
        hintUsedCount: hintUsedCount,
        monthlyRemaining: monthly,
        dailyRemaining: daily,
      );

  // 第一輪已完成並拆解的場次（多個 group 共用）。
  PracticeSession round1Done() => PracticeSession(
        id: 'round1',
        createdAt: DateTime(2026, 6, 24, 9),
        aiReplyCount: 3,
        messages: const [
          PracticeMessage(role: 'user', text: '嗨'),
          PracticeMessage(role: 'ai', text: '嗯？'),
        ],
        roundIndex: 1,
        visiblePracticeThreadId: 'round1',
        profileId: 'practice_girl_005',
        debriefSummary: '不錯',
        debriefStrengths: const ['開場好'],
        debriefSuggestedLine: '約她',
        debriefVibe: '暖',
      );

  PracticeDrawDraft draftFor(
    String profileId, {
    DateTime? nextResetAt,
    String difficulty = 'normal',
    PracticeLearningMode learningMode = PracticeLearningMode.standard,
    int? temperatureScore,
    int? familiarityScore,
    String? relationshipStageLabel,
  }) {
    final g = girlProfileById(profileId)!;
    return PracticeDrawDraft(
      sessionId: 'draft-sess',
      visiblePracticeThreadId: 'draft-sess',
      roundIndex: 1,
      profileId: g.profileId,
      personaId: g.personaId,
      difficulty: difficulty,
      difficultyPreference: PracticeDifficultyPreference.normal,
      freeAllowance: 1,
      freeUsed: 1,
      freeRemaining: 0,
      extraCostMessages: 5,
      learningMode: learningMode,
      temperatureScore: temperatureScore,
      familiarityScore: familiarityScore,
      relationshipStageLabel: relationshipStageLabel,
      nextResetAt: nextResetAt ?? DateTime.utc(2999, 1, 1, 4),
      createdAt: DateTime(2026, 6, 26, 13),
    );
  }

  // ── 進場狀態：locked / draft / session ──────────────────────────────────
  group('進場狀態', () {
    test('沒 session 也沒 draft → locked、girl null、不顯示對象', () {
      final c = makeController();
      final s = c.currentState;
      expect(s.drawStatus, PracticeDrawStatus.locked);
      expect(s.girl, isNull);
      expect(s.messages, isEmpty);
      expect(s.canSend, false);
    });

    test('有效 draft → revealed、還原同一位、不打 API', () {
      draftStore.save(draftFor('practice_girl_005'));
      final c = makeController();
      final s = c.currentState;

      expect(s.drawStatus, PracticeDrawStatus.revealed);
      expect(s.girl, isNotNull);
      expect(s.girl!.profileId, 'practice_girl_005');
      expect(s.messages, isEmpty);
      expect(api.drawCallCount, 0); // 還原 draft 不重抽
    });

    test('有效 beginner draft → 還原 learning state', () {
      draftStore.save(draftFor(
        'practice_girl_005',
        learningMode: PracticeLearningMode.beginner,
        temperatureScore: 42,
        familiarityScore: 44,
        relationshipStageLabel: '可以聊個人',
      ));
      final c = makeController();
      final s = c.currentState;

      expect(s.learningMode, PracticeLearningMode.beginner);
      expect(s.temperatureScore, 42);
      expect(s.familiarityScore, 44);
      expect(s.relationshipStageLabel, '可以聊個人');
    });

    test('beginner draft 未帶 temperatureScore → fallback 隨難度（easy 35）', () {
      draftStore.save(draftFor(
        'practice_girl_005',
        difficulty: 'easy',
        learningMode: PracticeLearningMode.beginner,
      ));
      final c = makeController();
      expect(c.currentState.temperatureScore, 35);
    });

    test('beginner session 未帶 temperatureScore → fallback 隨難度（challenge 20）',
        () {
      final c = makeControllerFrom(PracticeSession(
        id: 'open-2',
        createdAt: DateTime(2026, 6, 26, 12),
        aiReplyCount: 1,
        messages: const [
          PracticeMessage(role: 'user', text: '嗨'),
          PracticeMessage(role: 'ai', text: '嗯？'),
        ],
        profileId: 'practice_girl_009',
        difficulty: 'challenge',
        practiceMode: 'beginner',
      ));
      expect(c.currentState.temperatureScore, 20);
    });

    test('過期 draft（已過 nextResetAt）→ 忽略 → locked', () {
      draftStore.save(
        draftFor('practice_girl_005', nextResetAt: DateTime.utc(2000, 1, 1, 4)),
      );
      final c = makeController();
      expect(c.currentState.drawStatus, PracticeDrawStatus.locked);
      expect(c.currentState.girl, isNull);
    });

    test('有未拆解 session → revealed、照 session profile 還原（優先於 draft）', () {
      draftStore.save(draftFor('practice_girl_005'));
      final c = makeControllerFrom(PracticeSession(
        id: 'open-1',
        createdAt: DateTime(2026, 6, 26, 12),
        aiReplyCount: 1,
        messages: const [
          PracticeMessage(role: 'user', text: '嗨'),
          PracticeMessage(role: 'ai', text: '嗯？'),
        ],
        profileId: 'practice_girl_009',
      ));
      final s = c.currentState;
      expect(s.drawStatus, PracticeDrawStatus.revealed);
      expect(s.girl!.profileId, 'practice_girl_009'); // session 勝過 draft
    });
  });

  // ── drawNewPracticeGirl ────────────────────────────────────────────────
  group('drawNewPracticeGirl', () {
    test('成功 → revealed、girl=server 回的對象、roundIndex 1、threadId=新 sessionId',
        () async {
      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_010');
      final c = makeController();

      await c.drawNewPracticeGirl();
      final s = c.currentState;

      expect(s.drawStatus, PracticeDrawStatus.revealed);
      expect(s.girl!.profileId, 'practice_girl_010');
      expect(s.personaId, s.girl!.personaId);
      expect(s.roundIndex, 1);
      expect(s.visiblePracticeThreadId, s.sessionId);
      expect(s.messages, isEmpty);
      expect(api.lastDrawRequestId, isNotNull);
    });

    test('成功 → 存 draft（同一位、含 nextResetAt），但不寫進 recent sessions', () async {
      api.drawHandler = ({currentProfileId}) async => drawResult(
          profileId: 'practice_girl_010',
          nextResetAt: '2999-01-01T04:00:00.000Z');
      final c = makeController();

      await c.drawNewPracticeGirl();

      final draft = draftStore.load();
      expect(draft, isNotNull);
      expect(draft!.profileId, 'practice_girl_010');
      expect(draft.nextResetAt, DateTime.utc(2999, 1, 1, 4));
      expect(draft.sessionId, c.currentState.sessionId);
      expect(repo.recentSessions(), isEmpty); // 不造假歷史
    });

    test('翻牌帶 requestId：網路失敗重試沿用同 id、成功才 rotate', () async {
      final c = await makeRevealed();

      // 網路失敗：id 保留供重試（server 可能已入帳、回應丟失）
      api.drawHandler =
          ({currentProfileId}) async => throw Exception('network');
      await c.drawNewPracticeGirl();
      final firstId = api.lastDrawRequestId;
      expect(firstId, isNotNull);

      // 重試成功：沿用同一 id（server 靠它 replay 不雙扣）
      api.drawHandler = ({currentProfileId}) async => drawResult();
      await c.drawNewPracticeGirl();
      expect(api.lastDrawRequestId, firstId);

      // 成功後 rotate：下一抽是新意圖 → 新 id
      await c.drawNewPracticeGirl();
      expect(api.lastDrawRequestId, isNot(firstId));
    });

    test('翻牌 4xx 明確拒絕 → rotate 新 id（不沿用）', () async {
      final c = await makeRevealed();

      api.drawHandler = ({currentProfileId}) async =>
          throw PracticeDrawUpgradeRequiredException(extraCostMessages: 5);
      await c.drawNewPracticeGirl();
      final firstId = api.lastDrawRequestId;
      expect(firstId, isNotNull);

      api.drawHandler = ({currentProfileId}) async => drawResult();
      await c.drawNewPracticeGirl();
      expect(api.lastDrawRequestId, isNot(firstId));
    });

    test('翻牌失敗 → controller 重建（同持久化 store）→ 指紋吻合沿用同 id', () async {
      final pendingStore = InMemoryPracticePendingDrawStore();

      // 首抽（locked、girl=null）失敗：pending 指紋＝currentProfileId null
      api.drawHandler =
          ({currentProfileId}) async => throw Exception('network');
      final c = makeController(pendingDrawStore: pendingStore);
      await c.drawNewPracticeGirl();
      final firstId = api.lastDrawRequestId;
      expect(firstId, isNotNull);

      // 重建（autoDispose 後）：同 store、同 locked 狀態 → 重試沿用同 id
      api.drawHandler = ({currentProfileId}) async => drawResult();
      final c2 = makeController(pendingDrawStore: pendingStore);
      await c2.drawNewPracticeGirl();
      expect(api.lastDrawRequestId, firstId);
    });

    test('pending 指紋不符（換了對象）→ 鑄新 id 不沿用', () async {
      final pendingStore = InMemoryPracticePendingDrawStore();
      await pendingStore.save(
        PracticePendingDraw(
          currentProfileId: 'practice_girl_999',
          requestId: 'stale-id',
          savedAt: DateTime.now(),
        ),
      );

      await makeRevealed(pendingDrawStore: pendingStore);
      expect(api.lastDrawRequestId, isNot('stale-id'));
    });

    test('pending 超過 TTL（陳年首抽 id）→ 作廢鑄新 id（Codex client R1 P2）', () async {
      final pendingStore = InMemoryPracticePendingDrawStore();
      // locked 首抽指紋＝null：沒有 TTL 的話，幾天後的新首抽會誤沿用、
      // server replay 回舊 profile。
      await pendingStore.save(
        PracticePendingDraw(
          currentProfileId: null,
          requestId: 'ancient-id',
          savedAt: DateTime.now().subtract(const Duration(hours: 26)),
        ),
      );

      final c = makeController(pendingDrawStore: pendingStore);
      await c.drawNewPracticeGirl();
      expect(api.lastDrawRequestId, isNot('ancient-id'));
    });

    test('pending 在 TTL 內（剛失敗的重試）→ 沿用同 id', () async {
      final pendingStore = InMemoryPracticePendingDrawStore();
      await pendingStore.save(
        PracticePendingDraw(
          currentProfileId: null,
          requestId: 'recent-id',
          savedAt: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
      );

      final c = makeController(pendingDrawStore: pendingStore);
      await c.drawNewPracticeGirl();
      expect(api.lastDrawRequestId, 'recent-id');
    });

    test('換一位（已 revealed 再抽）→ 帶 currentProfileId 排除目前這位', () async {
      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_010');
      final c = await makeRevealed();
      final firstId = c.currentState.girl!.profileId;

      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_011');
      await c.drawNewPracticeGirl();

      expect(api.lastDrawCurrentProfileId, firstId);
      expect(c.currentState.girl!.profileId, 'practice_girl_011');
    });

    test('402 → drawUpgradeRequired、保留原狀態（仍 locked、girl null）、不存 draft',
        () async {
      api.drawHandler = ({currentProfileId}) async =>
          throw PracticeDrawUpgradeRequiredException(
            freeAllowance: 1,
            extraCostMessages: 5,
            nextResetAt: '2026-06-27T04:00:00.000Z',
          );
      final c = makeController();

      await c.drawNewPracticeGirl();
      final s = c.currentState;

      expect(s.drawUpgradeRequired, true);
      expect(s.drawStatus, PracticeDrawStatus.locked); // 保留原狀態
      expect(s.girl, isNull); // 不污染
      expect(s.drawExtraCost, 5);
      expect(draftStore.load(), isNull); // 不存 draft
    });

    test('429 → drawQuotaExceeded、保留原狀態、不污染', () async {
      api.drawHandler = ({currentProfileId}) async =>
          throw PracticeQuotaExceededException('本月額度已用完',
              monthlyRemaining: 0, dailyRemaining: 0);
      final c = makeController();

      await c.drawNewPracticeGirl();
      final s = c.currentState;

      expect(s.drawQuotaExceeded, true);
      expect(s.drawUpgradeRequired, false);
      expect(s.drawStatus, PracticeDrawStatus.locked);
      expect(s.girl, isNull);
    });

    test('換一位失敗（402）→ 不污染目前已揭曉的對象', () async {
      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_010');
      final c = await makeRevealed();
      final before = c.currentState.girl!.profileId;

      api.drawHandler = ({currentProfileId}) async =>
          throw PracticeDrawUpgradeRequiredException(extraCostMessages: 5);
      await c.drawNewPracticeGirl();
      final s = c.currentState;

      expect(s.drawUpgradeRequired, true);
      expect(s.drawStatus, PracticeDrawStatus.revealed); // 仍揭曉
      expect(s.girl!.profileId, before); // 不漂移
    });

    test('一般失敗 → drawStatus error、有錯誤訊息、locked 時不揭曉對象', () async {
      api.drawHandler = ({currentProfileId}) async =>
          throw PracticeGenerationFailedException('boom');
      final c = makeController();

      await c.drawNewPracticeGirl();
      final s = c.currentState;

      expect(s.drawStatus, PracticeDrawStatus.error);
      expect(s.errorMessage, isNotNull);
      expect(s.girl, isNull);
    });

    test('付費額外翻牌（cost>0）→ 同步訂閱剩餘額度', () async {
      api.drawHandler = ({currentProfileId}) async => drawResult(
            profileId: 'practice_girl_010',
            cost: 5,
            monthlyUsed: 10,
            monthlyLimit: 30,
            dailyUsed: 4,
            dailyLimit: 30,
          );
      final c = makeController();

      await c.drawNewPracticeGirl();
      expect(synced, [
        [20, 26]
      ]); // monthlyRemaining=30-10, dailyRemaining=30-4
    });

    test('免費翻牌（cost=0）→ 不同步額度', () async {
      api.drawHandler = ({currentProfileId}) async => drawResult(cost: 0);
      final c = makeController();
      await c.drawNewPracticeGirl();
      expect(synced, isEmpty);
    });
  });

  // ── 換一位入口都走 draw；續玩/切難度都不走 draw ───────────────────────────
  group('入口路由', () {
    test('局後換一位（drawNewPracticeGirl）→ 走 draw', () async {
      final c = makeControllerFrom(round1Done());
      expect(api.drawCallCount, 0);
      await c.drawNewPracticeGirl();
      expect(api.drawCallCount, 1);
    });

    test('揭曉後換一位（drawNewPracticeGirl）→ 走 draw', () async {
      final c = await makeRevealed();
      final before = api.drawCallCount;
      await c.drawNewPracticeGirl();
      expect(api.drawCallCount, before + 1);
    });

    test('continueWithSamePartner → 不走 draw、保留 profile/thread', () {
      final c = makeControllerFrom(round1Done());
      final beforeGirl = c.currentState.girl!.profileId;

      c.continueWithSamePartner(isPaid: true);

      expect(api.drawCallCount, 0);
      expect(c.currentState.girl!.profileId, beforeGirl);
      expect(c.currentState.visiblePracticeThreadId, 'round1');
      expect(c.currentState.roundIndex, 2);
    });

    test('setDifficultyPreference → 不走 draw、不換對象', () async {
      final c = await makeRevealed();
      final beforeGirl = c.currentState.girl!.profileId;
      final before = api.drawCallCount;

      c.setDifficultyPreference(PracticeDifficultyPreference.challenge);

      expect(api.drawCallCount, before); // 不抽
      expect(c.currentState.girl!.profileId, beforeGirl); // 不換對象
      expect(c.currentState.difficulty, 'challenge');
    });

    test('切難度（draft 未送出）→ 同步更新 draft 的難度', () async {
      final c = await makeRevealed();
      expect(draftStore.load()!.difficulty, 'normal');

      c.setDifficultyPreference(PracticeDifficultyPreference.challenge);

      expect(draftStore.load()!.difficulty, 'challenge');
      expect(draftStore.load()!.profileId, c.currentState.girl!.profileId);
    });
  });

  // ── sendMessage gating ─────────────────────────────────────────────────
  group('sendMessage 需要先翻牌', () {
    test('locked 時送訊息 → 擋下、提示先翻牌、不打 API、無泡泡', () async {
      var sendCalled = false;
      api.sendHandler = (_, {profile}) async {
        sendCalled = true;
        return reply();
      };
      final c = makeController();

      await c.sendMessage('嗨');
      final s = c.currentState;

      expect(sendCalled, false);
      expect(s.messages, isEmpty);
      expect(s.errorMessage, isNotNull);
    });

    test('翻牌後第一則送出成功 → 清掉 draft、寫入 session', () async {
      final c = await makeRevealed();
      expect(draftStore.load(), isNotNull);

      api.sendHandler = (_, {profile}) async => reply();
      await c.sendMessage('嗨');

      expect(draftStore.load(), isNull); // 第一則成功後清 draft
      expect(repo.getById(c.currentState.sessionId), isNotNull);
      expect(c.currentState.messages.map((m) => m.role), ['user', 'ai']);
    });
  });

  // ── 送訊息（已 revealed）行為 ─────────────────────────────────────────────
  group('送訊息', () {
    test('成功：user+ai 泡泡、計數、扣點同步、持久化', () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async => reply();

      await c.sendMessage('嗨');
      final s = c.currentState;

      expect(s.messages.map((m) => m.role).toList(), ['user', 'ai']);
      expect(s.aiReplyCount, 1);
      expect(s.isSending, false);
      expect(synced, [
        [29, 14]
      ]);
      expect(repo.getById(s.sessionId), isNotNull);
    });

    test('AI message stores server partnerState for later debrief context',
        () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async => reply(
            text: '嗯？聽起來你今天很忙。',
            partnerState: const PracticePartnerState(
              mood: 'curious',
              innerThought: '他有回到我的情緒，我想多問一點。',
            ),
          );

      await c.sendMessage('今天真的有點累');
      final last = c.currentState.messages.last;

      expect(last.role, 'ai');
      expect(last.mood, 'curious');
      expect(last.innerThought, '他有回到我的情緒，我想多問一點。');
      final saved = repo.getById(c.currentState.sessionId)!;
      expect(saved.messages.last.mood, 'curious');
      expect(saved.messages.last.innerThought, '他有回到我的情緒，我想多問一點。');
    });

    test('翻牌後送訊息帶上 server 給的 girl 身份', () async {
      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_010');
      final c = await makeRevealed();
      final girl = c.currentState.girl!;

      PracticeProfileDto? sent;
      api.sendHandler = (turns, {profile}) async {
        sent = profile;
        return reply();
      };
      await c.sendMessage('嗨');

      expect(sent!.profileId, girl.profileId);
      expect(sent!.nameId, girl.nameId);
      expect(sent!.personaId, girl.personaId);
      expect(repo.getById(c.currentState.sessionId)!.profileId, girl.profileId);
    });

    test('生成失敗：回滾泡泡、設錯誤與還原文字、不持久化、不同步', () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async =>
          throw PracticeGenerationFailedException('boom');

      await c.sendMessage('嗨');
      final s = c.currentState;

      expect(s.messages, isEmpty);
      expect(s.errorMessage, isNotNull);
      expect(s.restoreText, '嗨');
      expect(repo.getById(s.sessionId), isNull);
      expect(synced, isEmpty);
    });

    test('額度用罄：quotaExceeded + 回滾', () async {
      final c = await makeRevealed();
      api.sendHandler =
          (_, {profile}) async => throw PracticeQuotaExceededException(
                '本月額度已用完',
                monthlyRemaining: 0,
                dailyRemaining: 0,
              );

      await c.sendMessage('嗨');
      final s = c.currentState;

      expect(s.quotaExceeded, true);
      expect(s.errorMessage, '本月額度已用完');
      expect(s.messages, isEmpty);
    });

    test('模型限流 429：不標 quotaExceeded、顯示稍等文案＋回滾還原', () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async => throw PracticeApiException(
            '操作太頻繁，請稍等一分鐘再試。',
            status: 429,
          );

      await c.sendMessage('嗨');
      final s = c.currentState;

      expect(s.quotaExceeded, false);
      expect(s.errorMessage, contains('太頻繁'));
      expect(s.messages, isEmpty);
      expect(s.restoreText, '嗨');
    });

    test('Free 續玩需升級：upgradeRequired + 回滾 + 還原文字', () async {
      final c = await makeRevealed();
      api.sendHandler =
          (_, {profile}) async => throw PracticeUpgradeRequiredException();

      await c.sendMessage('嗨');
      final s = c.currentState;

      expect(s.upgradeRequired, true);
      expect(s.quotaExceeded, false);
      expect(s.messages, isEmpty);
      expect(s.restoreText, '嗨');
    });

    test('滿上限：sessionComplete 後鎖定輸入、再送被忽略', () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async =>
          reply(text: '最後一句', aiTurnCount: 20, complete: true, cost: 0);

      await c.sendMessage('嗨');
      expect(c.currentState.sessionComplete, true);
      expect(c.currentState.canSend, false);

      await c.sendMessage('再一句');
      expect(c.currentState.messages.length, 2);
    });

    test('mode locked（409 practice_mode_locked）：提示切回原模式、絕不標 sessionComplete',
        () async {
      final c = await makeRevealed();
      api.sendHandler =
          (_, {profile}) async => throw PracticeModeLockedException();

      await c.sendMessage('嗨');
      final s = c.currentState;

      expect(s.sessionComplete, false); // 誤標會引導「續聊同一位」多扣一則
      expect(
        s.errorMessage,
        '這位陪練女孩這一輪已用另一種模式進行中，請切回原本的模式繼續',
      );
      expect(s.messages, isEmpty); // 回滾樂觀泡泡
      expect(s.restoreText, '嗨');
      expect(s.canSend, true); // 不鎖輸入
    });

    test('clearError 會一併清掉 upgradeRequired / draw 旗標', () async {
      final c = await makeRevealed();
      api.sendHandler =
          (_, {profile}) async => throw PracticeUpgradeRequiredException();
      await c.sendMessage('嗨');
      expect(c.currentState.upgradeRequired, true);

      c.clearError();
      expect(c.currentState.upgradeRequired, false);
      expect(c.currentState.drawUpgradeRequired, false);
      expect(c.currentState.drawQuotaExceeded, false);
      expect(c.currentState.errorMessage, isNull);
    });
  });

  // ── 結束練習 / 拆解 ──────────────────────────────────────────────────────
  group('結束練習', () {
    Future<PracticeChatController> makeDebriefable() async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async => reply();
      await c.sendMessage('嗨');
      return c;
    }

    test('產拆解卡、鎖定、持久化拆解欄位', () async {
      final c = await makeDebriefable();

      api.debriefHandler = (_, {profile}) async => const PracticeDebrief(
            summary: '整體不錯',
            strengths: ['開場自然'],
            watchouts: [],
            suggestedLine: '下次直接約她',
            vibe: '暖',
            dateChance: 'medium',
            dateChanceReason: '她有回應，但還需要鋪墊。',
            nextInviteMove: '先丟一個模糊邀約。',
          );
      await c.endPractice();
      final s = c.currentState;

      expect(s.debrief, isNotNull);
      expect(s.sessionComplete, true);
      final saved = repo.getById(s.sessionId)!;
      expect(saved.debriefSummary, '整體不錯');
      expect(saved.debriefDateChance, 'medium');
      expect(saved.debriefDateChanceReason, '她有回應，但還需要鋪墊。');
      expect(saved.debriefNextInviteMove, '先丟一個模糊邀約。');
    });

    test('locked 時 endPractice 為 no-op', () async {
      final c = makeController();
      await c.endPractice();
      expect(c.currentState.debrief, isNull);
      expect(c.currentState.isDebriefing, false);
    });

    test('拆解失敗：標示失敗並鎖住輸入', () async {
      final c = await makeDebriefable();

      api.debriefHandler = (_, {profile}) async =>
          throw PracticeGenerationFailedException('boom');
      await c.endPractice();
      final s = c.currentState;

      expect(s.debrief, isNull);
      expect(s.debriefFailed, true);
      expect(s.ended, true);
      expect(s.canSend, false);
      expect(s.canDebrief, true);
    });

    test('拆解 429 模型限流：顯示 server 文案並保留重試', () async {
      final c = await makeDebriefable();
      api.debriefHandler = (_, {profile}) async => throw PracticeApiException(
            '請求太頻繁，請稍後再試。',
            status: 429,
          );

      await c.endPractice();
      final s = c.currentState;

      expect(s.isDebriefing, false);
      expect(s.debriefFailed, true);
      expect(s.debriefRetryable, true);
      expect(s.quotaExceeded, false);
      expect(s.errorMessage, '請求太頻繁，請稍後再試。');
      expect(s.canDebrief, true);
    });

    test('拆解達單場上限：提示已用完且不再提供重試', () async {
      final c = await makeDebriefable();
      api.debriefHandler = (_, {profile}) async =>
          throw PracticeApiException('practice_debrief_limit', status: 403);

      await c.endPractice();
      final s = c.currentState;

      expect(s.isDebriefing, false);
      expect(s.ended, true);
      expect(s.debriefFailed, true);
      expect(s.debriefRetryable, false);
      expect(s.errorMessage, '這場練習的拆解次數已用完。');
      expect(s.canDebrief, false);
    });

    test('拆解 quota / upgrade / mode locked 走明確旗標與文案', () async {
      final cases = <({
        Object exception,
        bool quotaExceeded,
        bool upgradeRequired,
        String message,
      })>[
        (
          exception: PracticeQuotaExceededException('額度已用完'),
          quotaExceeded: true,
          upgradeRequired: false,
          message: '額度已用完',
        ),
        (
          exception: PracticeUpgradeRequiredException(),
          quotaExceeded: false,
          upgradeRequired: true,
          message: '這個拆解會消耗訊息額度，升級後就能繼續使用。',
        ),
        (
          exception: PracticeModeLockedException(),
          quotaExceeded: false,
          upgradeRequired: false,
          message: '這位陪練女孩這一輪已用另一種模式進行中，請切回原本的模式繼續',
        ),
      ];

      for (final testCase in cases) {
        final c = await makeDebriefable();
        api.debriefHandler = (_, {profile}) async => throw testCase.exception;

        await c.endPractice();
        final s = c.currentState;

        expect(s.debriefFailed, true);
        expect(s.debriefRetryable, true);
        expect(s.quotaExceeded, testCase.quotaExceeded);
        expect(s.upgradeRequired, testCase.upgradeRequired);
        expect(s.errorMessage, testCase.message);
      }
    });

    test('拆解服務未就緒或設定缺失：顯示稍後再試文案', () async {
      final cases = [
        'practice_learning_not_ready',
        'config_missing',
      ];

      for (final code in cases) {
        final c = await makeDebriefable();
        api.debriefHandler = (_, {profile}) async =>
            throw PracticeGenerationFailedException(code);

        await c.endPractice();
        final s = c.currentState;

        expect(s.debriefFailed, true);
        expect(s.debriefRetryable, true);
        expect(s.errorMessage, '拆解服務暫時無法使用，請稍後再試。');
      }
    });

    test('拆解網路錯誤：提示網路不穩並保留重試', () async {
      final c = await makeDebriefable();
      api.debriefHandler =
          (_, {profile}) async => throw TimeoutException('timeout');

      await c.endPractice();
      final s = c.currentState;

      expect(s.debriefFailed, true);
      expect(s.debriefRetryable, true);
      expect(s.errorMessage, '網路不穩，拆解卡生成失敗，可以再按一次。');
    });
  });

  // ── 還原既有 session 續聊 ────────────────────────────────────────────────
  group('續聊既有 session', () {
    test('沿用 sessionId、舊訊息與 ai 計數，可直接送（已 revealed）', () async {
      final c = makeControllerFrom(PracticeSession(
        id: 'resume-1',
        createdAt: DateTime(2026, 6, 24, 9, 30),
        aiReplyCount: 1,
        messages: const [
          PracticeMessage(role: 'user', text: '嗨'),
          PracticeMessage(role: 'ai', text: '嗯？'),
        ],
        profileId: 'practice_girl_005',
      ));
      expect(c.currentState.drawStatus, PracticeDrawStatus.revealed);
      expect(c.currentState.sessionId, 'resume-1');

      late List<PracticeTurnDto> sentTurns;
      api.sendHandler = (turns, {profile}) async {
        sentTurns = turns;
        return reply(text: '好啊', aiTurnCount: 2, cost: 0);
      };
      await c.sendMessage('那你今天忙嗎');

      expect(sentTurns.map((t) => t.text).toList(), ['嗨', '嗯？', '那你今天忙嗎']);
      expect(c.currentState.aiReplyCount, 2);
      expect(repo.getById('resume-1')!.messages.length, 4);
    });

    test('provider 進房自動載入最近未拆解場次，略過已拆解紀錄', () async {
      await repo.save(PracticeSession(
        id: 'reviewed-newer',
        createdAt: DateTime(2026, 6, 24, 16),
        aiReplyCount: 1,
        messages: const [PracticeMessage(role: 'user', text: '已拆解')],
        debriefSummary: '已完成',
      ));
      await repo.save(PracticeSession(
        id: 'open-latest',
        createdAt: DateTime(2026, 6, 24, 15, 58),
        aiReplyCount: 1,
        messages: const [
          PracticeMessage(role: 'user', text: '嗨'),
          PracticeMessage(role: 'ai', text: '嗯？'),
        ],
      ));

      final container = ProviderContainer(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceChatApiServiceProvider.overrideWithValue(api),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
          practicePendingHintStoreProvider
              .overrideWithValue(InMemoryPracticePendingHintStore()),
          analysisHistoryRepositoryProvider.overrideWithValue(history),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(practiceChatControllerProvider);
      expect(state.sessionId, 'open-latest');
      expect(state.drawStatus, PracticeDrawStatus.revealed);
    });

    test('進房沒有任何 open session 也沒 draft → locked（不自動造對象）', () {
      final container = ProviderContainer(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceChatApiServiceProvider.overrideWithValue(api),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
          practicePendingHintStoreProvider
              .overrideWithValue(InMemoryPracticePendingHintStore()),
          analysisHistoryRepositoryProvider.overrideWithValue(history),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(practiceChatControllerProvider);
      expect(state.drawStatus, PracticeDrawStatus.locked);
      expect(state.girl, isNull);
    });
  });

  // ── 續玩 metadata 流穿 ───────────────────────────────────────────────────
  group('續玩 metadata 流穿', () {
    PracticeChatController resumeR2() => makeControllerFrom(PracticeSession(
          id: 'sess-r2',
          createdAt: DateTime(2026, 6, 24, 9, 30),
          aiReplyCount: 1,
          messages: const [
            PracticeMessage(role: 'user', text: '嗨'),
            PracticeMessage(role: 'ai', text: '嗯？'),
          ],
          roundIndex: 2,
          visiblePracticeThreadId: 'thread-x',
          profileId: 'practice_girl_005',
        ));

    test('既存 roundIndex/threadId 續聊：照原值還原', () {
      final c = resumeR2();
      expect(c.currentState.roundIndex, 2);
      expect(c.currentState.visiblePracticeThreadId, 'thread-x');
    });

    test('sendMessage 帶上 state 的 roundIndex 與 visiblePracticeThreadId',
        () async {
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 48,
              delta: 4,
              band: 'cold',
              reason: 'steady',
            ),
            hintUsedCount: 0,
          );
      final c = resumeR2();
      await c.sendMessage('在嗎');
      expect(api.lastRoundIndex, 2);
      expect(api.lastVisibleThreadId, 'thread-x');
    });

    test('endPractice 帶上 state 的 roundIndex 與 visiblePracticeThreadId',
        () async {
      api.sendHandler = (_, {profile}) async => reply(cost: 0);
      final c = resumeR2();
      api.debriefHandler = (_, {profile}) async => const PracticeDebrief(
            summary: 'x',
            strengths: [],
            watchouts: [],
            suggestedLine: 'y',
            vibe: '中性',
          );
      await c.endPractice();
      expect(api.lastDebriefRoundIndex, 2);
      expect(api.lastDebriefThreadId, 'thread-x');
    });
  });

  // ── 續玩同一位（continueWithSamePartner）─────────────────────────────────
  group('續玩同一位', () {
    test('付費續玩：新 sessionId、roundIndex+1、threadId 不變、訊息保留、aiReplyCount 歸 0', () {
      final c = makeControllerFrom(round1Done());
      final oldSessionId = c.currentState.sessionId;

      c.continueWithSamePartner(isPaid: true);
      final s = c.currentState;

      expect(s.sessionId, isNot(oldSessionId));
      expect(s.roundIndex, 2);
      expect(s.visiblePracticeThreadId, 'round1');
      expect(s.messages.map((m) => m.text).toList(), ['嗨', '嗯？']);
      expect(s.aiReplyCount, 0);
      expect(s.drawStatus, PracticeDrawStatus.revealed);
      expect(s.canRequestHint, false);
    });

    test('付費續玩：清掉 debrief/ended/sessionComplete，可再聊', () {
      final c = makeControllerFrom(round1Done());
      expect(c.currentState.canSend, false);

      c.continueWithSamePartner(isPaid: true);
      final s = c.currentState;

      expect(s.debrief, isNull);
      expect(s.ended, false);
      expect(s.sessionComplete, false);
      expect(s.canSend, true);
    });

    test('Free 續玩：只設 upgradeRequired，不動 session/messages/round，不走 draw', () {
      final c = makeControllerFrom(round1Done());
      final before = c.currentState;

      c.continueWithSamePartner(isPaid: false);
      final s = c.currentState;

      expect(s.upgradeRequired, true);
      expect(s.quotaExceeded, false);
      expect(s.sessionId, before.sessionId);
      expect(s.roundIndex, before.roundIndex);
      expect(s.messages, before.messages);
      expect(api.drawCallCount, 0);
    });

    test('roundIndex 第 3 輪後仍可付費續玩到第 4 輪', () {
      final c = makeControllerFrom(PracticeSession(
        id: 'round3',
        createdAt: DateTime(2026, 6, 24, 9),
        aiReplyCount: 5,
        messages: const [PracticeMessage(role: 'user', text: '嗨')],
        roundIndex: 3,
        visiblePracticeThreadId: 'thread-orig',
        profileId: 'practice_girl_005',
        debriefSummary: '結束',
      ));
      final before = c.currentState;

      c.continueWithSamePartner(isPaid: true);
      expect(c.currentState.sessionId, isNot(before.sessionId));
      expect(c.currentState.roundIndex, 4);
      expect(c.currentState.visiblePracticeThreadId, 'thread-orig');
      expect(c.currentState.messages, before.messages);
      expect(c.currentState.canSend, true);
    });

    test('續玩後送訊息：送出完整累積 thread、API 收到 roundIndex+1 與原 threadId', () async {
      final r1 = round1Done();
      await repo.save(r1);
      final c = makeControllerFrom(r1);
      c.continueWithSamePartner(isPaid: true);
      final newSessionId = c.currentState.sessionId;

      late List<PracticeTurnDto> sentTurns;
      api.sendHandler = (turns, {profile}) async {
        sentTurns = turns;
        return reply();
      };
      await c.sendMessage('我們再聊聊');

      expect(sentTurns.map((t) => t.text).toList(), ['嗨', '嗯？', '我們再聊聊']);
      expect(api.lastRoundIndex, 2);
      expect(api.lastVisibleThreadId, 'round1');
      expect(repo.getById(newSessionId), isNotNull);
      expect(repo.getById('round1'), isNotNull);
    });

    test('paid continuation forwards last partner state seed on first send',
        () async {
      final c = makeControllerFrom(PracticeSession(
        id: 'seed-round1',
        createdAt: DateTime(2026, 6, 24, 9),
        aiReplyCount: 1,
        messages: const [
          PracticeMessage(role: 'user', text: 'hi'),
          PracticeMessage(
            role: 'ai',
            text: 'hello',
            mood: 'guarded',
            innerThought: '他剛剛有點急，我想先看他穩不穩。',
          ),
        ],
        roundIndex: 1,
        visiblePracticeThreadId: 'seed-round1',
        profileId: 'practice_girl_005',
        practiceMode: 'beginner',
        temperatureScore: 44,
        familiarityScore: 30,
        debriefSummary: 'done',
      ));
      c.continueWithSamePartner(isPaid: true);
      expect(c.currentState.canRequestHint, false);

      api.sendHandler = (_, {profile}) async => reply(cost: 0);
      await c.sendMessage('那我慢一點問');

      expect(api.lastContinuationPartnerState?.mood, 'guarded');
      expect(c.currentState.canRequestHint, true);
      expect(
        api.lastContinuationPartnerState?.innerThought,
        '他剛剛有點急，我想先看他穩不穩。',
      );
    });

    test('長 thread 送訊息：local 保留全歷史，API 只收近期 turns 與 memorySummary', () async {
      final longMessages = <PracticeMessage>[];
      for (var i = 0; i < 70; i++) {
        longMessages.add(PracticeMessage(
          role: 'user',
          text: i == 0 ? '舊使用者訊息 $i S__42795075.jpg' : '舊使用者訊息 $i',
        ));
        longMessages.add(PracticeMessage(role: 'ai', text: '舊 AI 回覆 $i'));
      }
      final c = makeControllerFrom(PracticeSession(
        id: 'long-thread',
        createdAt: DateTime(2026, 6, 24, 9),
        aiReplyCount: 20,
        messages: longMessages,
        roundIndex: 5,
        visiblePracticeThreadId: 'thread-long',
        profileId: 'practice_girl_005',
        debriefSummary: '前一段結束',
      ));
      c.continueWithSamePartner(isPaid: true);

      late List<PracticeTurnDto> sentTurns;
      api.sendHandler = (turns, {profile}) async {
        sentTurns = turns;
        return reply();
      };
      await c.sendMessage('新的第六輪訊息');

      expect(c.currentState.messages.length, 142);
      expect(sentTurns.length, lessThan(c.currentState.messages.length));
      expect(sentTurns.last.text, '新的第六輪訊息');
      expect(sentTurns.any((turn) => turn.text == '舊使用者訊息 0'), false);
      expect(api.lastMemorySummary, contains('舊使用者訊息 0'));
      expect(api.lastMemorySummary, contains('舊 AI 回覆 0'));
      expect(api.lastMemorySummary, contains('舊使用者訊息 30'));
      expect(api.lastMemorySummary, contains('[image concept omitted]'));
      expect(api.lastMemorySummary, isNot(contains('S__42795075.jpg')));
      expect(api.lastRoundIndex, 6);
      expect(api.lastVisibleThreadId, 'thread-long');
    });

    test('長 thread hint/debrief：API 收到近期 turns 與 memorySummary', () async {
      final longMessages = <PracticeMessage>[];
      for (var i = 0; i < 70; i++) {
        longMessages.add(PracticeMessage(role: 'user', text: '舊使用者訊息 $i'));
        longMessages.add(PracticeMessage(role: 'ai', text: '舊 AI 回覆 $i'));
      }
      final c = makeControllerFrom(PracticeSession(
        id: 'long-beginner-thread',
        createdAt: DateTime(2026, 6, 24, 9),
        aiReplyCount: 19,
        messages: longMessages,
        roundIndex: 4,
        visiblePracticeThreadId: 'thread-long-beginner',
        profileId: 'practice_girl_005',
        practiceMode: 'beginner',
        temperatureScore: 58,
        familiarityScore: 45,
        relationshipStageLabel: '可以聊個人',
      ));

      late List<PracticeTurnDto> hintTurns;
      api.hintHandler = (turns, {profile}) async {
        hintTurns = turns;
        return hintResult();
      };
      await c.requestHint();

      expect(hintTurns.length, lessThan(c.currentState.messages.length));
      expect(api.lastHintMemorySummary, contains('舊使用者訊息 0'));
      expect(api.lastHintMemorySummary, contains('舊使用者訊息 29'));

      late List<PracticeTurnDto> debriefTurns;
      api.debriefHandler = (turns, {profile}) async {
        debriefTurns = turns;
        return const PracticeDebrief(
          summary: '長 thread 拆解',
          strengths: ['有延續前文'],
          watchouts: [],
          suggestedLine: '接著她剛剛的咖啡話題問一句。',
          vibe: '自然',
        );
      };
      await c.endPractice();

      expect(debriefTurns.length, lessThan(c.currentState.messages.length));
      expect(api.lastDebriefMemorySummary, contains('舊使用者訊息 0'));
      expect(api.lastDebriefMemorySummary, contains('舊使用者訊息 29'));
    });

    // ── 續聊保溫：續同一位沿用上一輪溫度三元組 ──────────────────────────
    PracticeSession beginnerRound1Done() => PracticeSession(
          id: 'beginner-round1',
          createdAt: DateTime(2026, 6, 24, 9),
          aiReplyCount: 3,
          messages: const [
            PracticeMessage(role: 'user', text: '嗨'),
            PracticeMessage(role: 'ai', text: '嗯？'),
          ],
          roundIndex: 1,
          visiblePracticeThreadId: 'beginner-round1',
          profileId: 'practice_girl_005',
          practiceMode: 'beginner',
          temperatureScore: 42,
          familiarityScore: 10,
          relationshipStageLabel: '建立熟悉中',
          hintUsedCount: 2,
          debriefSummary: '不錯',
          debriefStrengths: const ['開場好'],
          debriefSuggestedLine: '約她',
          debriefVibe: '暖',
        );

    test('beginner 續玩：溫度三元組沿用上一輪，roundIndex+1、計數歸零', () {
      final c = makeControllerFrom(beginnerRound1Done());
      expect(c.currentState.temperatureScore, 42);

      c.continueWithSamePartner(isPaid: true);
      final s = c.currentState;

      expect(s.temperatureScore, 42);
      expect(s.familiarityScore, 10);
      expect(s.relationshipStageLabel, '建立熟悉中');
      expect(s.lastTemperatureDelta, isNull);
      expect(s.temperatureReason, isNull);
      expect(s.roundIndex, 2);
      expect(s.aiReplyCount, 0);
      expect(s.hintUsedCount, 0);
    });

    test('beginner 續玩後首則訊息：API 收到沿用的 temperatureScore 42', () async {
      final c = makeControllerFrom(beginnerRound1Done());
      c.continueWithSamePartner(isPaid: true);

      api.sendHandler = (_, {profile}) async => reply(cost: 0);
      await c.sendMessage('我們再聊聊');

      expect(api.lastPracticeMode, PracticeLearningMode.beginner);
      expect(api.lastTemperatureScore, 42);
      expect(api.lastFamiliarityScore, 10);
    });

    test('standard 續玩：溫度三元組仍為 null', () {
      final c = makeControllerFrom(round1Done());

      c.continueWithSamePartner(isPaid: true);
      final s = c.currentState;

      expect(s.temperatureScore, isNull);
      expect(s.familiarityScore, isNull);
      expect(s.relationshipStageLabel, isNull);
    });

    test('startSessionWithProfile（拆解後同一位）：溫度重設為難度初始值（排除範圍鎖定）', () {
      final c = makeControllerFrom(beginnerRound1Done());

      // 已拆解場不可 resume → 開全新 thread，溫度必須回難度初始值。
      c.startSessionWithProfile('practice_girl_005');
      final s = c.currentState;

      expect(s.roundIndex, 1);
      expect(s.temperatureScore, initialPracticeTemperatureScore(s.difficulty));
      expect(s.familiarityScore, kInitialPracticeFamiliarityScore);
      expect(
        s.relationshipStageLabel,
        kInitialPracticeRelationshipStageLabel,
      );
    });
  });

  // ── catalog-profile 身份接線 ─────────────────────────────────────────────
  group('catalog-profile 身份接線', () {
    test('續玩同一位：girl 不漂移', () {
      final c = makeControllerFrom(round1Done());
      final before = c.currentState.girl!.profileId;
      c.continueWithSamePartner(isPaid: true);
      expect(c.currentState.girl!.profileId, before);
    });

    test('帶 profileId 的場次 restore：girl 解析回該位', () {
      final c = makeControllerFrom(PracticeSession(
        id: 'with-id',
        createdAt: DateTime(2026, 6, 24, 9),
        aiReplyCount: 2,
        messages: const [PracticeMessage(role: 'user', text: '嗨')],
        profileId: 'practice_girl_005',
      ));
      expect(c.currentState.girl!.profileId, 'practice_girl_005');
    });

    test('舊場（無 profileId）restore：girl 兜底為預設位 practice_girl_001', () {
      final c = makeControllerFrom(PracticeSession(
        id: 'old',
        createdAt: DateTime(2026, 6, 24, 9),
        aiReplyCount: 1,
        messages: const [PracticeMessage(role: 'user', text: '嗨')],
      ));
      expect(c.currentState.girl!.profileId, 'practice_girl_001');
    });

    test('photoAssetPath 跟著 profileId：續玩不漂移、換一位（draw）才換', () async {
      final c = makeControllerFrom(round1Done());
      final asset0 = c.currentState.girl!.photoAssetPath;
      expect(asset0, endsWith('${c.currentState.girl!.profileId}.jpg'));

      c.continueWithSamePartner(isPaid: true);
      expect(c.currentState.girl!.photoAssetPath, asset0);

      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_010');
      await c.drawNewPracticeGirl();
      expect(c.currentState.girl!.photoAssetPath, isNot(asset0));
    });
  });

  group('beginner learning mode', () {
    test('standard mode sends no temperature metadata', () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async => reply(cost: 0);

      await c.sendMessage('hello');

      expect(c.currentState.learningMode, PracticeLearningMode.standard);
      expect(api.lastPracticeMode, PracticeLearningMode.standard);
      expect(api.lastTemperatureScore, isNull);
      expect(c.currentState.temperatureScore, isNull);
      expect(repo.getById(c.currentState.sessionId)!.practiceMode, 'standard');
    });

    test(
        'beginner mode sends current learning state and persists public returned state',
        () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      expect(c.currentState.temperatureScore, 28); // normal 難度起始溫度
      expect(c.currentState.familiarityScore, 0);
      expect(c.currentState.relationshipStageLabel, '建立熟悉中');

      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 38,
              delta: 8,
              band: 'cold',
              reason: '有具體延伸話題',
              familiarityScore: 10,
              familiarityDelta: 10,
              stageLabel: '建立熟悉中',
            ),
            hintUsedCount: 1,
          );

      await c.sendMessage('hello');

      final s = c.currentState;
      expect(api.lastPracticeMode, PracticeLearningMode.beginner);
      expect(api.lastTemperatureScore, 28); // normal 難度起始溫度
      expect(api.lastFamiliarityScore, 0);
      expect(s.temperatureScore, 38);
      expect(s.lastTemperatureDelta, 8);
      expect(s.temperatureReason, '有具體延伸話題');
      expect(s.familiarityScore, 10);
      expect(s.relationshipStageLabel, '建立熟悉中');
      expect(s.hintUsedCount, 1);

      final saved = repo.getById(s.sessionId)!;
      expect(saved.practiceMode, 'beginner');
      expect(saved.temperatureScore, 38);
      expect(saved.familiarityScore, 10);
      expect(saved.relationshipStageLabel, '建立熟悉中');
      expect(saved.hintUsedCount, 1);
    });

    test('SR game mode sends and persists beginner-like learning state',
        () async {
      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_004');
      final c = await makeRevealed();
      expect(c.currentState.girl?.rarity, PracticeGirlRarity.sr);

      await c.setPracticeLearningMode(PracticeLearningMode.game);
      expect(c.currentState.learningMode, PracticeLearningMode.game);
      expect(c.currentState.temperatureScore, 28);
      expect(c.currentState.familiarityScore, 0);

      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 38,
              delta: 8,
              band: 'cold',
              reason: 'game moved',
              familiarityScore: 10,
              familiarityDelta: 10,
              stageLabel: '建立熟悉中',
            ),
            hintUsedCount: 1,
          );

      await c.sendMessage('hello');

      final s = c.currentState;
      expect(api.lastPracticeMode, PracticeLearningMode.game);
      expect(api.lastTemperatureScore, 28);
      expect(api.lastFamiliarityScore, 0);
      expect(s.temperatureScore, 38);
      expect(s.familiarityScore, 10);
      expect(s.hintUsedCount, 1);

      final saved = repo.getById(s.sessionId)!;
      expect(saved.practiceMode, 'game');
      expect(saved.temperatureScore, 38);
      expect(saved.familiarityScore, 10);
      expect(saved.hintUsedCount, 1);
    });

    test('non-SR cards cannot switch to game mode locally before chat starts',
        () async {
      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_001');
      final c = await makeRevealed();
      expect(c.currentState.girl?.rarity, isNot(PracticeGirlRarity.sr));

      await c.setPracticeLearningMode(PracticeLearningMode.game);

      expect(c.currentState.learningMode, PracticeLearningMode.standard);
      expect(c.currentState.temperatureScore, isNull);
      expect(c.currentState.familiarityScore, isNull);
    });

    test('R cards cannot switch to game mode locally before chat starts',
        () async {
      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_010');
      final c = await makeRevealed();
      expect(c.currentState.girl?.rarity, PracticeGirlRarity.r);

      await c.setPracticeLearningMode(PracticeLearningMode.game);

      expect(c.currentState.learningMode, PracticeLearningMode.standard);
      expect(c.currentState.temperatureScore, isNull);
      expect(c.currentState.familiarityScore, isNull);
    });

    test('pre-message beginner mode is saved in draft and restored', () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);

      final draft = draftStore.load()!;
      expect(draft.learningMode, PracticeLearningMode.beginner);
      expect(draft.temperatureScore, initialPracticeTemperatureScore('normal'));
      expect(draft.familiarityScore, kInitialPracticeFamiliarityScore);
      expect(
        draft.relationshipStageLabel,
        kInitialPracticeRelationshipStageLabel,
      );

      final restored = makeController();
      expect(restored.currentState.learningMode, PracticeLearningMode.beginner);
      expect(
        restored.currentState.temperatureScore,
        initialPracticeTemperatureScore('normal'),
      );
      expect(
        restored.currentState.familiarityScore,
        kInitialPracticeFamiliarityScore,
      );
      expect(
        restored.currentState.relationshipStageLabel,
        kInitialPracticeRelationshipStageLabel,
      );
    });

    test('sendMessage forwards applied hint metadata only in beginner mode',
        () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(cost: 0);

      await c.sendMessage(
        '我也想聽你多講一點。',
        appliedHintType: PracticeHintReplyType.warmUp,
        appliedHintText: 'original hint reply',
      );

      expect(api.lastPracticeMode, PracticeLearningMode.beginner);
      expect(api.lastAppliedHintType, PracticeHintReplyType.warmUp);
      expect(api.lastAppliedHintText, 'original hint reply');
    });

    test('endPractice forwards copied Hint turns into debrief', () async {
      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_004');
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.game);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 34,
              delta: 4,
              band: 'cold',
              reason: '照提示穩住',
              familiarityScore: 12,
              familiarityDelta: 12,
            ),
          );

      const hintText = '我對妳剛說的那個點有點好奇，哪個部分最吸引妳？';
      await c.sendMessage(
        hintText,
        appliedHintType: PracticeHintReplyType.steady,
        appliedHintText: hintText,
      );
      api.debriefHandler = (_, {profile}) async => const PracticeDebrief(
            summary: '整體不錯',
            strengths: ['有照提示接住'],
            watchouts: [],
            suggestedLine: '補一句自己的感受',
            vibe: '中性',
          );

      await c.endPractice();

      final applied = api.lastDebriefAppliedHintTurns;
      expect(applied, isNotNull);
      expect(applied, hasLength(1));
      expect(applied!.single.turnIndex, 0);
      expect(applied.single.type, PracticeHintReplyType.steady);
      expect(applied.single.originalHintText, hintText);
      expect(applied.single.sentText, hintText);
      expect(applied.single.exact, true);
    });

    test('standard mode ignores applied hint metadata', () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async => reply(cost: 0);

      await c.sendMessage(
        '我也想聽你多講一點。',
        appliedHintType: PracticeHintReplyType.warmUp,
        appliedHintText: 'original hint reply',
      );

      expect(api.lastPracticeMode, PracticeLearningMode.standard);
      expect(api.lastAppliedHintType, isNull);
      expect(api.lastAppliedHintText, isNull);
    });

    test('restores beginner state from saved session', () {
      final c = makeControllerFrom(PracticeSession(
        id: 'beginner-resume',
        createdAt: DateTime(2026, 6, 28, 14),
        aiReplyCount: 1,
        messages: const [
          PracticeMessage(role: 'user', text: 'hi'),
          PracticeMessage(role: 'ai', text: 'hello'),
        ],
        profileId: 'practice_girl_005',
        practiceMode: 'beginner',
        temperatureScore: 44,
        familiarityScore: 46,
        relationshipStageLabel: '可以聊個人',
        hintUsedCount: 2,
      ));

      expect(c.currentState.learningMode, PracticeLearningMode.beginner);
      expect(c.currentState.temperatureScore, 44);
      expect(c.currentState.familiarityScore, 46);
      expect(c.currentState.relationshipStageLabel, '可以聊個人');
      expect(c.currentState.hintUsedCount, 2);
    });

    test('requestHint is beginner-only and uses existing AI turn', () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 34,
              delta: 4,
              band: 'cold',
              reason: '延伸得不錯',
            ),
            hintUsedCount: 0,
          );

      await c.requestHint();
      expect(api.hintCallCount, 0);

      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      await c.sendMessage('hello');
      api.hintHandler = (_, {profile}) async => hintResult();

      await c.requestHint();

      final s = c.currentState;
      expect(api.hintCallCount, 1);
      expect(api.lastHintRoundIndex, s.roundIndex);
      expect(api.lastHintThreadId, s.visiblePracticeThreadId);
      expect(s.hintReplies, hasLength(2));
      expect(s.hintCoaching, contains('接住情緒'));
      expect(s.hintUsedCount, 1);
      expect(s.isHintLoading, false);
      expect(synced, [
        [28, 13]
      ]);
      expect(repo.getById(s.sessionId)!.hintUsedCount, 1);
    });

    test('requestHint is available in game mode and forwards game mode',
        () async {
      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_004');
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.game);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 34,
              delta: 4,
              band: 'cold',
              reason: 'game moved',
              familiarityScore: 4,
              familiarityDelta: 4,
              stageLabel: '建立熟悉中',
            ),
            hintUsedCount: 0,
          );

      await c.sendMessage('hello');
      api.hintHandler = (_, {profile}) async => hintResult();

      await c.requestHint();

      expect(api.hintCallCount, 1);
      expect(api.lastHintPracticeMode, PracticeLearningMode.game);
      expect(c.currentState.hintReplies, hasLength(2));
    });

    test('requestHint marks limit reached without clearing chat', () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');
      api.hintHandler =
          (_, {profile}) async => throw PracticeHintLimitException();

      await c.requestHint();

      expect(c.currentState.hintLimitReached, true);
      expect(c.currentState.isHintLoading, false);
      expect(c.currentState.messages.map((m) => m.role), ['user', 'ai']);
      expect(c.currentState.errorMessage, isNotNull);
    });

    test('requestHint stops locally after the fifth hint in a round', () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');
      api.hintHandler = (_, {profile}) async => hintResult(
            cost: 1,
            hintUsedCount: 5,
          );

      await c.requestHint();

      expect(c.currentState.hintUsedCount, 5);
      expect(c.currentState.canRequestHint, false);

      await c.requestHint();

      expect(api.hintCallCount, 1);
      expect(c.currentState.errorMessage, isNull);
    });

    test('requestHint explains when user must wait for the AI reply', () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');
      api.hintHandler = (_, {profile}) async => throw PracticeApiException(
            'invalid_hint_last_turn_must_be_ai',
            status: 400,
          );

      await c.requestHint();

      expect(c.currentState.isHintLoading, false);
      expect(c.currentState.errorMessage, '要等對方回覆後，才能請 Hint。');
      expect(c.currentState.messages.map((m) => m.role), ['user', 'ai']);
    });

    test('requestHint explains backend readiness failure', () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');
      api.hintHandler = (_, {profile}) async =>
          throw PracticeGenerationFailedException('practice_hint_not_ready');

      await c.requestHint();

      expect(c.currentState.isHintLoading, false);
      expect(c.currentState.errorMessage, '提示服務正在更新中，請稍後再試。');
      expect(c.currentState.messages.map((m) => m.role), ['user', 'ai']);
    });

    test('requestHint 帶 requestId：5xx 失敗重試沿用同 id、成功才 rotate', () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      // 第一次 5xx 失敗：id 保留供重試
      api.hintHandler = (_, {profile}) async =>
          throw PracticeGenerationFailedException('boom');
      await c.requestHint();
      final firstId = api.lastHintRequestId;
      expect(firstId, isNotNull);

      // 重試成功：沿用同一 id（server 靠它去重雙扣）
      api.hintHandler = (_, {profile}) async => hintResult();
      await c.requestHint();
      expect(api.lastHintRequestId, firstId);

      // 成功後 rotate：下一次 hint 是新意圖 → 新 id
      await c.requestHint();
      expect(api.lastHintRequestId, isNotNull);
      expect(api.lastHintRequestId, isNot(firstId));
    });

    test('requestHint 模型限流 429：不標 quota、id 保留重試沿用', () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      // 限流 429：沒打模型、沒扣費、沒占 latch → id 保留供等待後重試
      api.hintHandler = (_, {profile}) async => throw PracticeApiException(
            '操作太頻繁，請稍等一分鐘再試。',
            status: 429,
          );
      await c.requestHint();
      final firstId = api.lastHintRequestId;
      expect(firstId, isNotNull);
      expect(c.currentState.quotaExceeded, false);
      expect(c.currentState.errorMessage, contains('太頻繁'));

      api.hintHandler = (_, {profile}) async => hintResult();
      await c.requestHint();
      expect(api.lastHintRequestId, firstId);
    });

    test('requestHint 4xx 明確拒絕 → rotate 新 id（不沿用）', () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      api.hintHandler = (_, {profile}) async => throw PracticeApiException(
            'invalid_hint_last_turn_must_be_ai',
            status: 400,
          );
      await c.requestHint();
      final firstId = api.lastHintRequestId;
      expect(firstId, isNotNull);

      api.hintHandler = (_, {profile}) async => hintResult();
      await c.requestHint();
      expect(api.lastHintRequestId, isNot(firstId));
    });

    test('requestHint 403 in-flight：不 rotate requestId、轉可重試錯誤', () async {
      // server 回 403 practice_hint_in_flight＝原請求還在跑（latch 占用中），
      // 不是明確拒絕：rotate 會把 id 從記憶體＋store 清掉，等原請求以舊 id
      // 入帳後，新 id 重試＝replay miss＝重新生成＝重複扣費。
      final pendingStore = InMemoryPracticePendingHintStore();
      final c = await makeRevealed(pendingHintStore: pendingStore);
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      api.hintHandler = (_, {profile}) async => throw PracticeApiException(
            'practice_hint_in_flight',
            status: 403,
          );
      await c.requestHint();
      final firstId = api.lastHintRequestId;
      expect(firstId, isNotNull);

      // 不 rotate：持久化 store 仍握著同一個 id（replay 保護活著）
      expect(pendingStore.load()!.requestId, firstId);
      // 可重試錯誤 state：loading 收掉、不標 quota、文案提示稍候再試
      expect(c.currentState.isHintLoading, false);
      expect(c.currentState.quotaExceeded, false);
      expect(c.currentState.errorMessage, '提示正在產生中，等一下再試。');
      expect(c.currentState.canRequestHint, true);
    });

    test('requestHint 403 in-flight 後重試：沿用同 id（server replay 不重扣）',
        () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      api.hintHandler = (_, {profile}) async => throw PracticeApiException(
            'practice_hint_in_flight',
            status: 403,
          );
      await c.requestHint();
      final firstId = api.lastHintRequestId;
      expect(firstId, isNotNull);

      // 原請求可能已在舊 id 名下寫入已扣費快照：重試沿用同 id 才吃得到 replay
      api.hintHandler = (_, {profile}) async => hintResult();
      await c.requestHint();
      expect(api.lastHintRequestId, firstId);
      expect(c.currentState.hintReplies, hasLength(2));
    });

    test('requestHint 其他 403（practice_session_not_started）仍照舊 rotate',
        () async {
      // in-flight 特例只認 code 字串：其他 403 明確拒絕維持 rotate，
      // 確認沒把整個 4xx 分支改壞。
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      api.hintHandler = (_, {profile}) async => throw PracticeApiException(
            'practice_session_not_started',
            status: 403,
          );
      await c.requestHint();
      final firstId = api.lastHintRequestId;
      expect(firstId, isNotNull);

      api.hintHandler = (_, {profile}) async => hintResult();
      await c.requestHint();
      expect(api.lastHintRequestId, isNot(firstId));
    });

    test('requestHint 掛住超過 client timeout → 可重試錯誤、不 rotate requestId',
        () async {
      final c = await makeRevealed(
        hintRequestTimeout: const Duration(milliseconds: 40),
      );
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      // API 掛住比 timeout 久：client 必須主動放棄，不能讓 loading 卡死等 server。
      api.hintHandler = (_, {profile}) => Future<PracticeHintResult>.delayed(
            const Duration(milliseconds: 300),
            hintResult,
          );
      await c.requestHint();
      final firstId = api.lastHintRequestId;
      expect(firstId, isNotNull);
      expect(c.currentState.isHintLoading, false);
      expect(c.currentState.hintReplies, isEmpty);
      expect(c.currentState.errorMessage, isNotNull);

      // timeout 不 rotate：重試沿用同 id（server 若已完成會 replay 不重扣）。
      api.hintHandler = (_, {profile}) async => hintResult();
      await c.requestHint();
      expect(api.lastHintRequestId, firstId);
      expect(c.currentState.hintReplies, hasLength(2));
    });

    test('sendMessage 掛住超過 client timeout → 回滾樂觀訊息並給可重試錯誤', () async {
      final c = await makeRevealed(
        sendMessageTimeout: const Duration(milliseconds: 40),
      );
      api.sendHandler = (_, {profile}) => Future<PracticeChatReply>.delayed(
            const Duration(milliseconds: 300),
            () => reply(),
          );

      await c.sendMessage('嗨');

      expect(c.currentState.isSending, false);
      expect(c.currentState.messages, isEmpty);
      expect(c.currentState.errorMessage, isNotNull);
      // timeout 時 server 可能已完成扣費：文案不得宣稱「這次不扣額度」。
      expect(c.currentState.errorMessage, isNot(contains('不扣額度')));
      expect(c.currentState.restoreText, '嗨');
    });

    test('hint timeout 失敗 → controller 重建（同持久化 store）→ 重試沿用同 requestId',
        () async {
      // controller 是 autoDispose：離開練習室後記憶體 id 消失，靠 store 沿用。
      final pendingStore = InMemoryPracticePendingHintStore();
      final c = await makeRevealed(pendingHintStore: pendingStore);
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      // timeout 失敗：id 保留（記憶體＋store）
      api.hintHandler =
          (_, {profile}) async => throw TimeoutException('timeout');
      await c.requestHint();
      final firstId = api.lastHintRequestId;
      expect(firstId, isNotNull);
      expect(pendingStore.load()!.requestId, firstId);

      // 模擬 autoDispose 重建：從 repo 還原同一場、共用同一個持久化 store
      final rebuilt = makeControllerFrom(
        repo.getById(c.currentState.sessionId)!,
        pendingHintStore: pendingStore,
      );
      api.hintHandler = (_, {profile}) async => hintResult();
      await rebuilt.requestHint();

      // 沿用同 id → server 才能 replay 已扣費的結果，不重扣
      expect(api.lastHintRequestId, firstId);
      // 成功 → rotate：store 也清掉
      expect(pendingStore.load(), isNull);
    });

    test('重建後已是不同 turn（aiCount 變了）→ 不沿用舊 requestId', () async {
      final pendingStore = InMemoryPracticePendingHintStore();
      final c = await makeRevealed(pendingHintStore: pendingStore);
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      api.hintHandler =
          (_, {profile}) async => throw TimeoutException('timeout');
      await c.requestHint();
      final firstId = api.lastHintRequestId;
      expect(firstId, isNotNull);

      // 重建後又聊了一輪（aiReplyCount 1→2）＝store 指紋不吻合，舊 id 作廢
      final rebuilt = makeControllerFrom(
        repo.getById(c.currentState.sessionId)!,
        pendingHintStore: pendingStore,
      );
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            aiTurnCount: 2,
            temperature: const PracticeTemperature(
              score: 32,
              delta: 2,
              band: 'cold',
              reason: '延伸',
            ),
          );
      await rebuilt.sendMessage('再聊一句');

      api.hintHandler = (_, {profile}) async => hintResult();
      await rebuilt.requestHint();

      expect(api.lastHintRequestId, isNotNull);
      expect(api.lastHintRequestId, isNot(firstId));
    });

    test('同 controller：hint timeout 後對話推進（sendMessage 成功）→ 新回合 hint 鑄新 id',
        () async {
      // 記憶體 pending id 也必須綁回合指紋：對話推進後沿用舊 id，
      // server 會 replay 上一回合的舊 hint＝牛頭不對馬嘴。
      final pendingStore = InMemoryPracticePendingHintStore();
      final c = await makeRevealed(pendingHintStore: pendingStore);
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      // timeout：id 保留（同回合重試沿用）
      api.hintHandler =
          (_, {profile}) async => throw TimeoutException('timeout');
      await c.requestHint();
      final firstId = api.lastHintRequestId;
      expect(firstId, isNotNull);

      // 同一個 controller 繼續聊：對話推進（aiReplyCount 1→2）＝舊 id 過期
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            aiTurnCount: 2,
            temperature: const PracticeTemperature(
              score: 32,
              delta: 2,
              band: 'cold',
              reason: '延伸',
            ),
          );
      await c.sendMessage('再聊一句');

      api.hintHandler = (_, {profile}) async => hintResult();
      await c.requestHint();

      expect(api.lastHintRequestId, isNotNull);
      expect(api.lastHintRequestId, isNot(firstId));
    });

    test('同 controller：hint timeout 後 sendMessage 失敗回滾 → 回合未推進，重試沿用同 id',
        () async {
      // sendMessage 失敗＝回合沒推進：舊 id 的 replay 保護不得被誤清，
      // 否則 server 已扣費的結果吃不到 replay 會重複扣費。
      final pendingStore = InMemoryPracticePendingHintStore();
      final c = await makeRevealed(pendingHintStore: pendingStore);
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      api.hintHandler =
          (_, {profile}) async => throw TimeoutException('timeout');
      await c.requestHint();
      final firstId = api.lastHintRequestId;
      expect(firstId, isNotNull);

      // sendMessage 失敗回滾：aiReplyCount 不變
      api.sendHandler = (_, {profile}) async => throw Exception('network');
      await c.sendMessage('這句送不出去');
      expect(c.currentState.errorMessage, isNotNull);

      api.hintHandler = (_, {profile}) async => hintResult();
      await c.requestHint();

      expect(api.lastHintRequestId, firstId);
      expect(c.currentState.hintReplies, hasLength(2));
    });

    test('requestHint mode locked（409）：同文案、isHintLoading 復位、不標 sessionComplete',
        () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');
      api.hintHandler =
          (_, {profile}) async => throw PracticeModeLockedException();

      await c.requestHint();

      expect(c.currentState.isHintLoading, false);
      expect(c.currentState.sessionComplete, false);
      expect(
        c.currentState.errorMessage,
        '這位陪練女孩這一輪已用另一種模式進行中，請切回原本的模式繼續',
      );
      expect(c.currentState.messages.map((m) => m.role), ['user', 'ai']);
    });

    // ── 過期 hint 丟棄（generation 序號）──────────────────────────────────
    /// 進到「beginner、已有 ai 回覆、hint 在途（completer 未完成）」的共用起手式。
    Future<
        (
          PracticeChatController,
          Completer<PracticeHintResult>,
          Future<void>
        )> pendingHint() async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c.sendMessage('hello');

      final completer = Completer<PracticeHintResult>();
      api.hintHandler = (_, {profile}) => completer.future;
      final hintFuture = c.requestHint();
      expect(c.currentState.isHintLoading, true);
      return (c, completer, hintFuture);
    }

    test('續玩同一位期間在途 hint 回來 → 丟棄不填 state、isHintLoading 復位、額度仍同步', () async {
      final (c, completer, hintFuture) = await pendingHint();

      c.continueWithSamePartner(isPaid: true);
      completer.complete(hintResult());
      await hintFuture;

      final s = c.currentState;
      expect(s.hintReplies, isEmpty); // 過期內容不填回 UI
      expect(s.hintCoaching, isNull);
      expect(s.hintUsedCount, 0); // 新一輪計數不被舊回應污染
      expect(s.isHintLoading, false);
      expect(repo.getById(s.sessionId), isNull); // 不把舊 hint 持久化進新場
      // 已扣額度認列不回滾（server 事實）：剩餘額度照樣同步
      expect(synced, [
        [28, 13]
      ]);
    });

    test('換一位（draw）期間在途 hint 回來 → 丟棄、不污染新對象 state', () async {
      final (c, completer, hintFuture) = await pendingHint();

      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_011');
      await c.drawNewPracticeGirl();

      completer.complete(hintResult());
      await hintFuture;

      expect(c.currentState.girl!.profileId, 'practice_girl_011');
      expect(c.currentState.hintReplies, isEmpty);
      expect(c.currentState.hintUsedCount, 0);
      expect(c.currentState.isHintLoading, false);
    });

    test('續玩後在途 hint 失敗回來 → 過期錯誤不打擾新狀態（無 errorMessage/旗標）', () async {
      final (c, completer, hintFuture) = await pendingHint();

      c.continueWithSamePartner(isPaid: true);
      completer.completeError(PracticeQuotaExceededException('本月額度已用完'));
      await hintFuture;

      expect(c.currentState.errorMessage, isNull);
      expect(c.currentState.quotaExceeded, false);
      expect(c.currentState.isHintLoading, false);
    });

    test('過期舊 hint 完成 → 不得清掉較新 hint 的 pending requestId（replay 保護）', () async {
      // 舊 hint A 在途 → 續玩換場 → 新 hint B 在途（已存新 pending id）→
      // A 這時才回來：rotate 只認自己的 id，B 的 id 必須活下來供重試沿用。
      final (c, completerA, hintFutureA) = await pendingHint();

      c.continueWithSamePartner(isPaid: true);
      await c.sendMessage('新一輪 hello');

      final completerB = Completer<PracticeHintResult>();
      api.hintHandler = (_, {profile}) => completerB.future;
      final hintFutureB = c.requestHint();
      final bId = api.lastHintRequestId;
      expect(bId, isNotNull);

      // 過期的 A 成功回來：不得動到 B 的 pending id
      completerA.complete(hintResult());
      await hintFutureA;

      // B 之後 5xx 失敗 → 重試必須沿用 B 的同一個 id（若被 A 清掉會鑄新 id）
      completerB.completeError(PracticeGenerationFailedException('提示產生失敗'));
      await hintFutureB;
      api.hintHandler = (_, {profile}) async => hintResult();
      await c.requestHint();
      expect(api.lastHintRequestId, bId);
    });

    test('舊 controller dispose 後晚到的完成 → 不得清掉新 controller 的 pending id',
        () async {
      // autoDispose 情境：舊 controller 的在途 hint A 晚到時，共用 store 裡
      // 已是新 controller 的 id B——store 只有現值＝A 才可清。
      final pendingStore = InMemoryPracticePendingHintStore();
      final c1 = await makeRevealed(pendingHintStore: pendingStore);
      await c1.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            temperature: const PracticeTemperature(
              score: 30,
              delta: 0,
              band: 'cold',
              reason: '維持',
            ),
          );
      await c1.sendMessage('hello');

      final completerA = Completer<PracticeHintResult>();
      api.hintHandler = (_, {profile}) => completerA.future;
      final hintFutureA = c1.requestHint();
      final aId = api.lastHintRequestId;

      // 模擬重建：新 controller 共用 store，聊到下一個 turn 後發起 hint B
      // （timeout 失敗 → B 的 id 保留在 store 供重試）
      final c2 = makeControllerFrom(
        repo.getById(c1.currentState.sessionId)!,
        pendingHintStore: pendingStore,
      );
      api.sendHandler = (_, {profile}) async => reply(
            cost: 0,
            aiTurnCount: 2, // 下一個 turn：讓 B 的指紋與 A（aiCount=1）不同
            temperature: const PracticeTemperature(
              score: 32,
              delta: 2,
              band: 'cold',
              reason: '升溫',
            ),
          );
      await c2.sendMessage('again');
      api.hintHandler =
          (_, {profile}) async => throw TimeoutException('timeout');
      await c2.requestHint();
      final bId = api.lastHintRequestId;
      expect(bId, isNot(aId));
      expect(pendingStore.load()!.requestId, bId);

      // A 晚到成功：只能清自己的；B 的 replay 保護必須活著
      completerA.complete(hintResult());
      await hintFutureA;
      expect(pendingStore.load()!.requestId, bId);
    });

    test('hint 在途時 canSend=false（雙向互斥）、sendMessage no-op，完成後恢復', () async {
      final (c, completer, hintFuture) = await pendingHint();
      expect(c.currentState.canSend, false);

      // 在途時搶送：不打 API、不長泡泡
      var sendCalled = false;
      api.sendHandler = (_, {profile}) async {
        sendCalled = true;
        return reply();
      };
      await c.sendMessage('搶著送');
      expect(sendCalled, false);
      expect(c.currentState.messages, hasLength(2));

      completer.complete(hintResult());
      await hintFuture;
      expect(c.currentState.isHintLoading, false);
      expect(c.currentState.canSend, true);
    });

    test('requestHint maps backend gate codes to clear copy', () async {
      final cases = [
        ('practice_hint_in_flight', '提示正在產生中，等一下再試。'),
        ('practice_hint_beginner_only', '這場不是新手模式，下一場切到新手模式再用 Hint。'),
        ('practice_mode_locked', '這場不是新手模式，下一場切到新手模式再用 Hint。'),
      ];

      for (final (code, expectedMessage) in cases) {
        final c = await makeRevealed();
        await c.setPracticeLearningMode(PracticeLearningMode.beginner);
        api.sendHandler = (_, {profile}) async => reply(
              cost: 0,
              temperature: const PracticeTemperature(
                score: 30,
                delta: 0,
                band: 'cold',
                reason: '維持',
              ),
            );
        await c.sendMessage('hello');
        api.hintHandler = (_, {profile}) async =>
            throw PracticeApiException(code, status: 403);

        await c.requestHint();

        expect(c.currentState.isHintLoading, false);
        expect(c.currentState.errorMessage, expectedMessage);
        expect(c.currentState.messages.map((m) => m.role), ['user', 'ai']);
      }
    });
  });

  // ── 圖鑑解鎖記錄（onProfileUnlocked side-channel）────────────────────────
  group('圖鑑解鎖記錄 onProfileUnlocked', () {
    PracticeChatController makeCollector(
      List<String> sink, {
      PracticeSession? initialSession,
      void Function(String)? onProfileUnlocked,
    }) {
      final c = PracticeChatController(
        api: api,
        repository: repo,
        draftStore: draftStore,
        onProfileUnlocked: onProfileUnlocked ?? sink.add,
        initialSession: initialSession,
        sessionId: initialSession == null ? 'sess-1' : null,
        createdAt: initialSession == null ? DateTime(2026, 6, 26, 13, 0) : null,
      );
      addTearDown(c.dispose);
      return c;
    }

    PracticeSession openSession(String profileId) => PracticeSession(
          id: 'open-1',
          createdAt: DateTime(2026, 6, 26, 12),
          aiReplyCount: 1,
          messages: const [
            PracticeMessage(role: 'user', text: '嗨'),
            PracticeMessage(role: 'ai', text: '嗯？'),
          ],
          profileId: profileId,
        );

    test('locked 進場（無 session／draft）→ 不觸發', () async {
      final unlocked = <String>[];
      makeCollector(unlocked);
      await pumpEventQueue();
      expect(unlocked, isEmpty);
    });

    test('翻牌成功 → 記錄抽到的 profileId', () async {
      final unlocked = <String>[];
      final c = makeCollector(unlocked);
      await c.drawNewPracticeGirl();
      await pumpEventQueue();
      expect(unlocked, ['practice_girl_010']);
    });

    test('翻牌失敗 → 不記錄', () async {
      api.drawHandler = ({currentProfileId}) async => throw Exception('boom');
      final unlocked = <String>[];
      final c = makeCollector(unlocked);
      await c.drawNewPracticeGirl();
      await pumpEventQueue();
      expect(unlocked, isEmpty);
    });

    test('initialSession 還原 → 種子記錄該場 profileId', () async {
      final unlocked = <String>[];
      makeCollector(unlocked, initialSession: openSession('practice_girl_009'));
      await pumpEventQueue();
      expect(unlocked, ['practice_girl_009']);
    });

    test('有效 draft 還原 → 種子記錄 draft 的 profileId', () async {
      await draftStore.save(draftFor('practice_girl_005'));
      final unlocked = <String>[];
      makeCollector(unlocked);
      await pumpEventQueue();
      expect(unlocked, ['practice_girl_005']);
    });

    test('resumeSession → 記錄該場 profileId', () async {
      final unlocked = <String>[];
      final c = makeCollector(unlocked);
      await pumpEventQueue();
      expect(unlocked, isEmpty);

      c.resumeSession(openSession('practice_girl_009'));
      await pumpEventQueue();
      expect(unlocked, ['practice_girl_009']);
    });

    test('callback 丟例外 → 翻牌主流程不受影響', () async {
      final c = makeCollector(
        <String>[],
        onProfileUnlocked: (_) => throw StateError('collection boom'),
      );
      await c.drawNewPracticeGirl();
      await pumpEventQueue();
      expect(c.currentState.drawStatus, PracticeDrawStatus.revealed);
      expect(c.currentState.girl!.profileId, 'practice_girl_010');
    });
  });

  // ── 圖鑑點已抽卡進對話：startSessionWithProfile ──────────────────────────
  group('startSessionWithProfile', () {
    PracticeSession openSessionFor(String profileId) => PracticeSession(
          id: 'open-9',
          createdAt: DateTime(2026, 6, 26, 12),
          aiReplyCount: 1,
          messages: const [
            PracticeMessage(role: 'user', text: '嗨'),
            PracticeMessage(role: 'ai', text: '嗯？'),
          ],
          profileId: profileId,
        );

    test('無既有場次 → 以該角色免費開新局（revealed、空 transcript、第 1 輪）', () {
      final c = makeController();
      expect(c.currentState.drawStatus, PracticeDrawStatus.locked);

      c.startSessionWithProfile('practice_girl_005');

      final s = c.currentState;
      expect(s.girl!.profileId, 'practice_girl_005');
      expect(s.drawStatus, PracticeDrawStatus.revealed);
      expect(s.messages, isEmpty);
      expect(s.roundIndex, 1);
      expect(s.visiblePracticeThreadId, s.sessionId);
    });

    test('有既有場次 → 續玩該場（sessionId 相同、transcript 保留）', () async {
      await repo.save(openSessionFor('practice_girl_009'));
      final c = makeController();

      c.startSessionWithProfile('practice_girl_009');

      final s = c.currentState;
      expect(s.sessionId, 'open-9');
      expect(s.girl!.profileId, 'practice_girl_009');
      expect(s.messages.map((m) => m.text), ['嗨', '嗯？']);
      expect(s.drawStatus, PracticeDrawStatus.revealed);
    });

    test('只剩已完成（debrief）場 → 不 resume，免費開新局（Codex R1 P2）', () async {
      await repo.save(PracticeSession(
        id: 'done-9',
        createdAt: DateTime(2026, 6, 26, 14),
        aiReplyCount: 2,
        debriefSummary: '拆解完了',
        messages: const [
          PracticeMessage(role: 'user', text: '嗨'),
          PracticeMessage(role: 'ai', text: '嗯？'),
        ],
        profileId: 'practice_girl_009',
      ));
      final c = makeController();

      c.startSessionWithProfile('practice_girl_009');

      final s = c.currentState;
      expect(s.sessionId, isNot('done-9')); // 已拆解場不可續玩（比照 _canResume）
      expect(s.girl!.profileId, 'practice_girl_009');
      expect(s.messages, isEmpty);
      expect(s.roundIndex, 1);
    });

    test('較新已完成場＋較舊未完成場 → 續玩較舊未完成場', () async {
      await repo.save(openSessionFor('practice_girl_009'));
      await repo.save(PracticeSession(
        id: 'done-9-newer',
        createdAt: DateTime(2026, 6, 27, 9),
        aiReplyCount: 2,
        debriefSummary: '拆解完了',
        messages: const [PracticeMessage(role: 'user', text: '第二場')],
        profileId: 'practice_girl_009',
      ));
      final c = makeController();

      c.startSessionWithProfile('practice_girl_009');

      final s = c.currentState;
      expect(s.sessionId, 'open-9');
      expect(s.messages.map((m) => m.text), ['嗨', '嗯？']);
    });

    test('開新局不打 draw API、不寫翻牌 draft／pending draw', () {
      final pendingStore = InMemoryPracticePendingDrawStore();
      final c = makeController(pendingDrawStore: pendingStore);

      c.startSessionWithProfile('practice_girl_005');

      expect(c.currentState.girl!.profileId, 'practice_girl_005');
      expect(api.drawCallCount, 0); // 不打 drawProfile
      expect(draftStore.load(), isNull); // 不寫翻牌 draft
      expect(pendingStore.load(), isNull); // 不碰 pending draw store
    });

    test('catalog 解析不到 profileId → 不碰 state', () {
      final c = makeController();
      final before = c.currentState;

      c.startSessionWithProfile('no_such_profile');

      expect(identical(c.currentState, before), isTrue);
    });

    test('prior 帶錯誤旗標 → 開新局重設 errorMessage 與 draw 旗標', () async {
      // 先讓翻牌吃 402，製造 errorMessage 非 null＋drawUpgradeRequired 的 prior。
      api.drawHandler = ({currentProfileId}) async =>
          throw PracticeDrawUpgradeRequiredException(extraCostMessages: 5);
      final c = makeController();
      await c.drawNewPracticeGirl();
      expect(c.currentState.errorMessage, isNotNull);
      expect(c.currentState.drawUpgradeRequired, true);

      c.startSessionWithProfile('practice_girl_005');

      final s = c.currentState;
      expect(s.girl!.profileId, 'practice_girl_005');
      expect(s.errorMessage, isNull);
      expect(s.drawUpgradeRequired, false);
      expect(s.drawQuotaExceeded, false);
    });
  });

  group('案2：practice 溫度歷史事件', () {
    test('beginner 模式收到溫度 → endPractice 收操落一筆 practice 事件', () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            temperature: const PracticeTemperature(
              score: 38,
              delta: 8,
              band: 'cold',
              reason: '有具體延伸話題',
              familiarityScore: 12,
              familiarityDelta: 12,
              stageLabel: '破冰',
            ),
          );
      await c.sendMessage('嗨');
      api.debriefHandler = (_, {profile}) async => const PracticeDebrief(
            summary: '整體不錯',
            strengths: ['開場自然'],
            watchouts: [],
            suggestedLine: '下次直接約她',
            vibe: '暖',
          );
      await c.endPractice();

      expect(history.events.length, 1);
      final event = history.events.single;
      expect(event.kind, AnalysisHistoryKind.practice);
      expect(event.profileId, isNotNull);
      expect(event.roundIndex, 1);
      expect(event.temperatureScore, 38);
      expect(event.familiarityScore, 12);
      expect(event.relationshipStageLabel, '破冰');
    });

    test('新手模式局中多次送訊息＋求 hint 絕不寫事件，收操恰記一筆終溫', () async {
      final c = await makeRevealed();
      await c.setPracticeLearningMode(PracticeLearningMode.beginner);
      api.sendHandler = (_, {profile}) async => reply(
            temperature: const PracticeTemperature(
              score: 38,
              delta: 8,
              band: 'cold',
              reason: '有具體延伸話題',
              familiarityScore: 12,
              familiarityDelta: 12,
              stageLabel: '破冰',
            ),
          );
      await c.sendMessage('嗨');
      api.sendHandler = (_, {profile}) async => reply(
            temperature: const PracticeTemperature(
              score: 45,
              delta: 7,
              band: 'warm',
              reason: '互動加溫',
              familiarityScore: 20,
              familiarityDelta: 8,
              stageLabel: '建立熟悉中',
            ),
          );
      await c.sendMessage('妳今天過得如何');
      api.hintHandler = (_, {profile}) async => hintResult();
      await c.requestHint();

      expect(history.events, isEmpty); // 局中（送訊息/hint 的 _persist）絕不寫

      api.debriefHandler = (_, {profile}) async => const PracticeDebrief(
            summary: '整體不錯',
            strengths: ['開場自然'],
            watchouts: [],
            suggestedLine: '下次直接約她',
            vibe: '暖',
          );
      await c.endPractice();

      expect(history.events.length, 1); // 每局收操恰一筆
      expect(history.events.single.temperatureScore, 45); // 記終溫
    });

    test('standard 模式（temperatureScore null）→ 絕不寫事件', () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async => reply();
      await c.sendMessage('嗨');

      expect(history.events, isEmpty);
    });

    test('endPractice（debrief 後 _persist）也只在有溫度時寫', () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async => reply();
      api.debriefHandler = (_, {profile}) async => const PracticeDebrief(
            summary: '整體不錯',
            strengths: ['開場自然'],
            watchouts: [],
            suggestedLine: '下次直接約她',
            vibe: '暖',
          );
      await c.sendMessage('嗨');
      await c.endPractice();

      expect(history.events, isEmpty); // standard 全程無溫度
    });
  });
}

/// 測試用翻牌回應：從 catalog 取真實對象身份，draw/usage 用參數覆寫。
PracticeDrawResult drawResult({
  String profileId = 'practice_girl_010',
  int cost = 0,
  int freeAllowance = 1,
  int freeUsed = 1,
  int freeRemaining = 0,
  int extraCost = 5,
  String nextResetAt = '2999-01-01T04:00:00.000Z',
  int monthlyUsed = 0,
  int monthlyLimit = 30,
  int dailyUsed = 0,
  int dailyLimit = 30,
}) {
  final g = girlProfileById(profileId)!;
  return PracticeDrawResult(
    profile: PracticeDrawnProfile(
      profileId: g.profileId,
      nameId: g.nameId,
      professionId: g.professionId,
      photoId: g.photoId,
      personaId: g.personaId,
    ),
    draw: PracticeDrawReceipt(
      costMessages: cost,
      freeAllowance: freeAllowance,
      freeUsed: freeUsed,
      freeRemaining: freeRemaining,
      extraCostMessages: extraCost,
      nextResetAt: nextResetAt,
    ),
    usage: PracticeDrawUsage(
      monthlyUsed: monthlyUsed,
      monthlyLimit: monthlyLimit,
      dailyUsed: dailyUsed,
      dailyLimit: dailyLimit,
    ),
  );
}
