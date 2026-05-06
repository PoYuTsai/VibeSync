import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/coach_chat/data/repositories/coach_chat_repository_impl.dart';
import 'package:vibesync/features/coach_chat/domain/entities/coach_chat_result.dart';

const _testHivePath = './.dart_tool/test_hive_coach_chat_repo';
const _testBoxName = 'test_coach_chat_results';

CoachChatResult _result(
  String id, {
  String conversationId = 'c-1',
  DateTime? generatedAt,
}) {
  return CoachChatResult(
    id: id,
    conversationId: conversationId,
    partnerId: 'p-1',
    question: '她是什麼意思？',
    mode: 'replyCraft',
    headline: '接住再反問',
    answer: '她是在丟觀察，不是要你證明自己。',
    userState: '你可能急著解釋。',
    nextStep: '先用一句反問接回去。',
    suggestedLine: '被妳發現了。妳也是亂逛派嗎？',
    boundaryReminder: '不要把一句觀察放大成壓力。',
    needsReflection: false,
    reflectionQuestion: null,
    generatedAt: generatedAt ?? DateTime(2026, 5, 7, 12),
    provider: 'claude',
    modelUsed: 'claude-sonnet-4-20250514',
  );
}

void main() {
  setUpAll(() {
    Hive.init(_testHivePath);
    if (!Hive.isAdapterRegistered(17)) {
      Hive.registerAdapter(CoachChatResultAdapter());
    }
  });

  late Box<CoachChatResult> box;
  late CoachChatRepositoryImpl repo;

  setUp(() async {
    box = await Hive.openBox<CoachChatResult>(_testBoxName);
    repo = CoachChatRepositoryImpl(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('put + latestForConversation returns newest result', () async {
    await repo.put(_result('old', generatedAt: DateTime(2026, 5, 7, 11)));
    await repo.put(_result('new', generatedAt: DateTime(2026, 5, 7, 12)));

    expect(repo.latestForConversation('c-1')?.id, 'new');
  });

  test('put trims to latest 3 results per conversation', () async {
    for (var i = 0; i < 5; i++) {
      await repo.put(_result(
        'r-$i',
        generatedAt: DateTime(2026, 5, 7, 10 + i),
      ));
    }

    final list = repo.listByConversation('c-1');
    expect(list.map((r) => r.id), ['r-4', 'r-3', 'r-2']);
  });

  test('deleteConversation removes only that conversation', () async {
    await repo.put(_result('a', conversationId: 'c-1'));
    await repo.put(_result('b', conversationId: 'c-2'));

    await repo.deleteConversation('c-1');

    expect(repo.listByConversation('c-1'), isEmpty);
    expect(repo.listByConversation('c-2').single.id, 'b');
  });

  test('clearAll wipes every result', () async {
    await repo.put(_result('a', conversationId: 'c-1'));
    await repo.put(_result('b', conversationId: 'c-2'));

    await repo.clearAll();

    expect(box.values, isEmpty);
  });
}
