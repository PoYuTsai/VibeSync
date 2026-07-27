// lib/features/learning/domain/models/ebook.dart
//
// 互動電子書的書 / 章模型。
//
// 產品不變量（2026-07-25 拍板，CC 不自行改動）：
//   - 四本書、二十章。
//   - Book 1 免費，Books 2–4 訂閱（Starter 與 Essential 都算）。
//   - 非線性：付費使用者四本一次全開，不做前一本完成才解鎖下一本。
//   - 電子書不消耗既有文章每日免費額度，故這裡完全不碰 ArticleReadService。
library;

import 'ebook_block.dart';

/// 權限分界。只有 [free] 與 [premium] 兩種，tier 細節留給 subscription。
enum EbookAccess { free, premium }

/// 書封主題 key。JSON 只放語意 key，icon 與配色在 presentation 查表。
enum EbookTheme { compass, lens, firstAid, bridge }

/// 教材出處，讓內容可回溯到兩份來源教材的哪一節。
class EbookSourceRef {
  const EbookSourceRef({
    required this.document,
    required this.sections,
  });

  final String document;
  final List<String> sections;
}

class EbookChapter {
  const EbookChapter({
    required this.id,
    required this.number,
    required this.title,
    required this.learningGoal,
    required this.estimatedMinutes,
    required this.sourceRefs,
    required this.blocks,
  });

  final String id;

  /// 顯示用章號，例如 `1.3`。排序以 [Ebook.chapters] 的順序為準，不靠這個字串。
  final String number;
  final String title;

  /// 本章只回答一個問題；目錄與閱讀器都用它當一行說明。
  final String learningGoal;
  final int estimatedMinutes;
  final List<EbookSourceRef> sourceRefs;
  final List<EbookBlock> blocks;

  Iterable<EbookQuizBlock> get quizzes => blocks.whereType<EbookQuizBlock>();

  Iterable<EbookFlipCardBlock> get flipCards =>
      blocks.whereType<EbookFlipCardBlock>();

  Iterable<EbookChecklistBlock> get checklists =>
      blocks.whereType<EbookChecklistBlock>();

  Iterable<EbookDialogueBlock> get dialogues =>
      blocks.whereType<EbookDialogueBlock>();

  Iterable<EbookStageFunnelBlock> get stageFunnels =>
      blocks.whereType<EbookStageFunnelBlock>();

  Iterable<EbookEntryListBlock> get entryLists =>
      blocks.whereType<EbookEntryListBlock>();

  bool get hasSafetyCallout => blocks.any(
        (block) =>
            block is EbookCalloutBlock &&
            block.tone == EbookCalloutTone.safety,
      );
}

class Ebook {
  const Ebook({
    required this.schemaVersion,
    required this.id,
    required this.contentVersion,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.goal,
    required this.access,
    required this.theme,
    required this.estimatedMinutes,
    required this.sourceRefs,
    required this.chapters,
  });

  final int schemaVersion;
  final String id;

  /// 內容語意版本。純文案修改不必動；大改一章時應改 chapter id 或升這個版本。
  final int contentVersion;

  /// 書號 1–4，書架與封面排版用。
  final int number;
  final String title;
  final String subtitle;
  final String goal;
  final EbookAccess access;
  final EbookTheme theme;
  final int estimatedMinutes;
  final List<EbookSourceRef> sourceRefs;
  final List<EbookChapter> chapters;

  int get chapterCount => chapters.length;

  bool get isFree => access == EbookAccess.free;

  /// 唯一提供試讀的付費書書號。
  ///
  /// 2026-07-27 夥伴回饋（Eric 轉達）：免費閱讀＝第一冊全部＋第二冊第一章。
  /// 在此之前是「每一本付費書都開第一章」，第 3、4 本因此收回試讀。
  static const int previewBookNumber = 2;

  /// 免費試讀章數：免費書全開，第 2 本開第一章，其餘付費書 0 章。
  ///
  /// 這是產品規則而不是內容欄位：寫在 JSON 會讓「哪幾章免費」變成可被內容
  /// 誤改的付費邊界，寫在這裡則由 domain 測試守住。
  int get freePreviewChapterCount {
    if (isFree) return chapters.length;
    return number == previewBookNumber ? 1 : 0;
  }

  /// 未訂閱者可以讀的試讀章 id。免費書與沒有試讀章的付費書都回傳 `null`
  /// （免費書整本都不需要試讀概念；第 3、4 本則是真的一章都不開）。
  String? get previewChapterId => isFree || chapters.isEmpty || freePreviewChapterCount == 0
      ? null
      : chapters.first.id;

  /// 這一章在未訂閱狀態下是否可讀。
  bool isPreviewChapter(String chapterId) {
    if (isFree) return true;
    final index = indexOfChapter(chapterId);
    return index >= 0 && index < freePreviewChapterCount;
  }

  EbookChapter? findChapter(String chapterId) {
    for (final chapter in chapters) {
      if (chapter.id == chapterId) return chapter;
    }
    return null;
  }

  int indexOfChapter(String chapterId) =>
      chapters.indexWhere((chapter) => chapter.id == chapterId);
}

/// 四本書的集合。由 [EbookCatalogRepository] 建立並驗證。
class EbookCatalog {
  const EbookCatalog({required this.books});

  final List<Ebook> books;

  Ebook? findBook(String bookId) {
    for (final book in books) {
      if (book.id == bookId) return book;
    }
    return null;
  }

  EbookChapter? findChapter(String bookId, String chapterId) =>
      findBook(bookId)?.findChapter(chapterId);
}
