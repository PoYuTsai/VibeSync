// lib/features/learning/data/repositories/chat_quiz_progress_repository.dart
//
// 聊天測驗進度的本機儲存。
//
// Key：`chat_quiz_progress_v1:<ownerUserId>`
//   - **獨立於電子書的 `learning_progress_v1:`。** 兩者共用一顆 key 或一顆
//     schemaVersion，都會讓測驗改版清光使用者的閱讀進度（見
//     `chat_quiz_progress.dart` 的說明）。
//   - ownerUserId 必須是目前 Supabase account id（trim 後非空），不得用 email。
//   - 沒有帳號時完全不寫入（fail closed），不建立 `anonymous` 共用進度。
//
// 寫入語意：所有 mutator 都 await Hive 寫入才回傳，並在 repository 內序列化，
// 避免連點造成 read-modify-write 互相覆蓋。
//
// 這裡完全不碰網路、額度與計費：測驗重試無限次、不扣任何東西。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive_ce/hive_ce.dart';

import '../../domain/models/chat_quiz_progress.dart';

class ChatQuizProgressRepository {
  ChatQuizProgressRepository({
    required Box box,
    DateTime Function()? now,
  })  : _box = box,
        _now = now ?? DateTime.now;

  static const String storageKeyPrefix = 'chat_quiz_progress_v1';

  final Box _box;
  final DateTime Function() _now;

  /// 序列化寫入用的尾端 Future。任何 action 拋錯都不會弄壞這條鏈。
  Future<void> _tail = Future<void>.value();

  static String storageKeyFor(String ownerUserId) {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) {
      throw ArgumentError('ownerUserId 不得為空：測驗進度必須綁定帳號');
    }
    return '$storageKeyPrefix:$owner';
  }

  Future<ChatQuizProgress> load(String ownerUserId) {
    return _serialize(() async => _read(ownerUserId));
  }

  /// 記錄一題的作答。
  ///
  /// 冪等：同一題、同一個 revision、同一個選項重複送出不改變任何東西
  /// （連點兩次送出不會蓋掉作答時間）。
  Future<ChatQuizProgress> recordAnswer({
    required String ownerUserId,
    required String questionId,
    required String choiceId,
    required int revision,
  }) {
    return _mutate(ownerUserId, (progress) {
      final existing = progress.answers[questionId];
      if (existing != null &&
          existing.choiceId == choiceId &&
          existing.revision == revision) {
        return progress;
      }
      return progress.copyWith(
        answers: <String, ChatQuizAnswer>{
          ...progress.answers,
          questionId: ChatQuizAnswer(
            choiceId: choiceId,
            revision: revision,
            answeredAt: _now(),
          ),
        },
      );
    });
  }

  /// 記錄一關跑完的成績，只留最好的那一次。
  ///
  /// 成績沒有變好就是 no-op：重試不扣任何東西，也不該把先前更好的成績蓋掉。
  Future<ChatQuizProgress> recordLevelResult({
    required String ownerUserId,
    required String levelId,
    required int correctCount,
    required int questionCount,
    required bool passed,
  }) {
    return _mutate(ownerUserId, (progress) {
      // 在 mutator 內驗證，讓所有錯誤都以同一種形式（Future 上的錯誤）冒出來，
      // 呼叫端不必分辨哪些是同步拋、哪些是非同步拋。
      if (questionCount < 1) {
        throw ArgumentError('questionCount 必須 >= 1');
      }
      if (correctCount < 0 || correctCount > questionCount) {
        throw ArgumentError('correctCount 必須落在 0..$questionCount');
      }
      final candidate = ChatQuizLevelResult(
        correctCount: correctCount,
        questionCount: questionCount,
        passed: passed,
        achievedAt: _now(),
      );
      final existing = progress.levels[levelId];
      if (existing != null && !candidate.isBetterThan(existing)) {
        return progress;
      }
      return progress.copyWith(
        levels: <String, ChatQuizLevelResult>{
          ...progress.levels,
          levelId: candidate,
        },
      );
    });
  }

  /// 清掉某一關的作答，讓「再跑一次」從第一題重新開始。
  ///
  /// 刻意不動 [ChatQuizProgress.levels]：最佳成績是使用者已經拿到的東西，
  /// 重跑一次不該把它收回去。
  Future<ChatQuizProgress> clearAnswers({
    required String ownerUserId,
    required List<String> questionIds,
  }) {
    return _mutate(ownerUserId, (progress) {
      final next = <String, ChatQuizAnswer>{...progress.answers};
      var changed = false;
      for (final questionId in questionIds) {
        if (next.remove(questionId) != null) changed = true;
      }
      return changed ? progress.copyWith(answers: next) : progress;
    });
  }

  // -------------------------------------------------------------------------

  Future<ChatQuizProgress> _mutate(
    String ownerUserId,
    ChatQuizProgress Function(ChatQuizProgress progress) update,
  ) {
    return _serialize(() async {
      final key = storageKeyFor(ownerUserId);
      final current = _read(ownerUserId);
      final updated = update(current);
      if (identical(updated, current)) return current;
      final next = updated.copyWith(updatedAt: _now());
      await _box.put(key, jsonEncode(next.toJson()));
      return next;
    });
  }

  /// 同步讀取並解碼。損壞資料回空進度，並且刻意不刪除原 key
  /// （後續正常寫入才會覆蓋），也不把 raw payload 寫進 log。
  ChatQuizProgress _read(String ownerUserId) {
    final key = storageKeyFor(ownerUserId);
    final raw = _box.get(key);
    if (raw == null) return ChatQuizProgress.empty;
    if (raw is! String || raw.trim().isEmpty) {
      debugPrint('[chat-quiz-progress] 進度資料型別不符，改用空進度。');
      return ChatQuizProgress.empty;
    }
    try {
      return ChatQuizProgress.fromJson(jsonDecode(raw));
    } catch (_) {
      debugPrint('[chat-quiz-progress] 進度資料無法解析，改用空進度。');
      return ChatQuizProgress.empty;
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
