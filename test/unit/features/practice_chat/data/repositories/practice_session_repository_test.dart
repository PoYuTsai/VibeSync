import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_hint.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';

void main() {
  late Box<PracticeSession> box;
  late PracticeSessionRepository repo;

  setUp(() async {
    Hive.init('./.dart_tool/test_hive_practice_repo');
    if (!Hive.isAdapterRegistered(22)) {
      Hive.registerAdapter(PracticeMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(23)) {
      Hive.registerAdapter(PracticeSessionAdapter());
    }
    final ts = DateTime.now().microsecondsSinceEpoch;
    box = await Hive.openBox<PracticeSession>('practice_repo_$ts');
    repo = PracticeSessionRepository(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  PracticeSession session(String id, int minute) => PracticeSession(
        id: id,
        createdAt: DateTime(2026, 6, 24, 10, minute),
        messages: [PracticeMessage(role: 'user', text: '嗨 $id')],
      );

  // 同一位續玩會產生多個 billing session（各自 id），但共用同一個
  // visiblePracticeThreadId。clock 用 minute 表新舊。
  PracticeSession round(String id, String threadId, int minute) =>
      PracticeSession(
        id: id,
        createdAt: DateTime(2026, 6, 24, 10, minute),
        messages: [PracticeMessage(role: 'user', text: '嗨 $id')],
        visiblePracticeThreadId: threadId,
      );

  test('只保留最近 5 場，舊的被修剪', () async {
    for (var i = 1; i <= 6; i++) {
      await repo.save(session('s$i', i)); // minute 越大越新
    }
    final recent = repo.recentSessions();
    expect(recent.length, 5);
    // s1 是最舊（minute=1），應被刪。
    expect(recent.any((s) => s.id == 's1'), false);
    expect(box.get('s1'), isNull);
    expect(box.length, 5);
  });

  test('recentSessions 依建立時間新到舊排序', () async {
    await repo.save(session('a', 5));
    await repo.save(session('b', 30));
    await repo.save(session('c', 15));
    final recent = repo.recentSessions();
    expect(recent.map((s) => s.id).toList(), ['b', 'c', 'a']);
  });

  test('同 id 再 save 是更新而非新增', () async {
    await repo.save(session('x', 10));
    await repo.save(session('x', 10));
    expect(box.length, 1);
    expect(repo.getById('x'), isNotNull);
  });

  test('save 後可帶拆解卡欄位持久化', () async {
    await repo.save(PracticeSession(
      id: 'd',
      createdAt: DateTime(2026, 6, 24, 12, 0),
      messages: const [],
      aiReplyCount: 3,
      debriefSummary: '整體不錯',
      debriefStrengths: const ['開場自然'],
      debriefVibe: '暖',
      debriefDateChance: 'high',
      debriefDateChanceReason: '她已經接住邀約鋪墊。',
      debriefNextInviteMove: '直接約週末咖啡。',
      debriefQualitySchemaVersion: kPracticeDebriefQualitySchemaVersion,
    ));
    final loaded = repo.getById('d');
    expect(loaded!.hasDebrief, true);
    expect(loaded.hasRestorableDebrief, true);
    expect(loaded.debriefSummary, '整體不錯');
    expect(loaded.debriefVibe, '暖');
    expect(loaded.debriefDateChance, 'high');
    expect(loaded.debriefDateChanceReason, '她已經接住邀約鋪墊。');
    expect(loaded.debriefNextInviteMove, '直接約週末咖啡。');
    expect(loaded.debriefQualitySchemaVersion,
        kPracticeDebriefQualitySchemaVersion);
  });

  test('舊拆解沒有品質版本時仍算完成，但不可 restore', () async {
    await repo.save(PracticeSession(
      id: 'legacy-debrief',
      createdAt: DateTime(2026, 6, 24, 12, 1),
      debriefSummary: '舊版拆解',
      debriefSuggestedLine: '舊版下一句',
    ));

    final loaded = repo.getById('legacy-debrief')!;
    expect(loaded.hasDebrief, true);
    expect(loaded.hasRestorableDebrief, false);
    expect(loaded.debriefQualitySchemaVersion, isNull);
  });

  test('save 後可持久化 persona 與 difficulty', () async {
    await repo.save(PracticeSession(
      id: 'p',
      createdAt: DateTime(2026, 6, 24, 18),
      personaId: 'teasing_humor',
      personaLabel: '幽默吐槽型',
      difficulty: 'challenge',
      difficultyLabel: '挑戰',
    ));

    final loaded = repo.getById('p')!;
    expect(loaded.personaId, 'teasing_humor');
    expect(loaded.personaLabel, '幽默吐槽型');
    expect(loaded.difficulty, 'challenge');
    expect(loaded.difficultyLabel, '挑戰');
  });

  test('save 後可持久化 profileId（續玩同一位的身份識別）', () async {
    await repo.save(PracticeSession(
      id: 'g',
      createdAt: DateTime(2026, 6, 25, 9),
      profileId: 'practice_girl_007',
    ));
    expect(repo.getById('g')!.profileId, 'practice_girl_007');
  });

  test('舊場（無 profileId）讀回為 null，不 crash', () async {
    await repo.save(PracticeSession(
      id: 'legacy',
      createdAt: DateTime(2026, 6, 25, 9),
    ));
    expect(repo.getById('legacy')!.profileId, isNull);
  });

  test('save persists beginner learning metadata', () async {
    await repo.save(PracticeSession(
      id: 'beginner',
      createdAt: DateTime(2026, 6, 28, 10),
      practiceMode: 'beginner',
      temperatureScore: 42,
      familiarityScore: 44,
      relationshipStageLabel: '可以聊個人',
      hintUsedCount: 3,
    ));

    final loaded = repo.getById('beginner')!;
    expect(loaded.practiceMode, 'beginner');
    expect(loaded.temperatureScore, 42);
    expect(loaded.familiarityScore, 44);
    expect(loaded.relationshipStageLabel, '可以聊個人');
    expect(loaded.hintUsedCount, 3);
  });

  test('copyWith updates beginner learning metadata', () {
    final original = PracticeSession(
      id: 'copy',
      createdAt: DateTime(2026, 6, 28, 11),
      practiceMode: 'standard',
      temperatureScore: 30,
      familiarityScore: 0,
      relationshipStageLabel: '建立熟悉中',
      hintUsedCount: 0,
    );

    final updated = original.copyWith(
      practiceMode: 'beginner',
      temperatureScore: 55,
      familiarityScore: 45,
      relationshipStageLabel: '可以聊個人',
      hintUsedCount: 2,
    );

    expect(updated.practiceMode, 'beginner');
    expect(updated.temperatureScore, 55);
    expect(updated.familiarityScore, 45);
    expect(updated.relationshipStageLabel, '可以聊個人');
    expect(updated.hintUsedCount, 2);
  });

  test('delete 移除指定練習紀錄，不影響其他場', () async {
    await repo.save(session('keep', 10));
    await repo.save(session('drop', 11));

    await repo.delete('drop');

    expect(repo.getById('drop'), isNull);
    expect(repo.getById('keep'), isNotNull);
    expect(repo.recentSessions().map((s) => s.id).toList(), ['keep']);
  });

  // ── visible thread 語意（同一位續玩多輪 = 一段對話）──────────────────────
  test('recentSessions 同一位多輪只顯示最新一筆（依 visible thread 去重）', () async {
    await repo.save(round('t1-r1', 't1', 10));
    await repo.save(round('t1-r2', 't1', 20));
    await repo.save(round('t1-r3', 't1', 30)); // t1 最新一輪
    await repo.save(session('other', 5)); // 另一段對話

    final recent = repo.recentSessions();
    // 顯示成兩段對話，不是四筆 session。
    expect(recent.length, 2);
    // 每段對話取最新一輪；t1 取 r3。
    expect(recent.map((s) => s.id).toList(), ['t1-r3', 'other']);
  });

  test('recentSessions 以 visible thread 計最近 5 段，同一位續玩不吃掉名額', () async {
    // A 續到 3 輪、且是最新的對話（rounds 落在時間前段），加上 5 段各 1 輪 = 6 段。
    // 未去重的 take(5) 會被 A 的 3 輪吃掉名額、漏掉其他段；去重後 A 只佔 1 名額。
    await repo.save(round('A-r1', 'A', 8));
    await repo.save(round('A-r2', 'A', 9));
    await repo.save(round('A-r3', 'A', 10)); // A 最新
    await repo.save(session('B', 7));
    await repo.save(session('C', 6));
    await repo.save(session('D', 5));
    await repo.save(session('E', 4));
    await repo.save(session('F', 3)); // 最舊一段

    final recent = repo.recentSessions();
    // 6 段對話 → 只留最近 5 段；A 只佔 1 個名額。
    expect(recent.length, 5);
    final keys = recent.map((s) => s.visiblePracticeThreadId ?? s.id).toList();
    expect(keys.where((k) => k == 'A').length, 1); // A 去重後只一筆
    expect(keys.toSet().length, 5); // 5 段不重複
    expect(keys.contains('A'), true); // A 最新，必留
    expect(keys.contains('F'), false); // 最舊一段被擠掉
  });

  test('deleteVisibleThread 刪掉同一位的所有輪次，不影響其他段', () async {
    await repo.save(round('t1-r1', 't1', 10));
    await repo.save(round('t1-r2', 't1', 20));
    await repo.save(round('t1-r3', 't1', 30));
    await repo.save(session('keep', 5));

    await repo.deleteVisibleThread('t1');

    expect(repo.getById('t1-r1'), isNull);
    expect(repo.getById('t1-r2'), isNull);
    expect(repo.getById('t1-r3'), isNull);
    expect(repo.getById('keep'), isNotNull);
  });

  test('trim 以 visible thread 計：同一位續 3 輪不會被當成 3 段而擠掉早輪', () async {
    // 1 段對話 A（3 輪）+ 4 段各 1 輪 = 5 段對話、共 7 個 session。
    await repo.save(round('A-r1', 'A', 1));
    await repo.save(round('A-r2', 'A', 2));
    await repo.save(round('A-r3', 'A', 3));
    await repo.save(session('B', 4));
    await repo.save(session('C', 5));
    await repo.save(session('D', 6));
    await repo.save(session('E', 7));

    // 舊行為（保留 5 個 session）會刪掉 A-r1/A-r2；新行為保留 5 段對話 → 7 個全留。
    expect(box.length, 7);
    expect(box.get('A-r1'), isNotNull);
    expect(box.get('A-r2'), isNotNull);
    expect(box.get('A-r3'), isNotNull);
  });
}
