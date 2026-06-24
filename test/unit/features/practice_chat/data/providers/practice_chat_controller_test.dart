import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';

class _FakeApi extends PracticeChatApiService {
  Future<PracticeChatReply> Function(List<PracticeTurnDto> turns)? sendHandler;
  Future<PracticeDebrief> Function(List<PracticeTurnDto> turns)? debriefHandler;

  @override
  Future<PracticeChatReply> sendMessage({
    required String sessionId,
    required List<PracticeTurnDto> turns,
  }) =>
      sendHandler!(turns);

  @override
  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required List<PracticeTurnDto> turns,
  }) =>
      debriefHandler!(turns);
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
    api.sendHandler = (_) async => reply();
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

  test('costDeducted=0（同場後續）不觸發額度同步', () async {
    api.sendHandler = (_) async => reply(cost: 0, monthly: null, daily: null);
    final c = makeController();

    await c.sendMessage('嗨');
    expect(synced, isEmpty);
  });

  test('生成失敗：回滾使用者泡泡、設錯誤與還原文字、不持久化、不同步', () async {
    api.sendHandler = (_) async =>
        throw PracticeGenerationFailedException('boom');
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
    api.sendHandler = (_) async => throw PracticeQuotaExceededException(
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

  test('滿 10 則：sessionComplete 後鎖定輸入、再送被忽略', () async {
    api.sendHandler = (_) async =>
        reply(text: '最後一句', aiTurnCount: 10, complete: true, cost: 0);
    final c = makeController();

    await c.sendMessage('嗨');
    expect(c.currentState.sessionComplete, true);
    expect(c.currentState.canSend, false);

    await c.sendMessage('再一句'); // 應被忽略
    expect(c.currentState.messages.length, 2); // 仍只有 user+ai
  });

  test('結束練習：產拆解卡、鎖定、持久化拆解欄位', () async {
    api.sendHandler = (_) async => reply();
    final c = makeController();
    await c.sendMessage('嗨');

    api.debriefHandler = (_) async => const PracticeDebrief(
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
    api.debriefHandler = (_) async => const PracticeDebrief(
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
    api.sendHandler = (_) async => reply();
    final c = makeController();
    await c.sendMessage('嗨');

    api.debriefHandler = (_) async =>
        throw PracticeGenerationFailedException('boom');
    await c.endPractice();
    final s = c.currentState;

    expect(s.debrief, isNull);
    expect(s.errorMessage, isNotNull);
    expect(s.ended, false); // 解鎖讓使用者可再按
  });
}
