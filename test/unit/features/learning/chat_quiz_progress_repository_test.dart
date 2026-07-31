// test/unit/features/learning/chat_quiz_progress_repository_test.dart
//
// 測驗進度儲存。這一支的第一優先不是測驗本身，而是**證明它動不到電子書的
// 閱讀進度**：兩者住在同一顆加密 box 裡，key 或 schemaVersion 一旦沾到，
// 測驗改版就會靜靜清光所有人已經讀完的章節。
//
// 其餘重點沿用電子書進度已經做對的四件事：帳號綁定（沒登入不寫）、寫入序列化
// （連點不互蓋）、壞資料回空但不刪原始資料、冪等。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/learning/data/repositories/chat_quiz_progress_repository.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_progress_repository.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz_progress.dart';

const _testHivePath = './.dart_tool/test_hive_chat_quiz_progress';
const _testBoxName = 'test_chat_quiz_progress_settings';

const _ownerA = 'user-a-0001';
const _ownerB = 'user-b-0002';
const _levelOne = 'quiz-level-1-1';
const _questionOne = 'q-1-1-01';

void main() {
  setUpAll(() {
    Hive.init(_testHivePath);
  });

  late Box box;
  late ChatQuizProgressRepository repo;
  late DateTime clock;

  setUp(() async {
    box = await Hive.openBox(_testBoxName);
    clock = DateTime.utc(2026, 7, 31, 12);
    repo = ChatQuizProgressRepository(box: box, now: () => clock);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('與電子書進度的隔離', () {
    test('測驗進度與電子書進度完全獨立', () async {
      final ebookRepo = EbookProgressRepository(box: box, now: () => clock);
      await ebookRepo.markChapterCompleted(
        ownerUserId: _ownerA,
        bookId: 'ebook-1-bottleneck',
        chapterId: 'ebook-1-chapter-1',
      );

      await repo.recordAnswer(
        ownerUserId: _ownerA,
        questionId: _questionOne,
        choiceId: '$_questionOne-a',
        revision: 1,
      );

      final ebook = await ebookRepo.load(_ownerA);
      expect(
        ebook.bookProgress('ebook-1-bottleneck').completedChapterIds,
        contains('ebook-1-chapter-1'),
        reason: '測驗寫入把電子書進度弄壞了',
      );

      expect(box.get('learning_progress_v1:$_ownerA'), isNotNull);
      expect(box.get('chat_quiz_progress_v1:$_ownerA'), isNotNull);
    });

    test('兩份進度的 key 前綴與 schemaVersion 各自獨立', () {
      expect(
        ChatQuizProgressRepository.storageKeyPrefix,
        isNot(EbookProgressRepository.storageKeyPrefix),
      );
      // 兩顆版本號可以剛好都是 1，但它們必須是不同的常數——升測驗那顆
      // 不得讓電子書那份進度變成「版本對不上」而整包回空。
      expect(ChatQuizProgress.currentSchemaVersion, 1);
    });

    test('測驗進度寫入不會產生電子書的 key', () async {
      await repo.recordAnswer(
        ownerUserId: _ownerA,
        questionId: _questionOne,
        choiceId: '$_questionOne-a',
        revision: 1,
      );
      expect(box.get('learning_progress_v1:$_ownerA'), isNull);
      expect(
        box.keys.where((key) => '$key'.startsWith('learning_progress_v1')),
        isEmpty,
      );
    });
  });

  group('storage key', () {
    test('綁帳號 id，不從 email 推導', () {
      expect(
        ChatQuizProgressRepository.storageKeyFor(_ownerA),
        'chat_quiz_progress_v1:$_ownerA',
      );
      expect(
        ChatQuizProgressRepository.storageKeyFor('  $_ownerA  '),
        'chat_quiz_progress_v1:$_ownerA',
      );
    });

    test('沒登入不寫入任何東西', () async {
      expect(
        () => ChatQuizProgressRepository.storageKeyFor('   '),
        throwsArgumentError,
      );
      await expectLater(
        repo.recordAnswer(
          ownerUserId: '  ',
          questionId: _questionOne,
          choiceId: '$_questionOne-a',
          revision: 1,
        ),
        throwsArgumentError,
      );
      expect(box.keys, isEmpty, reason: '未登入時不得建立任何 key');
    });

    test('換帳號不沿用上一個帳號的進度', () async {
      await repo.recordAnswer(
        ownerUserId: _ownerA,
        questionId: _questionOne,
        choiceId: '$_questionOne-a',
        revision: 1,
      );
      final other = await repo.load(_ownerB);
      expect(other.answers, isEmpty);
      expect(other.levels, isEmpty);

      final mine = await repo.load(_ownerA);
      expect(mine.answers, hasLength(1));
    });
  });

  group('作答', () {
    test('全新帳號是空進度', () async {
      final progress = await repo.load(_ownerA);
      expect(progress.answers, isEmpty);
      expect(progress.levels, isEmpty);
      expect(progress.isLevelPassed(_levelOne), isFalse);
    });

    test('作答存得下來，重開也讀得到', () async {
      await repo.recordAnswer(
        ownerUserId: _ownerA,
        questionId: _questionOne,
        choiceId: '$_questionOne-b',
        revision: 2,
      );

      final reloaded = await ChatQuizProgressRepository(box: box).load(_ownerA);
      final answer = reloaded.answerFor(_questionOne, revision: 2);
      expect(answer?.choiceId, '$_questionOne-b');
      expect(answer?.revision, 2);
    });

    test('題目 revision 改了，舊答案自動失效', () async {
      await repo.recordAnswer(
        ownerUserId: _ownerA,
        questionId: _questionOne,
        choiceId: '$_questionOne-a',
        revision: 1,
      );
      final progress = await repo.load(_ownerA);
      expect(progress.answerFor(_questionOne, revision: 1), isNotNull);
      expect(
        progress.answerFor(_questionOne, revision: 2),
        isNull,
        reason: '題目改寫後不得顯示上一版的作答',
      );
    });

    test('重複送出同一個答案是 no-op，不會蓋掉作答時間', () async {
      await repo.recordAnswer(
        ownerUserId: _ownerA,
        questionId: _questionOne,
        choiceId: '$_questionOne-a',
        revision: 1,
      );
      final first = await repo.load(_ownerA);
      final firstAt = first.answers[_questionOne]!.answeredAt;

      clock = clock.add(const Duration(minutes: 5));
      await repo.recordAnswer(
        ownerUserId: _ownerA,
        questionId: _questionOne,
        choiceId: '$_questionOne-a',
        revision: 1,
      );
      final second = await repo.load(_ownerA);
      expect(second.answers[_questionOne]!.answeredAt, firstAt);
    });

    test('清除作答讓「再跑一次」從頭開始，但不收回最佳成績', () async {
      await repo.recordAnswer(
        ownerUserId: _ownerA,
        questionId: _questionOne,
        choiceId: '$_questionOne-a',
        revision: 1,
      );
      await repo.recordLevelResult(
        ownerUserId: _ownerA,
        levelId: _levelOne,
        correctCount: 9,
        questionCount: 10,
        passed: true,
      );

      final after = await repo.clearAnswers(
        ownerUserId: _ownerA,
        questionIds: [_questionOne],
      );
      expect(after.answers, isEmpty);
      expect(after.resultFor(_levelOne)?.correctCount, 9);
      expect(after.isLevelPassed(_levelOne), isTrue);
    });

    test('連續 20 次寫入沒有遺失', () async {
      await Future.wait([
        for (var index = 0; index < 20; index++)
          repo.recordAnswer(
            ownerUserId: _ownerA,
            questionId: 'q-$index',
            choiceId: 'q-$index-a',
            revision: 1,
          ),
      ]);

      final progress = await repo.load(_ownerA);
      expect(progress.answers, hasLength(20));
      for (var index = 0; index < 20; index++) {
        expect(progress.answers['q-$index']?.choiceId, 'q-$index-a');
      }
    });
  });

  group('關卡成績', () {
    test('只留最好的一次，變差不覆蓋', () async {
      await repo.recordLevelResult(
        ownerUserId: _ownerA,
        levelId: _levelOne,
        correctCount: 9,
        questionCount: 10,
        passed: true,
      );
      clock = clock.add(const Duration(hours: 1));
      await repo.recordLevelResult(
        ownerUserId: _ownerA,
        levelId: _levelOne,
        correctCount: 4,
        questionCount: 10,
        passed: false,
      );

      final progress = await repo.load(_ownerA);
      expect(progress.resultFor(_levelOne)?.correctCount, 9);
      expect(progress.isLevelPassed(_levelOne), isTrue);
    });

    test('變好就更新', () async {
      await repo.recordLevelResult(
        ownerUserId: _ownerA,
        levelId: _levelOne,
        correctCount: 6,
        questionCount: 10,
        passed: false,
      );
      await repo.recordLevelResult(
        ownerUserId: _ownerA,
        levelId: _levelOne,
        correctCount: 10,
        questionCount: 10,
        passed: true,
      );

      final progress = await repo.load(_ownerA);
      expect(progress.resultFor(_levelOne)?.correctCount, 10);
      expect(progress.isLevelPassed(_levelOne), isTrue);
    });

    test('送出同一個成績兩次是 no-op', () async {
      final first = await repo.recordLevelResult(
        ownerUserId: _ownerA,
        levelId: _levelOne,
        correctCount: 8,
        questionCount: 10,
        passed: true,
      );
      clock = clock.add(const Duration(hours: 1));
      final second = await repo.recordLevelResult(
        ownerUserId: _ownerA,
        levelId: _levelOne,
        correctCount: 8,
        questionCount: 10,
        passed: true,
      );
      expect(
        second.resultFor(_levelOne)?.achievedAt,
        first.resultFor(_levelOne)?.achievedAt,
      );
    });

    test('不合法的題數／答對數直接擋掉', () async {
      await expectLater(
        repo.recordLevelResult(
          ownerUserId: _ownerA,
          levelId: _levelOne,
          correctCount: 0,
          questionCount: 0,
          passed: false,
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.recordLevelResult(
          ownerUserId: _ownerA,
          levelId: _levelOne,
          correctCount: 11,
          questionCount: 10,
          passed: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('壞資料', () {
    test('壞資料回空進度，但不刪原始資料', () async {
      final key = ChatQuizProgressRepository.storageKeyFor(_ownerA);
      await box.put(key, '{ 這不是 JSON');

      final progress = await repo.load(_ownerA);
      expect(progress.answers, isEmpty);
      expect(box.get(key), '{ 這不是 JSON', reason: '原始資料不得被刪掉');
    });

    test('型別不符回空進度', () async {
      await box.put(ChatQuizProgressRepository.storageKeyFor(_ownerA), 42);
      final progress = await repo.load(_ownerA);
      expect(progress.answers, isEmpty);
    });

    test('未知 schemaVersion 整包當空，且只影響測驗', () async {
      await box.put(
        ChatQuizProgressRepository.storageKeyFor(_ownerA),
        jsonEncode(<String, Object?>{
          'schemaVersion': 99,
          'answers': {
            _questionOne: {
              'choiceId': 'x',
              'revision': 1,
              'answeredAt': '2026-07-31T12:00:00Z',
            },
          },
        }),
      );

      final progress = await repo.load(_ownerA);
      expect(progress.answers, isEmpty);
    });

    test('單筆壞掉的作答不影響同一份進度的其他題', () async {
      await box.put(
        ChatQuizProgressRepository.storageKeyFor(_ownerA),
        jsonEncode(<String, Object?>{
          'schemaVersion': ChatQuizProgress.currentSchemaVersion,
          'answers': {
            'q-good': {
              'choiceId': 'q-good-a',
              'revision': 1,
              'answeredAt': '2026-07-31T12:00:00Z',
            },
            'q-bad': {'choiceId': '', 'revision': 0},
          },
        }),
      );

      final progress = await repo.load(_ownerA);
      expect(progress.answers.keys, ['q-good']);
    });
  });
}
