// lib/features/learning/data/repositories/ebook_progress_repository.dart
//
// 電子書進度的本機儲存。
//
// 為什麼不用 ArticleReadService／usageBox：電子書拍板為「不消耗文章每日額度」，
// 兩者共用任何 key 都可能讓閱讀電子書扣掉文章配額。這裡只用加密的 settingsBox，
// 而且 key 一律綁帳號 id。
//
// Key：`learning_progress_v1:<ownerUserId>`
//   - ownerUserId 必須是目前 Supabase account id（trim 後非空），不得用 email。
//   - 沒有帳號時完全不寫入（fail closed），不建立 `anonymous` 共用進度。
//
// 寫入語意：所有 mutator 都 await Hive 寫入才回傳，並在 repository 內序列化，
// 避免快速連續操作時 read-modify-write 互相覆蓋。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive_ce/hive_ce.dart';

import '../../domain/models/ebook_progress.dart';

class EbookProgressRepository {
  EbookProgressRepository({
    required Box box,
    DateTime Function()? now,
  })  : _box = box,
        _now = now ?? DateTime.now;

  static const String storageKeyPrefix = 'learning_progress_v1';

  final Box _box;
  final DateTime Function() _now;

  /// 序列化寫入用的尾端 Future。任何 action 拋錯都不會弄壞這條鏈。
  Future<void> _tail = Future<void>.value();

  static String storageKeyFor(String ownerUserId) {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) {
      throw ArgumentError('ownerUserId 不得為空：電子書進度必須綁定帳號');
    }
    return '$storageKeyPrefix:$owner';
  }

  Future<EbookProgressSnapshot> load(String ownerUserId) {
    return _serialize(() async => _read(ownerUserId));
  }

  /// 完成章節。冪等：重複呼叫不會改變結果。
  Future<EbookProgressSnapshot> markChapterCompleted({
    required String ownerUserId,
    required String bookId,
    required String chapterId,
    int? contentVersion,
  }) {
    return _mutate(ownerUserId, bookId, (progress) {
      if (progress.completedChapterIds.contains(chapterId) &&
          progress.lastChapterId == chapterId &&
          (contentVersion == null ||
              progress.contentVersionSeen == contentVersion)) {
        return progress;
      }
      return progress.copyWith(
        contentVersionSeen: contentVersion,
        lastChapterId: chapterId,
        completedChapterIds: <String>{
          ...progress.completedChapterIds,
          chapterId,
        },
      );
    });
  }

  Future<EbookProgressSnapshot> setLastChapter({
    required String ownerUserId,
    required String bookId,
    required String chapterId,
    int? contentVersion,
  }) {
    return _mutate(ownerUserId, bookId, (progress) {
      if (progress.lastChapterId == chapterId &&
          (contentVersion == null ||
              progress.contentVersionSeen == contentVersion)) {
        return progress;
      }
      return progress.copyWith(
        contentVersionSeen: contentVersion,
        lastChapterId: chapterId,
      );
    });
  }

  Future<EbookProgressSnapshot> recordQuizSubmission({
    required String ownerUserId,
    required String bookId,
    required String quizId,
    required int quizRevision,
    required List<String> choiceIds,
    required bool solved,
  }) {
    return _mutate(ownerUserId, bookId, (progress) {
      return progress.copyWith(
        quizStates: <String, EbookQuizState>{
          ...progress.quizStates,
          quizId: EbookQuizState(
            quizRevision: quizRevision,
            selectedChoiceIds:
                choiceIds.toSet().toList(growable: false),
            solved: solved,
          ),
        },
      );
    });
  }

  Future<EbookProgressSnapshot> setChecklistItem({
    required String ownerUserId,
    required String bookId,
    required String blockId,
    required String itemId,
    required bool checked,
  }) {
    return _mutate(ownerUserId, bookId, (progress) {
      final current = <String>{...progress.checkedItemsFor(blockId)};
      if (checked) {
        current.add(itemId);
      } else {
        current.remove(itemId);
      }
      final next = <String, Set<String>>{...progress.checklistStates};
      if (current.isEmpty) {
        next.remove(blockId);
      } else {
        next[blockId] = current;
      }
      return progress.copyWith(checklistStates: next);
    });
  }

  // -------------------------------------------------------------------------

  Future<EbookProgressSnapshot> _mutate(
    String ownerUserId,
    String bookId,
    EbookBookProgress Function(EbookBookProgress progress) update,
  ) {
    return _serialize(() async {
      final key = storageKeyFor(ownerUserId);
      final snapshot = _read(ownerUserId);
      final current = snapshot.bookProgress(bookId);
      final updated = update(current);
      final next = snapshot.withBook(bookId, updated, updatedAt: _now());
      await _box.put(key, jsonEncode(next.toJson()));
      return next;
    });
  }

  /// 同步讀取並解碼。損壞資料回空 snapshot，並且刻意不刪除原 key
  /// （後續正常寫入才會覆蓋），也不把 raw payload 寫進 log。
  EbookProgressSnapshot _read(String ownerUserId) {
    final key = storageKeyFor(ownerUserId);
    final raw = _box.get(key);
    if (raw == null) return EbookProgressSnapshot.empty;
    if (raw is! String || raw.trim().isEmpty) {
      debugPrint('[ebook-progress] 進度資料型別不符，改用空進度。');
      return EbookProgressSnapshot.empty;
    }
    try {
      return EbookProgressSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      debugPrint('[ebook-progress] 進度資料無法解析，改用空進度。');
      return EbookProgressSnapshot.empty;
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
