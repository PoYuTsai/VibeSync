// lib/features/learning/domain/models/ebook_progress.dart
//
// 互動電子書的本機進度模型。
//
// 儲存規則（2026-07-25 拍板）：
//   - resume 存 chapter id，不存 index：調整章節順序不會把使用者丟到別章。
//   - quiz 存 stable choice string id 與 quizRevision：題目語意改版時舊答案失效。
//   - checklist 只存被勾選的 item id，絕不接受自由文字。
//   - 不儲存任何真實聊天內容或反思文字。
library;

/// 單一題目的作答狀態。
class EbookQuizState {
  const EbookQuizState({
    required this.quizRevision,
    required this.selectedChoiceIds,
    required this.solved,
  });

  final int quizRevision;
  final List<String> selectedChoiceIds;
  final bool solved;

  Map<String, Object?> toJson() => <String, Object?>{
        'quizRevision': quizRevision,
        'selectedChoiceIds': selectedChoiceIds,
        'solved': solved,
      };

  /// 回傳 `null` 表示這筆資料型別不可信，呼叫端當成未作答。
  static EbookQuizState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final revision = raw['quizRevision'];
    final solved = raw['solved'];
    final selected = raw['selectedChoiceIds'];
    if (revision is! int || revision < 1) return null;
    if (solved is! bool) return null;
    if (selected is! List) return null;
    final ids = selected
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    return EbookQuizState(
      quizRevision: revision,
      selectedChoiceIds: ids,
      solved: solved,
    );
  }
}

/// 單一本書的進度。
class EbookBookProgress {
  const EbookBookProgress({
    this.contentVersionSeen,
    this.lastChapterId,
    this.completedChapterIds = const <String>{},
    this.quizStates = const <String, EbookQuizState>{},
    this.checklistStates = const <String, Set<String>>{},
  });

  static const empty = EbookBookProgress();

  /// 使用者上次看到的內容版本。
  ///
  /// 刻意只記錄、不用來失效進度：拍板的策略是「純文案修改保留進度；真正改寫
  /// 一章時改 chapter id 或升 quiz revision」。所以 contentVersion 變動不會清掉
  /// 已完成章節或 checklist——那由 id／revision 負責。這個欄位留給未來需要
  /// 明確 migration 時判斷起點。
  final int? contentVersionSeen;

  /// 上次讀到哪一章（章節 id，不是 index）。
  final String? lastChapterId;
  final Set<String> completedChapterIds;

  /// quizId -> 作答狀態。
  final Map<String, EbookQuizState> quizStates;

  /// checklist blockId -> 已勾選的 item id 集合。
  final Map<String, Set<String>> checklistStates;

  bool isChapterCompleted(String chapterId) =>
      completedChapterIds.contains(chapterId);

  /// 完成度 = 已完成章節數 ÷ 總章節數。刻意不用 scroll 百分比。
  double completionRatio(int totalChapters) {
    if (totalChapters <= 0) return 0;
    final completed = completedChapterIds.length.clamp(0, totalChapters);
    return completed / totalChapters;
  }

  /// 取出這一題已保存的答案；[quizRevision] 不符時回 `null`（視為未作答）。
  EbookQuizState? quizStateFor(String quizId, int quizRevision) {
    final state = quizStates[quizId];
    if (state == null) return null;
    if (state.quizRevision != quizRevision) return null;
    return state;
  }

  Set<String> checkedItemsFor(String blockId) =>
      checklistStates[blockId] ?? const <String>{};

