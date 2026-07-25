// lib/features/learning/domain/ebook_reading_position.dart
//
// 續讀位置的純邏輯，刻意與 widget 分離以便單獨測試。
//
// 鐵則：resume 一律用 chapter id 決定，不用 index。調整章節順序或改寫章節時，
// 使用者不會被丟到別的一章；不合法的 id 一律 fallback，不 crash。
library;

import 'models/ebook.dart';
import 'models/ebook_progress.dart';

/// 「繼續閱讀」該落在哪一章。
///
/// 順序：
///   1. 已保存且仍存在的 lastChapterId。
///   2. 第一個還沒完成的章節。
///   3. 第一章。
String resolveResumeChapterId(Ebook book, EbookBookProgress progress) {
  final last = progress.lastChapterId;
  if (last != null && book.findChapter(last) != null) {
    return last;
  }
  for (final chapter in book.chapters) {
    if (!progress.isChapterCompleted(chapter.id)) {
      return chapter.id;
    }
  }
  return book.chapters.first.id;
}

/// 閱讀器的初始章節 index。
///
/// route 上的 chapterId 只決定初始頁；unknown chapter 依序 fallback 到
/// 保存的 lastChapterId（若合法）再到第一章。
int resolveInitialChapterIndex(
  Ebook book, {
  String? routeChapterId,
  required EbookBookProgress progress,
}) {
  if (routeChapterId != null) {
    final index = book.indexOfChapter(routeChapterId);
    if (index >= 0) return index;
  }
  final resumeIndex = book.indexOfChapter(resolveResumeChapterId(book, progress));
  return resumeIndex >= 0 ? resumeIndex : 0;
}

/// 這本書是否已經開始讀（決定 CTA 是「開始閱讀」還是「繼續閱讀」）。
bool ebookHasStarted(Ebook book, EbookBookProgress progress) {
  if (progress.completedChapterIds.isNotEmpty) return true;
  final last = progress.lastChapterId;
  return last != null && book.findChapter(last) != null;
}
