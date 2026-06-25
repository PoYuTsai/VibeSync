import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
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

  // 續玩 metadata 捕捉：驗 controller 是否把 state 的 roundIndex/threadId 帶進 API。
  int? lastRoundIndex;
  String? lastVisibleThreadId;
  int? lastDebriefRoundIndex;
  String? lastDebriefThreadId;

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
}

void main() {
  late Box<PracticeSession> box;
  late PracticeSessionRepository repo;
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
    api = _FakeApi();
    synced = [];
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  PracticeChatController makeController() {
    final c = PracticeChatController(
      api: api,
      repository: repo,
      onUsageSynced: ({required monthlyRemaining, required dailyRemaining}) {
        synced.add([monthlyRemaining, dailyRemaining]);
      },
      sessionId: 'sess-1',
      createdAt: DateTime(2026, 6, 24, 10, 0),
    );
    addTearDown(c.dispose);
    return c;
  }

  PracticeChatController makeControllerFrom(PracticeSession session) {
    final c = PracticeChatController(
      api: api,
      repository: repo,
      onUsageSynced: ({required monthlyRemaining, required dailyRemaining}) {
        synced.add([monthlyRemaining, dailyRemaining]);
      },
      initialSession: session,
    );
    addTearDown(c.dispose);
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

  test('送訊息成功：附上 user+ai 泡泡、更新計數、扣點同步、持久化', () async {
    api.sendHandler = (_, {profile}) async => reply();
    final c = makeController();

    await c.sendMessage('嗨');
    final s = c.currentState;

    expect(s.messages.map((m) => m.role).toList(), ['user', 'ai']);
    expect(s.messages.last.text, '嗯？');
    expect(s.aiReplyCount, 1);
    expect(s.isSending, false);
    expect(synced, [
      [29, 14]
    ]);
    expect(repo.getById('sess-1'), isNotNull);
  });

  test('新場次會帶固定 profile，送訊息與拆解都沿用同一組', () async {
    final c = makeController();

    expect(c.currentState.personaId, isNotEmpty);
    expect(c.currentState.personaLabel, isNotEmpty);
    expect(c.currentState.difficulty, 'normal');
    expect(c.currentState.difficultyLabel, '一般');

    PracticeProfileDto? sentProfile;
    api.sendHandler = (turns, {profile}) async {
      sentProfile = profile;
      return reply();
    };

    await c.sendMessage('嗨');

    expect(sentProfile!.personaId, c.currentState.personaId);
    expect(sentProfile!.difficulty, c.currentState.difficulty);
    final saved = repo.getById(c.currentState.sessionId)!;
    expect(saved.personaId, c.currentState.personaId);
    expect(saved.difficulty, c.currentState.difficulty);
  });

  test('換一位（隨機難度）只換角色、不重抽難度', () {
    final c = makeController();
    c.setDifficultyPreference(PracticeDifficultyPreference.random);
    final lockedDifficulty = c.currentState.difficulty;
    final lockedLabel = c.currentState.difficultyLabel;

    // 連按多次「換一位」：難度必須穩定（即使偏好是隨機）。
    for (var i = 0; i < 30; i++) {
      c.regeneratePersona();
      expect(c.currentState.difficulty, lockedDifficulty);
      expect(c.currentState.difficultyLabel, lockedLabel);
    }
  });

  test('costDeducted=0（同場後續）不觸發額度同步', () async {
    api.sendHandler =
        (_, {profile}) async => reply(cost: 0, monthly: null, daily: null);
    final c = makeController();

    await c.sendMessage('嗨');
    expect(synced, isEmpty);
  });

  test('生成失敗：回滾使用者泡泡、設錯誤與還原文字、不持久化、不同步', () async {
    api.sendHandler =
        (_, {profile}) async => throw PracticeGenerationFailedException('boom');
    final c = makeController();

    await c.sendMessage('嗨');
    final s = c.currentState;

    expect(s.messages, isEmpty); // 回滾，不留半截
    expect(s.errorMessage, isNotNull);
    expect(s.restoreText, '嗨');
    expect(s.isSending, false);
    expect(repo.getById('sess-1'), isNull); // 未持久化
    expect(synced, isEmpty); // 未扣額度
  });

  test('額度用罄：quotaExceeded 旗標 + 回滾', () async {
    api.sendHandler = (_, {profile}) async => throw PracticeQuotaExceededException(
          '本月額度已用完',
          monthlyRemaining: 0,
          dailyRemaining: 0,
        );
    final c = makeController();

    await c.sendMessage('嗨');
    final s = c.currentState;

    expect(s.quotaExceeded, true);
    expect(s.errorMessage, '本月額度已用完');
    expect(s.messages, isEmpty);
  });

  test('Free 續玩需升級：upgradeRequired 旗標 + 回滾 + 還原文字、不持久化', () async {
    api.sendHandler =
        (_, {profile}) async => throw PracticeUpgradeRequiredException();
    final c = makeController();

    await c.sendMessage('嗨');
    final s = c.currentState;

    expect(s.upgradeRequired, true);
    expect(s.quotaExceeded, false); // 與額度用罄是不同訊號
    expect(s.errorMessage, isNotNull);
    expect(s.messages, isEmpty); // 回滾，不留半截
    expect(s.restoreText, '嗨');
    expect(s.isSending, false);
    expect(repo.getById('sess-1'), isNull); // 未持久化
    expect(synced, isEmpty); // 未扣額度
  });

  test('clearError 會一併清掉 upgradeRequired', () async {
    api.sendHandler =
        (_, {profile}) async => throw PracticeUpgradeRequiredException();
    final c = makeController();
    await c.sendMessage('嗨');
    expect(c.currentState.upgradeRequired, true);

    c.clearError();
    expect(c.currentState.upgradeRequired, false);
    expect(c.currentState.errorMessage, isNull);
  });

  test('滿 10 則：sessionComplete 後鎖定輸入、再送被忽略', () async {
    api.sendHandler = (_, {profile}) async =>
        reply(text: '最後一句', aiTurnCount: 10, complete: true, cost: 0);
    final c = makeController();

    await c.sendMessage('嗨');
    expect(c.currentState.sessionComplete, true);
    expect(c.currentState.canSend, false);

    await c.sendMessage('再一句'); // 應被忽略
    expect(c.currentState.messages.length, 2); // 仍只有 user+ai
  });

  test('結束練習：產拆解卡、鎖定、持久化拆解欄位', () async {
    api.sendHandler = (_, {profile}) async => reply();
    final c = makeController();
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
    expect(s.debrief!.summary, '整體不錯');
    expect(s.sessionComplete, true);
    final saved = repo.getById('sess-1');
    expect(saved!.debriefSummary, '整體不錯');
    expect(saved.debriefVibe, '暖');
  });

  test('沒有任何 AI 回覆時 endPractice 為 no-op', () async {
    api.debriefHandler = (_, {profile}) async => const PracticeDebrief(
          summary: 'x',
          strengths: [],
          watchouts: [],
          suggestedLine: 'y',
          vibe: '中性',
        );
    final c = makeController();

    await c.endPractice();
    expect(c.currentState.debrief, isNull);
    expect(c.currentState.isDebriefing, false);
  });

  test('拆解失敗：設錯誤、解鎖 ended 供重試', () async {
    api.sendHandler = (_, {profile}) async => reply();
    final c = makeController();
    await c.sendMessage('嗨');

    api.debriefHandler =
        (_, {profile}) async => throw PracticeGenerationFailedException('boom');
    await c.endPractice();
    final s = c.currentState;

    expect(s.debrief, isNull);
    expect(s.errorMessage, isNotNull);
    expect(s.ended, false); // 解鎖讓使用者可再按
  });

  test('從未拆解場次續聊：沿用 sessionId、舊訊息與 ai 計數', () async {
    final c = makeControllerFrom(PracticeSession(
      id: 'resume-1',
      createdAt: DateTime(2026, 6, 24, 9, 30),
      aiReplyCount: 1,
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗯？'),
      ],
    ));
    expect(c.currentState.sessionId, 'resume-1');
    expect(c.currentState.aiReplyCount, 1);
    expect(c.currentState.messages.map((m) => m.text).toList(), ['嗨', '嗯？']);

    late List<PracticeTurnDto> sentTurns;
    api.sendHandler = (turns, {profile}) async {
      sentTurns = turns;
      return reply(text: '好啊', aiTurnCount: 2, cost: 0);
    };

    await c.sendMessage('那你今天忙嗎');

    expect(sentTurns.map((t) => t.text).toList(), [
      '嗨',
      '嗯？',
      '那你今天忙嗎',
    ]);
    expect(c.currentState.sessionId, 'resume-1');
    expect(c.currentState.aiReplyCount, 2);
    expect(repo.getById('resume-1')!.messages.length, 4);
    expect(synced, isEmpty);
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
    await repo.save(PracticeSession(
      id: 'open-older',
      createdAt: DateTime(2026, 6, 24, 15, 50),
      aiReplyCount: 1,
      messages: const [PracticeMessage(role: 'user', text: '舊場')],
    ));

    final container = ProviderContainer(
      overrides: [
        practiceSessionRepositoryProvider.overrideWithValue(repo),
        practiceChatApiServiceProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final state = container.read(practiceChatControllerProvider);

    expect(state.sessionId, 'open-latest');
    expect(state.aiReplyCount, 1);
    expect(state.messages.map((m) => m.text).toList(), ['嗨', '嗯？']);
  });

  // ── 續玩 metadata（roundIndex / visiblePracticeThreadId）流穿 ──────────
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
        ));

    test('新場次：roundIndex 預設 1、visiblePracticeThreadId 等於 sessionId', () {
      final c = makeController();
      expect(c.currentState.roundIndex, 1);
      expect(c.currentState.visiblePracticeThreadId, 'sess-1');
    });

    test('舊場（無 roundIndex/threadId）續聊：roundIndex 兜底 1、threadId 兜底用 session.id', () {
      final c = makeControllerFrom(PracticeSession(
        id: 'old-sess',
        createdAt: DateTime(2026, 6, 24, 9),
        aiReplyCount: 1,
        messages: const [PracticeMessage(role: 'user', text: '嗨')],
      ));
      expect(c.currentState.roundIndex, 1);
      expect(c.currentState.visiblePracticeThreadId, 'old-sess');
    });

    test('既存 roundIndex/threadId 的場次續聊：照原值還原', () {
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

    test('_persist 寫入 roundIndex 與 visiblePracticeThreadId', () async {
      api.sendHandler = (_, {profile}) async => reply(cost: 0);
      final c = resumeR2();

      await c.sendMessage('在嗎');
      final saved = repo.getById('sess-r2')!;

      expect(saved.roundIndex, 2);
      expect(saved.visiblePracticeThreadId, 'thread-x');
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
}
