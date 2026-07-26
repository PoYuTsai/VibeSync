// test/unit/features/learning/ebook_content_invariants_test.dart
//
// 真實 bundled 內容的不變量。這裡守的是教材契約而不是程式行為。
//
// 2026-07-27 內容全面換成夥伴版本（四章約 18,000 字）之後，這份契約跟著換：
//   - 舊契約要求「每章至少一張翻卡、一題 Quiz、一段對話」。新內容沒有翻卡與
//     測驗（夥伴回饋：測驗多餘），對話只集中在拆解庫，所以那三條移除。
//   - 新增的是條目庫契約：一半篇幅是「查的」不是「讀的」，那些內容必須是
//     entryList（列表→點開），不能攤成長捲。
//   - 安全／同意 callout 與禁語表：舊內容是我們自己寫的，新內容照夥伴原文，
//     Eric 2026-07-27 拍板不另外加判斷，所以那兩條移除。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';

import '../../../helpers/ebook_test_content.dart';

/// 第一章是診斷章：它的互動是漏斗。
const _diagnosisChapterId = 'ebook-1-chapter-1';

/// 攤平章節區塊，含條目庫裡的巢狀區塊。
Iterable<EbookBlock> _flatten(Iterable<EbookBlock> blocks) sync* {
  for (final block in blocks) {
    yield block;
    if (block is EbookEntryListBlock) {
      for (final entry in block.entries) {
        yield* _flatten(entry.blocks);
      }
    }
  }
}

/// 抓出一個區塊裡所有使用者可見的文字，用於內容掃描。
List<String> _blockTexts(EbookBlock block) {
  final texts = <String?>[];
  switch (block) {
    case EbookHeadingBlock():
      texts.add(block.text);
    case EbookParagraphBlock():
      texts.add(block.text);
    case EbookBulletListBlock():
      texts.add(block.title);
      texts.addAll(block.items);
    case EbookCalloutBlock():
      texts.addAll([block.title, block.text]);
    case EbookComparisonBlock():
      texts.addAll([block.title, block.caption]);
      for (final item in block.items) {
        texts.addAll([item.label, item.text, item.note]);
      }
    case EbookDialogueBlock():
      texts.addAll([block.title, block.caption]);
      for (final line in block.lines) {
        texts.addAll([line.text, line.timeLabel, line.annotation]);
      }
    case EbookFlipCardBlock():
      texts.addAll([
        block.frontTitle,
        block.frontText,
        block.backTitle,
        block.backText,
      ]);
      texts.addAll(block.backPoints);
    case EbookQuizBlock():
      texts.addAll([block.question, block.scenario, block.takeaway]);
      for (final choice in block.choices) {
        texts.addAll([choice.text, choice.feedback]);
      }
    case EbookStageFunnelBlock():
      texts.addAll([block.title, block.intro]);
      for (final stage in block.stages) {
        texts.addAll([
          stage.stageName,
          stage.symptom,
          stage.verdictTitle,
          stage.verdictText,
          stage.targetLabel,
        ]);
      }
    case EbookEntryListBlock():
      texts.addAll([block.title, block.caption]);
      for (final entry in block.entries) {
        texts.addAll([entry.title, entry.summary]);
      }
    case EbookChecklistBlock():
      texts.addAll([block.title, block.caption]);
      for (final item in block.items) {
        texts.addAll([item.text, item.note]);
      }
    case EbookCrossRefBlock():
      texts.addAll([block.label, block.contextLabel]);
  }
  return texts.whereType<String>().toList();
}

String _chapterText(EbookChapter chapter) => [
      chapter.title,
      chapter.learningGoal,
      for (final block in _flatten(chapter.blocks)) ..._blockTexts(block),
    ].join('\n');

/// 原文的交叉指涉寫法。與轉換器（tools/content）的偵測規則對齊。
final _crossRefPhrase =
    RegExp(r'見案例\s*[A-Z]|課本\s*\d+\.\d+|見第[一二三四五六七八九十]+節');

