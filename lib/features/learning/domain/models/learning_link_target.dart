// lib/features/learning/domain/models/learning_link_target.dart
//
// Dating Knowledge Library 的深連目標。
//
// 刻意「只帶 id，不帶路徑字串」：route 樣板的唯一真相源是
// `ebook_detail_screen.dart` 的 `ebookChapterRoute()`，由 presentation 呼叫端
// 自己組。若這裡也存一份組好的路徑，route 改動就有兩處要同步——那正是
// taxonomy 漂移最常見的起點。
library;

import 'package:flutter/foundation.dart';

@immutable
class LearningLinkTarget {
  const LearningLinkTarget({
    required this.bookId,
    required this.chapterId,
    this.entryId,
  });

  final String bookId;
  final String chapterId;

  /// 章內定位點（entryList 的條目 id）；null 表示只捲到章首。
  /// 不存在的 entry id 由閱讀器忽略，不會 404。
  final String? entryId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LearningLinkTarget &&
        other.bookId == bookId &&
        other.chapterId == chapterId &&
        other.entryId == entryId;
  }

  @override
  int get hashCode => Object.hash(bookId, chapterId, entryId);

  @override
  String toString() => 'LearningLinkTarget(bookId: $bookId, '
      'chapterId: $chapterId, entryId: $entryId)';
}