  EbookBookProgress copyWith({
    int? contentVersionSeen,
    String? lastChapterId,
    Set<String>? completedChapterIds,
    Map<String, EbookQuizState>? quizStates,
    Map<String, Set<String>>? checklistStates,
  }) {
    return EbookBookProgress(
      contentVersionSeen: contentVersionSeen ?? this.contentVersionSeen,
      lastChapterId: lastChapterId ?? this.lastChapterId,
      completedChapterIds: completedChapterIds ?? this.completedChapterIds,
      quizStates: quizStates ?? this.quizStates,
      checklistStates: checklistStates ?? this.checklistStates,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (contentVersionSeen != null) 'contentVersionSeen': contentVersionSeen,
        if (lastChapterId != null) 'lastChapterId': lastChapterId,
        'completedChapterIds': completedChapterIds.toList(growable: false),
        'quizStates': <String, Object?>{
          for (final entry in quizStates.entries)
            entry.key: entry.value.toJson(),
        },
        'checklistStates': <String, Object?>{
          for (final entry in checklistStates.entries)
            entry.key: entry.value.toList(growable: false),
        },
      };

  /// 寬容解析：單一欄位壞掉只丟掉那一欄，不讓整本書的進度消失。
  static EbookBookProgress fromJson(Object? raw) {
    if (raw is! Map) return empty;

    final contentVersionSeen = raw['contentVersionSeen'];
    final lastChapterId = raw['lastChapterId'];

    final completed = <String>{};
    final completedRaw = raw['completedChapterIds'];
    if (completedRaw is List) {
      completed.addAll(
        completedRaw.whereType<String>().where((id) => id.trim().isNotEmpty),
      );
    }

    final quizStates = <String, EbookQuizState>{};
    final quizRaw = raw['quizStates'];
    if (quizRaw is Map) {
      for (final entry in quizRaw.entries) {
        final key = entry.key;
        if (key is! String || key.trim().isEmpty) continue;
        final state = EbookQuizState.fromJson(entry.value);
        if (state != null) quizStates[key] = state;
      }
    }

    final checklistStates = <String, Set<String>>{};
    final checklistRaw = raw['checklistStates'];
    if (checklistRaw is Map) {
      for (final entry in checklistRaw.entries) {
        final key = entry.key;
        if (key is! String || key.trim().isEmpty) continue;
        final value = entry.value;
        if (value is! List) continue;
        final items = value
            .whereType<String>()
            .where((id) => id.trim().isNotEmpty)
            .toSet();
        if (items.isNotEmpty) checklistStates[key] = items;
      }
    }

    return EbookBookProgress(
      contentVersionSeen:
          contentVersionSeen is int ? contentVersionSeen : null,
      lastChapterId: lastChapterId is String && lastChapterId.trim().isNotEmpty
          ? lastChapterId
          : null,
      completedChapterIds: completed,
      quizStates: quizStates,
      checklistStates: checklistStates,
    );
  }
}

/// 一個帳號的完整電子書進度。
class EbookProgressSnapshot {
  const EbookProgressSnapshot({
    this.schemaVersion = currentSchemaVersion,
    this.updatedAt,
    this.books = const <String, EbookBookProgress>{},
  });

  static const int currentSchemaVersion = 1;
  static const empty = EbookProgressSnapshot();

  final int schemaVersion;
  final DateTime? updatedAt;
  final Map<String, EbookBookProgress> books;

  EbookBookProgress bookProgress(String bookId) =>
      books[bookId] ?? EbookBookProgress.empty;

  EbookProgressSnapshot withBook(
    String bookId,
    EbookBookProgress progress, {
    DateTime? updatedAt,
  }) {
    return EbookProgressSnapshot(
      schemaVersion: currentSchemaVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      books: <String, EbookBookProgress>{...books, bookId: progress},
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
        'books': <String, Object?>{
          for (final entry in books.entries) entry.key: entry.value.toJson(),
        },
      };

  /// 未知 schema version 一律回空 snapshot（fail closed），並且不刪除原始資料。
  static EbookProgressSnapshot fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final schemaVersion = raw['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != currentSchemaVersion) {
      return empty;
    }

    final books = <String, EbookBookProgress>{};
    final booksRaw = raw['books'];
    if (booksRaw is Map) {
      for (final entry in booksRaw.entries) {
        final key = entry.key;
        if (key is! String || key.trim().isEmpty) continue;
        books[key] = EbookBookProgress.fromJson(entry.value);
      }
    }

    final updatedAtRaw = raw['updatedAt'];
    return EbookProgressSnapshot(
      schemaVersion: currentSchemaVersion,
      updatedAt: updatedAtRaw is String ? DateTime.tryParse(updatedAtRaw) : null,
      books: books,
    );
  }
}