/// 出現這些反效果技巧名稱的章節，必須同時有 warning callout，
/// 確保它們只出現在「為何不要這樣做」的框架裡。
const _manipulationTerms = <String>[
  'Negging',
  '間歇性',
  '棘輪',
  '忽冷忽熱',
  '貶低',
];

void main() {
  late EbookCatalog catalog;

  setUpAll(() async {
    catalog = await loadProductionCatalog();
  });

  test('每本書的 metadata 完整且可回溯來源', () {
    for (final book in catalog.books) {
      expect(book.sourceRefs, isNotEmpty, reason: '${book.id} 缺 sourceRefs');
      expect(book.chapters, isNotEmpty, reason: '${book.id} 沒有章節');
      expect(book.estimatedMinutes, greaterThan(0));
      expect(book.title.trim(), isNotEmpty);
      expect(book.subtitle.trim(), isNotEmpty);
      expect(book.goal.trim(), isNotEmpty);
    }
  });

  test('每章都有內容、學習目標與來源', () {
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        final where = '${book.id}/${chapter.id}';
        expect(chapter.blocks, isNotEmpty, reason: '$where 沒有區塊');
        expect(chapter.sourceRefs, isNotEmpty, reason: '$where 缺 sourceRefs');
        expect(chapter.learningGoal.trim(), isNotEmpty, reason: '$where 缺學習目標');
        expect(chapter.estimatedMinutes, greaterThan(0), reason: '$where 缺閱讀時間');
      }
    }
  });

  test('章號在每本書內唯一且遞增', () {
    for (final book in catalog.books) {
      final numbers = book.chapters.map((chapter) => chapter.number).toList();
      expect(numbers.toSet(), hasLength(numbers.length),
          reason: '${book.id} 章號重複');
      for (var index = 0; index < numbers.length; index++) {
        expect(numbers[index], '${book.number}.${index + 1}',
            reason: '${book.id} 第 ${index + 1} 章章號與順序不一致');
      }
    }
  });

  test('所有區塊 id（含條目庫巢狀）與章節 id 全域唯一', () {
    final blockIds = <String>{};
    final chapterIds = <String>{};
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        expect(chapterIds.add(chapter.id), isTrue,
            reason: '章節 id 重複：${chapter.id}');
        for (final block in _flatten(chapter.blocks)) {
          expect(blockIds.add(block.id), isTrue,
              reason: '區塊 id 重複：${block.id}');
        }
      }
    }
  });

  test('診斷章用漏斗，五層都指向真的存在的章節', () {
    final chapter = catalog.findChapter(
      'ebook-1-bottleneck',
      _diagnosisChapterId,
    );
    expect(chapter, isNotNull);
    final funnel = chapter!.stageFunnels.single;
    expect(funnel.stages, hasLength(5), reason: '漏斗應對應五個階段');
    expect(funnel.stages.map((s) => s.number).toList(),
        const ['0', '1', '2', '3', '4']);
    for (final stage in funnel.stages) {
      expect(
        catalog.findChapter(stage.targetBookId, stage.targetChapterId),
        isNotNull,
        reason: '${stage.id} 的跳章目標不存在',
      );
    }
    // 夥伴回饋（2026-07-26）：這一章不要算術型測驗，也不要教練示範對話。
    expect(chapter.quizzes, isEmpty);
    expect(chapter.dialogues, isEmpty);
  });

  test('查閱型內容一律是條目庫，不攤成長捲', () {
    // 這五章是「查的」不是「讀的」：開場範例、對話拆解、反效果技巧、
    // 疑難情境、常見問題。它們必須是 entryList，否則單章會出現數千字的牆。
    const libraryChapters = <String, int>{
      'ebook-1-chapter-5': 8, // 八種檔案類型
      'ebook-2-chapter-5': 13, // 對話逐句拆解
      'ebook-3-chapter-2': 6, // 六個反效果技巧
      'ebook-3-chapter-3': 8, // 疑難情境
      'ebook-3-chapter-4': 12, // 常見問題
    };
    for (final entry in libraryChapters.entries) {
      final chapter = catalog.books
          .expand((book) => book.chapters)
          .firstWhere((chapter) => chapter.id == entry.key);
      final lists = chapter.entryLists.toList();
      expect(lists, isNotEmpty, reason: '${entry.key} 應該是條目庫');
      final biggest = lists
          .map((list) => list.entries.length)
          .reduce((a, b) => a > b ? a : b);
      expect(biggest, greaterThanOrEqualTo(entry.value),
          reason: '${entry.key} 條目數少於預期');
    }
  });

  test('每一條條目都有標題與內容，且不巢狀第二層條目庫', () {
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        for (final list in chapter.entryLists) {
          expect(list.entries.length, greaterThanOrEqualTo(2),
              reason: '${list.id} 只有一條，不需要做成列表');
          for (final entry in list.entries) {
            expect(entry.title.trim(), isNotEmpty, reason: '${entry.id} 缺標題');
            expect(entry.blocks, isNotEmpty, reason: '${entry.id} 沒有內容');
            expect(
              entry.blocks.whereType<EbookEntryListBlock>(),
              isEmpty,
              reason: '${entry.id} 出現第二層條目庫',
            );
          }
        }
      }
    }
  });

  test('沒有任何空白文字漏進內容', () {
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        for (final block in _flatten(chapter.blocks)) {
          for (final text in _blockTexts(block)) {
            expect(text.trim(), isNotEmpty,
                reason: '${block.id} 有空字串');
          }
        }
      }
    }
  });

  test('反效果技巧只出現在否定框架裡，不得被包裝成正向技巧', () {
    // 框架有三種合法形狀，只認 warning callout 會誤殺：
    //   1. warning／safety callout（警告區那一章）
    //   2. 帶死亡點的對話案例（拆解庫：示範它失敗）
    //   3. 提到它的那一句話本身就在否定它（例如「…→ 不用」）
    const negations = ['不用', '不要', '別', '反效果', '死亡', '失敗', '崩', '扣分'];
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        final blocks = _flatten(chapter.blocks).toList();
        final texts = blocks.expand(_blockTexts).toList();
        final hits = _manipulationTerms
            .where((term) => texts.any((text) => text.contains(term)))
            .toList();
        if (hits.isEmpty) continue;

        final hasWarningCallout = blocks.any(
          (block) =>
              block is EbookCalloutBlock &&
              (block.tone == EbookCalloutTone.warning ||
                  block.tone == EbookCalloutTone.safety),
        );
        final hasDeathPoint = blocks.any(
          (block) =>
              block is EbookDialogueBlock &&
              block.lines.any((line) => line.isDeathPoint),
        );
        if (hasWarningCallout || hasDeathPoint) continue;

        for (final term in hits) {
          for (final text in texts.where((text) => text.contains(term))) {
            expect(
              negations.any(text.contains),
              isTrue,
              reason: '${book.id}/${chapter.id} 提到「$term」卻沒有否定框架：$text',
            );
          }
        }
      }
    }
  });

  // 原文到處寫「見案例 K」「課本 6.1」，但案例庫在第 2 本、警告區在第 3 本。
  // 沒有按鈕時那行字等於死巷：讀者得退出閱讀器、回書架、開另一本、翻章、再從
  // 十幾條裡找字母。
  test('原文寫「見案例 X／課本 6.x／見第 N 節」的地方都有前往按鈕', () {
    final missing = <String>[];
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        void check(String where, List<EbookBlock> container) {
          final texts = container.expand(_blockTexts).join('\n');
          if (!_crossRefPhrase.hasMatch(texts)) return;
          if (container.whereType<EbookCrossRefBlock>().isNotEmpty) return;
          missing.add('$where：${_crossRefPhrase.firstMatch(texts)![0]}');
        }

        // 章層級：條目庫另外逐條檢查（它的按鈕在條目裡，不在章層級），
        // 否則條目摘要裡的指涉會在這裡誤報。
        check(
          '${book.id}/${chapter.id}',
          chapter.blocks
              .where((block) => block is! EbookEntryListBlock)
              .toList(),
        );
        for (final list in chapter.entryLists) {
          for (final entry in list.entries) {
            check(
              '${book.id}/${chapter.id}/${entry.id}',
              [
                EbookParagraphBlock(id: '${entry.id}-title', text: entry.title),
                if (entry.summary != null)
                  EbookParagraphBlock(
                      id: '${entry.id}-summary', text: entry.summary!),
                ...entry.blocks,
              ],
            );
          }
        }
      }
    }
    expect(missing, isEmpty, reason: '這些交叉指涉沒有前往按鈕：$missing');
  });

  test('每個前往按鈕的目標章與目標條目都真的存在', () {
    var count = 0;
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        for (final block in _flatten(chapter.blocks)) {
          if (block is! EbookCrossRefBlock) continue;
          count++;
          final target =
              catalog.findChapter(block.targetBookId, block.targetChapterId);
          expect(target, isNotNull, reason: '${block.id} 的目標章不存在');
          final entryId = block.targetEntryId;
          if (entryId == null) continue;
          expect(
            target!.entryLists.expand((list) => list.entries).any(
                  (entry) => entry.id == entryId,
                ),
            isTrue,
            reason: '${block.id} 的目標條目 $entryId 不在目標章裡',
          );
        }
      }
    }
    // 內容若被改到一顆按鈕都不剩，上一條測試會空轉而不報錯，所以這裡要求
    // 這批指涉至少全部在（2026-07-27 是 8 顆）。
    expect(count, greaterThanOrEqualTo(8));
  });

  test('對話拆解庫涵蓋案例 A–N（案例 N 曾經被轉換器整條吃掉）', () {
    final chapter = catalog.findChapter(
      'ebook-2-conversation',
      'ebook-2-chapter-5',
    )!;
    final titles = chapter.entryLists
        .expand((list) => list.entries)
        .map((entry) => entry.title)
        .toList();
    for (final letter in 'ABCDEFGHIJKLMN'.split('')) {
      expect(
        titles.any((title) => title.startsWith('案例 $letter ')),
        isTrue,
        reason: '缺少案例 $letter',
      );
    }
  });

  test('來源校正：六個功能位與五個變數標記', () {
    final bottleneck = catalog.findBook('ebook-1-bottleneck')!;
    expect(
      bottleneck.chapters.map(_chapterText).join('\n').contains('六個功能位'),
      isTrue,
    );
    final conversation = catalog.findBook('ebook-2-conversation')!;
    final markerText = conversation.chapters.map(_chapterText).join('\n');
    for (final marker in const ['價值', '框架', '情緒', '投資', '互惠']) {
      expect(markerText.contains(marker), isTrue, reason: '缺少變數：$marker');
    }
  });

  test('恰好四本、二十章，每本五章', () {
    expect(catalog.books, hasLength(4));
    for (final book in catalog.books) {
      expect(book.chapters, hasLength(5), reason: '${book.id} 章數不是 5');
    }
    final totalChapters = catalog.books.fold<int>(
      0,
      (sum, book) => sum + book.chapterCount,
    );
    expect(totalChapters, 20);
  });

  test('權限分界：Book 1 免費，Books 2–4 訂閱', () {
    expect(catalog.books.first.id, 'ebook-1-bottleneck');
    expect(catalog.books.first.access, EbookAccess.free);
    for (final book in catalog.books.skip(1)) {
      expect(book.access, EbookAccess.premium, reason: '${book.id} 應為訂閱內容');
    }
  });

  test('每一章的閱讀量都在可讀範圍內（不出現數千字的牆）', () {
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        // 條目庫章的總字數可以高，但那是分散在各條裡的；這裡量的是
        // 「一次攤在畫面上」的量：章層級區塊（不含條目內文）。
        final flat = chapter.blocks
            .where((block) => block is! EbookEntryListBlock)
            .expand(_blockTexts)
            .join()
            .length;
        expect(
          flat,
          lessThan(3000),
          reason: '${book.id}/${chapter.id} 章層級文字 $flat 字，太長',
        );
      }
    }
  });
}
