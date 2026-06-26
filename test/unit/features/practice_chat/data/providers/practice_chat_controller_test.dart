import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_draw_draft_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_draw_draft.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_profile.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';

class _FakeApi extends PracticeChatApiService {
  Future<PracticeChatReply> Function(
    List<PracticeTurnDto> turns, {
    PracticeProfileDto? profile,
  })? sendHandler;
  Future<PracticeDebrief> Function(
    List<PracticeTurnDto> turns, {
    PracticeProfileDto? profile,
  })? debriefHandler;
  Future<PracticeDrawResult> Function({String? currentProfileId})? drawHandler;

  // 續玩 metadata 捕捉。
  int? lastRoundIndex;
  String? lastVisibleThreadId;
  int? lastDebriefRoundIndex;
  String? lastDebriefThreadId;

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
  }) {
    lastRoundIndex = roundIndex;
    lastVisibleThreadId = visiblePracticeThreadId;
    return sendHandler!(turns, profile: profile);
  }

  @override
  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
  }) {
    lastDebriefRoundIndex = roundIndex;
    lastDebriefThreadId = visiblePracticeThreadId;
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
    // 預設翻牌回一位固定對象（far-future reset → 草稿不過期）。
    api.drawHandler = ({currentProfileId}) async => drawResult();
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  PracticeChatController makeController() {
    final c = PracticeChatController(
      api: api,
      repository: repo,
      draftStore: draftStore,
      onUsageSynced: ({required monthlyRemaining, required dailyRemaining}) {
        synced.add([monthlyRemaining, dailyRemaining]);
      },
      sessionId: 'sess-1',
      createdAt: DateTime(2026, 6, 26, 13, 0),
    );
    addTearDown(c.dispose);
    return c;
  }

  PracticeChatController makeControllerFrom(PracticeSession session) {
    final c = PracticeChatController(
      api: api,
      repository: repo,
      draftStore: draftStore,
      onUsageSynced: ({required monthlyRemaining, required dailyRemaining}) {
        synced.add([monthlyRemaining, dailyRemaining]);
      },
      initialSession: session,
    );
    addTearDown(c.dispose);
    return c;
  }

  /// 進到 revealed（翻好一張牌）的 controller，給「需要先有對象才能聊天」的測試用。
  Future<PracticeChatController> makeRevealed() async {
    final c = makeController();
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
  }) =>
      PracticeChatReply(
        reply: text,
        aiTurnCount: aiTurnCount,
        sessionComplete: complete,
        costDeducted: cost,
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
    test('成功 → revealed、girl=server 回的對象、roundIndex 1、threadId=新 sessionId', () async {
      api.drawHandler =
          ({currentProfileId}) async => drawResult(profileId: 'practice_girl_010');
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
      api.drawHandler = ({currentProfileId}) async =>
          drawResult(profileId: 'practice_girl_010', nextResetAt: '2999-01-01T04:00:00.000Z');
      final c = makeController();

      await c.drawNewPracticeGirl();

      final draft = draftStore.load();
      expect(draft, isNotNull);
      expect(draft!.profileId, 'practice_girl_010');
      expect(draft.nextResetAt, DateTime.utc(2999, 1, 1, 4));
      expect(draft.sessionId, c.currentState.sessionId);
      expect(repo.recentSessions(), isEmpty); // 不造假歷史
    });

    test('換一位（已 revealed 再抽）→ 帶 currentProfileId 排除目前這位', () async {
      api.drawHandler =
          ({currentProfileId}) async => drawResult(profileId: 'practice_girl_010');
      final c = await makeRevealed();
      final firstId = c.currentState.girl!.profileId;

      api.drawHandler =
          ({currentProfileId}) async => drawResult(profileId: 'practice_girl_011');
      await c.drawNewPracticeGirl();

      expect(api.lastDrawCurrentProfileId, firstId);
      expect(c.currentState.girl!.profileId, 'practice_girl_011');
    });

    test('402 → drawUpgradeRequired、保留原狀態（仍 locked、girl null）、不存 draft', () async {
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
      api.drawHandler =
          ({currentProfileId}) async => drawResult(profileId: 'practice_girl_010');
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
      api.drawHandler =
          ({currentProfileId}) async => drawResult(cost: 0);
      final c = makeController();
      await c.drawNewPracticeGirl();
      expect(synced, isEmpty);
    });
  });

  // ── 換一位入口都走 draw；續玩/切難度都不走 draw ───────────────────────────
  group('入口路由', () {
    test('startNewPartner → 走 draw', () async {
      final c = makeControllerFrom(round1Done());
      expect(api.drawCallCount, 0);
      await c.startNewPartner();
      expect(api.drawCallCount, 1);
    });

    test('regeneratePersona → 走 draw', () async {
      final c = await makeRevealed();
      final before = api.drawCallCount;
      await c.regeneratePersona();
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

    test('翻牌後送訊息帶上 server 給的 girl 身份', () async {
      api.drawHandler =
          ({currentProfileId}) async => drawResult(profileId: 'practice_girl_010');
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
      api.sendHandler =
          (_, {profile}) async => throw PracticeGenerationFailedException('boom');

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
      api.sendHandler = (_, {profile}) async => throw PracticeQuotaExceededException(
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
    test('產拆解卡、鎖定、持久化拆解欄位', () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async => reply();
      await c.sendMessage('嗨');

      api.debriefHandler = (_, {profile}) async => const PracticeDebrief(
            summary: '整體不錯',
            strengths: ['開場自然'],
            watchouts: [],
            suggestedLine: '下次直接約她',
            vibe: '暖',
          );
      await c.endPractice();
      final s = c.currentState;

      expect(s.debrief, isNotNull);
      expect(s.sessionComplete, true);
      expect(repo.getById(s.sessionId)!.debriefSummary, '整體不錯');
    });

    test('locked 時 endPractice 為 no-op', () async {
      final c = makeController();
      await c.endPractice();
      expect(c.currentState.debrief, isNull);
      expect(c.currentState.isDebriefing, false);
    });

    test('拆解失敗：標示失敗並鎖住輸入', () async {
      final c = await makeRevealed();
      api.sendHandler = (_, {profile}) async => reply();
      await c.sendMessage('嗨');

      api.debriefHandler =
          (_, {profile}) async => throw PracticeGenerationFailedException('boom');
      await c.endPractice();
      final s = c.currentState;

      expect(s.debrief, isNull);
      expect(s.debriefFailed, true);
      expect(s.ended, true);
      expect(s.canSend, false);
      expect(s.canDebrief, true);
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

    test('sendMessage 帶上 state 的 roundIndex 與 visiblePracticeThreadId', () async {
      api.sendHandler = (_, {profile}) async => reply(cost: 0);
      final c = resumeR2();
      await c.sendMessage('在嗎');
      expect(api.lastRoundIndex, 2);
      expect(api.lastVisibleThreadId, 'thread-x');
    });

    test('endPractice 帶上 state 的 roundIndex 與 visiblePracticeThreadId', () async {
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

    test('roundIndex 已達上限 3：付費續玩為 no-op', () {
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
      expect(c.currentState.sessionId, before.sessionId);
      expect(c.currentState.roundIndex, 3);
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
  });

  // ── 60-profile 身份接線 ──────────────────────────────────────────────────
  group('60-profile 身份接線', () {
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

      api.drawHandler =
          ({currentProfileId}) async => drawResult(profileId: 'practice_girl_010');
      await c.startNewPartner();
      expect(c.currentState.girl!.photoAssetPath, isNot(asset0));
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
