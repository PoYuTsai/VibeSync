// test/unit/features/learning/ebook_progress_controller_test.dart
//
// Controller 層：owner id 只能來自 auth scope、未登入 fail closed、
// 換帳號重建不沿用上一個帳號的 snapshot、寫入 await 完成才更新 state。
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_progress_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook_progress.dart';

const _testHivePath = './.dart_tool/test_hive_ebook_progress_controller';
const _testBoxName = 'test_ebook_progress_controller_settings';

const _ownerA = 'user-a-0001';
const _ownerB = 'user-b-0002';
const _bookOne = 'ebook-1-bottleneck';

void main() {
  setUpAll(() {
    Hive.init(_testHivePath);
  });

  late Box box;
  late EbookProgressRepository repo;

  setUp(() async {
    box = await Hive.openBox(_testBoxName);
    repo = EbookProgressRepository(box: box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    final dir = Directory(_testHivePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ProviderContainer containerFor(Stream<String?> owners) {
    final container = ProviderContainer(
      overrides: [
        ebookProgressOwnerProvider.overrideWith((ref) => owners),
        ebookProgressRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('未登入時 fail closed：空進度且不寫入任何 key', () async {
    final container = containerFor(Stream<String?>.value(null));

    final snapshot =
        await container.read(ebookProgressControllerProvider.future);
    expect(snapshot.books, isEmpty);

    await container
        .read(ebookProgressControllerProvider.notifier)
        .markChapterCompleted(bookId: _bookOne, chapterId: 'ebook-1-chapter-1');

    expect(box.keys, isEmpty);
    expect(
      container.read(ebookProgressControllerProvider).value!.books,
      isEmpty,
    );
  });

  test('空白 owner id 也視為未登入', () async {
    final container = containerFor(Stream<String?>.value('   '));
    final snapshot =
        await container.read(ebookProgressControllerProvider.future);
    expect(snapshot.books, isEmpty);
    expect(box.keys, isEmpty);
  });

  test('完成章節：await 寫入後才更新 state，且進度可從 box 重讀', () async {
    final container = containerFor(Stream<String?>.value(_ownerA));
    await container.read(ebookProgressControllerProvider.future);

    await container
        .read(ebookProgressControllerProvider.notifier)
        .markChapterCompleted(
          bookId: _bookOne,
          chapterId: 'ebook-1-chapter-1',
          contentVersion: 1,
        );

    final state = container.read(ebookProgressControllerProvider).value!;
    expect(
      state.bookProgress(_bookOne).completedChapterIds,
      {'ebook-1-chapter-1'},
    );
    expect(
      (await repo.load(_ownerA)).bookProgress(_bookOne).completedChapterIds,
      {'ebook-1-chapter-1'},
    );
    expect(
      container.read(ebookBookProgressProvider(_bookOne)).lastChapterId,
      'ebook-1-chapter-1',
    );
  });

  test('quiz 與 checklist 都經由 controller 保存', () async {
    final container = containerFor(Stream<String?>.value(_ownerA));
    await container.read(ebookProgressControllerProvider.future);
    final notifier = container.read(ebookProgressControllerProvider.notifier);

    await notifier.recordQuizSubmission(
      bookId: _bookOne,
      quizId: 'quiz-1',
      quizRevision: 2,
      choiceIds: const ['choice-b'],
      solved: true,
    );
    await notifier.setChecklistItem(
      bookId: _bookOne,
      blockId: 'check-1',
      itemId: 'item-1',
      checked: true,
    );

    final progress = container.read(ebookBookProgressProvider(_bookOne));
    expect(progress.quizStateFor('quiz-1', 2)?.solved, isTrue);
    expect(progress.quizStateFor('quiz-1', 3), isNull);
    expect(progress.checkedItemsFor('check-1'), {'item-1'});
  });

  test('換帳號後重建，不沿用上一個帳號的 snapshot', () async {
    final owners = StreamController<String?>();
    addTearDown(owners.close);
    final container = containerFor(owners.stream);

    owners.add(_ownerA);
    await container.read(ebookProgressControllerProvider.future);
    await container
        .read(ebookProgressControllerProvider.notifier)
        .markChapterCompleted(bookId: _bookOne, chapterId: 'ebook-1-chapter-1');
    expect(
      container.read(ebookBookProgressProvider(_bookOne)).completedChapterIds,
      {'ebook-1-chapter-1'},
    );

    owners.add(_ownerB);
    await container.pump();
    final forB = await container.read(ebookProgressControllerProvider.future);
    expect(forB.bookProgress(_bookOne).completedChapterIds, isEmpty,
        reason: '帳號 B 不得看到帳號 A 的進度');

    await container
        .read(ebookProgressControllerProvider.notifier)
        .markChapterCompleted(bookId: _bookOne, chapterId: 'ebook-1-chapter-4');

    owners.add(_ownerA);
    await container.pump();
    final backToA = await container.read(ebookProgressControllerProvider.future);
    expect(
      backToA.bookProgress(_bookOne).completedChapterIds,
      {'ebook-1-chapter-1'},
      reason: '同帳號重新登入應恢復自己的本機進度',
    );
  });

  test('登出 invalidate 後不保留舊帳號 snapshot', () async {
    final owners = StreamController<String?>();
    addTearDown(owners.close);
    final container = containerFor(owners.stream);

    owners.add(_ownerA);
    await container.read(ebookProgressControllerProvider.future);
    await container
        .read(ebookProgressControllerProvider.notifier)
        .markChapterCompleted(bookId: _bookOne, chapterId: 'ebook-1-chapter-1');

    owners.add(null);
    container.invalidate(ebookProgressControllerProvider);
    await container.pump();

    final afterLogout =
        await container.read(ebookProgressControllerProvider.future);
    expect(afterLogout.books, isEmpty);
  });

  test('已開始的寫入不會因為 provider dispose 而遺失', () async {
    final container = containerFor(Stream<String?>.value(_ownerA));
    await container.read(ebookProgressControllerProvider.future);

    final pending = container
        .read(ebookProgressControllerProvider.notifier)
        .markChapterCompleted(bookId: _bookOne, chapterId: 'ebook-1-chapter-2');

    container.invalidate(ebookProgressControllerProvider);
    await pending; // 不應拋錯（state 已死就只是不更新）

    expect(
      (await repo.load(_ownerA)).bookProgress(_bookOne).completedChapterIds,
      {'ebook-1-chapter-2'},
    );
  });

  test('bookProgress 切片在載入中先給空進度', () {
    final container = containerFor(const Stream<String?>.empty());
    expect(
      container.read(ebookBookProgressProvider(_bookOne)),
      same(EbookBookProgress.empty),
    );
  });
}
