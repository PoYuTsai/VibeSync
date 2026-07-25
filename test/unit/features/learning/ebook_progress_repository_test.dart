// test/unit/features/learning/ebook_progress_repository_test.dart
//
// 電子書進度儲存。重點：帳號隔離、resume 存 chapter id、quiz revision 失效、
// 損壞資料不 crash、快速連續寫入最後一筆勝出。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_progress_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook_progress.dart';

const _testHivePath = './.dart_tool/test_hive_ebook_progress';
const _testBoxName = 'test_ebook_progress_settings';

const _ownerA = 'user-a-0001';
const _ownerB = 'user-b-0002';
const _bookOne = 'ebook-1-bottleneck';
const _bookTwo = 'ebook-2-conversation';

void main() {
  setUpAll(() {
    Hive.init(_testHivePath);
  });

  late Box box;
  late EbookProgressRepository repo;

  setUp(() async {
    box = await Hive.openBox(_testBoxName);
    repo = EbookProgressRepository(
      box: box,
      now: () => DateTime.utc(2026, 7, 25, 12),
    );
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('storage key', () {
    test('is account scoped and never derived from email', () {
      expect(
        EbookProgressRepository.storageKeyFor(_ownerA),
        'learning_progress_v1:$_ownerA',
      );
      expect(
        EbookProgressRepository.storageKeyFor('  $_ownerA  '),
        'learning_progress_v1:$_ownerA',
      );
    });

    test('rejects an empty owner id', () {
      expect(
        () => EbookProgressRepository.storageKeyFor('   '),
        throwsArgumentError,
      );
    });
  });

  test('empty snapshot for a fresh account', () async {
    final snapshot = await repo.load(_ownerA);
    expect(snapshot.books, isEmpty);
    expect(snapshot.bookProgress(_bookOne).completedChapterIds, isEmpty);
    expect(snapshot.bookProgress(_bookOne).lastChapterId, isNull);
  });

  test('chapter completion is idempotent and drives completion ratio', () async {
    await repo.markChapterCompleted(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      chapterId: 'ebook-1-chapter-1',
      contentVersion: 1,
    );
    await repo.markChapterCompleted(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      chapterId: 'ebook-1-chapter-1',
      contentVersion: 1,
    );
    final snapshot = await repo.markChapterCompleted(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      chapterId: 'ebook-1-chapter-2',
      contentVersion: 1,
    );

    final progress = snapshot.bookProgress(_bookOne);
    expect(progress.completedChapterIds,
        {'ebook-1-chapter-1', 'ebook-1-chapter-2'});
    expect(progress.contentVersionSeen, 1);
    expect(progress.completionRatio(5), closeTo(0.4, 0.0001));
    expect(progress.completionRatio(0), 0);
    expect(progress.isChapterCompleted('ebook-1-chapter-1'), isTrue);
    expect(progress.isChapterCompleted('ebook-1-chapter-9'), isFalse);
  });

  test('completing a chapter also updates lastChapterId', () async {
    final snapshot = await repo.markChapterCompleted(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      chapterId: 'ebook-1-chapter-3',
    );
    expect(snapshot.bookProgress(_bookOne).lastChapterId, 'ebook-1-chapter-3');
  });

  test('lastChapterId round-trips and survives chapter reordering', () async {
    await repo.setLastChapter(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      chapterId: 'ebook-1-chapter-4',
    );

    final reloaded = await EbookProgressRepository(box: box).load(_ownerA);
    // 儲存的是 chapter id，不是 index：章節順序改變也還是指向同一章。
    expect(reloaded.bookProgress(_bookOne).lastChapterId, 'ebook-1-chapter-4');
    final rawJson =
        jsonDecode(box.get(EbookProgressRepository.storageKeyFor(_ownerA))
            as String) as Map<String, Object?>;
    expect(rawJson['schemaVersion'], EbookProgressSnapshot.currentSchemaVersion);
    expect(rawJson.toString(), isNot(contains('chapterIndex')));
  });

  test('books do not leak into each other', () async {
    await repo.markChapterCompleted(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      chapterId: 'ebook-1-chapter-1',
    );
    final snapshot = await repo.markChapterCompleted(
      ownerUserId: _ownerA,
      bookId: _bookTwo,
      chapterId: 'ebook-2-chapter-1',
    );

    expect(snapshot.bookProgress(_bookOne).completedChapterIds,
        {'ebook-1-chapter-1'});
    expect(snapshot.bookProgress(_bookTwo).completedChapterIds,
        {'ebook-2-chapter-1'});
  });

  test('accounts do not leak into each other', () async {
    await repo.markChapterCompleted(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      chapterId: 'ebook-1-chapter-1',
    );
    await repo.recordQuizSubmission(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      quizId: 'ebook-1-c1-quiz-1',
      quizRevision: 1,
      choiceIds: const ['ebook-1-c1-quiz-1-b'],
      solved: true,
    );

    final forB = await repo.load(_ownerB);
    expect(forB.books, isEmpty);

    await repo.markChapterCompleted(
      ownerUserId: _ownerB,
      bookId: _bookOne,
      chapterId: 'ebook-1-chapter-5',
    );

    final forA = await repo.load(_ownerA);
    expect(forA.bookProgress(_bookOne).completedChapterIds,
        {'ebook-1-chapter-1'});
    expect(
      forA.bookProgress(_bookOne).quizStateFor('ebook-1-c1-quiz-1', 1)?.solved,
      isTrue,
    );

    final reloadedB = await repo.load(_ownerB);
    expect(reloadedB.bookProgress(_bookOne).completedChapterIds,
        {'ebook-1-chapter-5'});
    expect(
      reloadedB.bookProgress(_bookOne).quizStateFor('ebook-1-c1-quiz-1', 1),
      isNull,
    );

    expect(box.keys, containsAll(<String>[
      EbookProgressRepository.storageKeyFor(_ownerA),
      EbookProgressRepository.storageKeyFor(_ownerB),
    ]));
  });

  group('quiz state', () {
    test('stores stable string choice ids, not indexes', () async {
      final snapshot = await repo.recordQuizSubmission(
        ownerUserId: _ownerA,
        bookId: _bookTwo,
        quizId: 'quiz-multi',
        quizRevision: 2,
        choiceIds: const ['choice-v', 'choice-e', 'choice-v'],
        solved: true,
      );

      final state =
          snapshot.bookProgress(_bookTwo).quizStateFor('quiz-multi', 2)!;
      expect(state.selectedChoiceIds..sort(), ['choice-e', 'choice-v']);
      expect(state.solved, isTrue);
    });

    test('a wrong answer is stored as unsolved and can be retried', () async {
      await repo.recordQuizSubmission(
        ownerUserId: _ownerA,
        bookId: _bookTwo,
        quizId: 'quiz-1',
        quizRevision: 1,
        choiceIds: const ['wrong'],
        solved: false,
      );
      var state = (await repo.load(_ownerA))
          .bookProgress(_bookTwo)
          .quizStateFor('quiz-1', 1)!;
      expect(state.solved, isFalse);
      expect(state.selectedChoiceIds, ['wrong']);

      await repo.recordQuizSubmission(
        ownerUserId: _ownerA,
        bookId: _bookTwo,
        quizId: 'quiz-1',
        quizRevision: 1,
        choiceIds: const ['right'],
        solved: true,
      );
      state = (await repo.load(_ownerA))
          .bookProgress(_bookTwo)
          .quizStateFor('quiz-1', 1)!;
      expect(state.solved, isTrue);
      expect(state.selectedChoiceIds, ['right']);
    });

    test('a revision bump invalidates the stored answer', () async {
      await repo.recordQuizSubmission(
        ownerUserId: _ownerA,
        bookId: _bookTwo,
        quizId: 'quiz-1',
        quizRevision: 1,
        choiceIds: const ['a'],
        solved: true,
      );
      final progress = (await repo.load(_ownerA)).bookProgress(_bookTwo);

      expect(progress.quizStateFor('quiz-1', 1), isNotNull);
      expect(progress.quizStateFor('quiz-1', 2), isNull,
          reason: 'revision 改變時舊答案必須視為未作答');
      // 原資料仍在，只是不再被採用（沒有靜默刪除）。
      expect(progress.quizStates['quiz-1']!.quizRevision, 1);
    });
  });

  group('checklist state', () {
    test('checking and unchecking round-trips', () async {
      await repo.setChecklistItem(
        ownerUserId: _ownerA,
        bookId: 'ebook-4-meeting',
        blockId: 'weekly-check',
        itemId: 'item-1',
        checked: true,
      );
      await repo.setChecklistItem(
        ownerUserId: _ownerA,
        bookId: 'ebook-4-meeting',
        blockId: 'weekly-check',
        itemId: 'item-2',
        checked: true,
      );
      var progress = (await repo.load(_ownerA)).bookProgress('ebook-4-meeting');
      expect(progress.checkedItemsFor('weekly-check'), {'item-1', 'item-2'});

      await repo.setChecklistItem(
        ownerUserId: _ownerA,
        bookId: 'ebook-4-meeting',
        blockId: 'weekly-check',
        itemId: 'item-1',
        checked: false,
      );
      progress = (await repo.load(_ownerA)).bookProgress('ebook-4-meeting');
      expect(progress.checkedItemsFor('weekly-check'), {'item-2'});

      await repo.setChecklistItem(
        ownerUserId: _ownerA,
        bookId: 'ebook-4-meeting',
        blockId: 'weekly-check',
        itemId: 'item-2',
        checked: false,
      );
      progress = (await repo.load(_ownerA)).bookProgress('ebook-4-meeting');
      expect(progress.checkedItemsFor('weekly-check'), isEmpty);
      expect(progress.checklistStates.containsKey('weekly-check'), isFalse);
    });
  });

  group('corruption 與 migration', () {
    test('malformed JSON falls back to an empty snapshot', () async {
      await box.put(
        EbookProgressRepository.storageKeyFor(_ownerA),
        '{ this is not json',
      );
      final snapshot = await repo.load(_ownerA);
      expect(snapshot.books, isEmpty);
      // 不靜默刪除原 key。
      expect(
        box.containsKey(EbookProgressRepository.storageKeyFor(_ownerA)),
        isTrue,
      );
    });

    test('a non-string payload falls back to an empty snapshot', () async {
      await box.put(
        EbookProgressRepository.storageKeyFor(_ownerA),
        <String, Object?>{'schemaVersion': 1},
      );
      expect((await repo.load(_ownerA)).books, isEmpty);
    });

    test('unknown schema version falls back to an empty snapshot', () async {
      await box.put(
        EbookProgressRepository.storageKeyFor(_ownerA),
        jsonEncode(<String, Object?>{
          'schemaVersion': 99,
          'books': <String, Object?>{
            _bookOne: <String, Object?>{
              'completedChapterIds': ['ebook-1-chapter-1'],
            },
          },
        }),
      );
      expect((await repo.load(_ownerA)).books, isEmpty);
    });

    test('type-polluted fields are dropped, valid ones survive', () async {
      await box.put(
        EbookProgressRepository.storageKeyFor(_ownerA),
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'books': <String, Object?>{
            _bookOne: <String, Object?>{
              'contentVersionSeen': 'one',
              'lastChapterId': 42,
              'completedChapterIds': [
                'ebook-1-chapter-1',
                7,
                null,
                '  ',
              ],
              'quizStates': <String, Object?>{
                'good': <String, Object?>{
                  'quizRevision': 1,
                  'selectedChoiceIds': ['a', 3],
                  'solved': true,
                },
                'bad-revision': <String, Object?>{
                  'quizRevision': 'x',
                  'selectedChoiceIds': ['a'],
                  'solved': true,
                },
                'bad-solved': <String, Object?>{
                  'quizRevision': 1,
                  'selectedChoiceIds': ['a'],
                  'solved': 'yes',
                },
              },
              'checklistStates': <String, Object?>{
                'block-1': ['i1', 2],
                'block-2': 'not-a-list',
              },
            },
          },
        }),
      );

      final progress = (await repo.load(_ownerA)).bookProgress(_bookOne);
      expect(progress.contentVersionSeen, isNull);
      expect(progress.lastChapterId, isNull);
      expect(progress.completedChapterIds, {'ebook-1-chapter-1'});
      expect(progress.quizStates.keys, ['good']);
      expect(progress.quizStates['good']!.selectedChoiceIds, ['a']);
      expect(progress.checkedItemsFor('block-1'), {'i1'});
      expect(progress.checkedItemsFor('block-2'), isEmpty);
    });

    test('a recovered snapshot can still be written to', () async {
      await box.put(
        EbookProgressRepository.storageKeyFor(_ownerA),
        'garbage',
      );
      final snapshot = await repo.markChapterCompleted(
        ownerUserId: _ownerA,
        bookId: _bookOne,
        chapterId: 'ebook-1-chapter-1',
      );
      expect(snapshot.bookProgress(_bookOne).completedChapterIds,
          {'ebook-1-chapter-1'});
    });
  });

  test('writes are awaited and land in the box', () async {
    await repo.markChapterCompleted(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      chapterId: 'ebook-1-chapter-1',
    );
    // 不再 await 任何東西，資料就已經在 box 裡。
    expect(
      box.get(EbookProgressRepository.storageKeyFor(_ownerA)),
      isA<String>().having(
        (raw) => raw.contains('ebook-1-chapter-1'),
        'contains chapter id',
        isTrue,
      ),
    );
  });

  test('rapid lastChapter writes: the last one wins and none are lost',
      () async {
    final futures = <Future<EbookProgressSnapshot>>[];
    for (var index = 1; index <= 5; index++) {
      futures.add(
        repo.setLastChapter(
          ownerUserId: _ownerA,
          bookId: _bookOne,
          chapterId: 'ebook-1-chapter-$index',
        ),
      );
    }
    await Future.wait(futures);

    final snapshot = await repo.load(_ownerA);
    expect(snapshot.bookProgress(_bookOne).lastChapterId, 'ebook-1-chapter-5');
  });

  test('interleaved completion writes are all preserved', () async {
    await Future.wait(<Future<void>>[
      repo.markChapterCompleted(
        ownerUserId: _ownerA,
        bookId: _bookOne,
        chapterId: 'ebook-1-chapter-1',
      ),
      repo.markChapterCompleted(
        ownerUserId: _ownerA,
        bookId: _bookOne,
        chapterId: 'ebook-1-chapter-2',
      ),
      repo.recordQuizSubmission(
        ownerUserId: _ownerA,
        bookId: _bookOne,
        quizId: 'q1',
        quizRevision: 1,
        choiceIds: const ['a'],
        solved: true,
      ),
    ]);

    final progress = (await repo.load(_ownerA)).bookProgress(_bookOne);
    expect(progress.completedChapterIds,
        {'ebook-1-chapter-1', 'ebook-1-chapter-2'});
    expect(progress.quizStateFor('q1', 1), isNotNull);
  });

  test('a failed write does not break later writes', () async {
    await expectLater(repo.load('  '), throwsArgumentError);
    final snapshot = await repo.markChapterCompleted(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      chapterId: 'ebook-1-chapter-1',
    );
    expect(snapshot.bookProgress(_bookOne).completedChapterIds, hasLength(1));
  });

  test('snapshot never stores free-text reflections or chat content', () async {
    await repo.markChapterCompleted(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      chapterId: 'ebook-1-chapter-1',
    );
    await repo.recordQuizSubmission(
      ownerUserId: _ownerA,
      bookId: _bookOne,
      quizId: 'q1',
      quizRevision: 1,
      choiceIds: const ['choice-a'],
      solved: true,
    );
    final raw = box.get(EbookProgressRepository.storageKeyFor(_ownerA))
        as String;
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    expect(decoded.keys, containsAll(<String>['schemaVersion', 'books']));
    // 只有 id / bool / 版本號等結構性欄位。
    for (final key in const ['note', 'text', 'message', 'reflection']) {
      expect(raw.contains('"$key"'), isFalse, reason: '不應出現自由文字欄位 $key');
    }
  });
}
