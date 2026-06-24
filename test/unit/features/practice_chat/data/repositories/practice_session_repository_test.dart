import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
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
    ));
    final loaded = repo.getById('d');
    expect(loaded!.hasDebrief, true);
    expect(loaded.debriefSummary, '整體不錯');
    expect(loaded.debriefVibe, '暖');
  });

  test('delete 移除指定練習紀錄，不影響其他場', () async {
    await repo.save(session('keep', 10));
    await repo.save(session('drop', 11));

    await repo.delete('drop');

    expect(repo.getById('drop'), isNull);
    expect(repo.getById('keep'), isNotNull);
    expect(repo.recentSessions().map((s) => s.id).toList(), ['keep']);
  });
}
