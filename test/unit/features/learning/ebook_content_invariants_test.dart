// test/unit/features/learning/ebook_content_invariants_test.dart
//
// 真實 bundled 內容的不變量。這裡守的是教材契約而不是程式行為：
//   - 每章至少一張翻卡、一題 Quiz、一段對話。
//   - 涉及邀約／拒絕／升級的章節必須有安全 callout。
//   - 來源校正（五標記、十四案例、六個功能位）不得回歸。
//   - 反操弄立場不得被重新包裝成正向技巧。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';

import '../../../helpers/ebook_test_content.dart';

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
    case EbookChecklistBlock():
      texts.addAll([block.title, block.caption]);
      for (final item in block.items) {
        texts.addAll([item.text, item.note]);
      }
  }
  return texts.whereType<String>().toList();
}

String _chapterText(EbookChapter chapter) => [
      chapter.title,
      chapter.learningGoal,
      for (final block in chapter.blocks) ..._blockTexts(block),
    ].join('\n');

/// 觸發安全 callout 要求的關鍵詞。對齊施工規格「涉及邀約、拒絕或升級的章節」。
const _safetyTriggers = <String>[
  '邀約',
  '拒絕',
  '婉拒',
  '棘輪',
  '升級',
  '種子',
  '取消',
];

/// 任何章節都不得出現的字串（來源校正與調性硬規則）。
const _forbiddenPhrases = <String>[
  '十二個案例',
  '五個位置',
  '四大變數',
  '四個變數',
  '假定同意',
  '賦格',
  '失格',
  '得寸進尺',
  '常春藤',
  '完全無法診斷',
  '體脂是最大',
  '幾乎完全可控',
  '固定上限',
  '五到八',
];

/// 出現這些反效果技巧名稱的章節，必須同時有 warning 或 safety callout，
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

  test('每章至少一張翻卡、一題 Quiz、一段對話，並標註來源', () {
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        final where = '${book.id}/${chapter.id}';
        expect(chapter.flipCards, isNotEmpty, reason: '$where 缺翻卡');
        expect(chapter.quizzes, isNotEmpty, reason: '$where 缺 Quiz');
        expect(chapter.dialogues, isNotEmpty, reason: '$where 缺對話');
        expect(chapter.sourceRefs, isNotEmpty, reason: '$where 缺 sourceRefs');
        expect(chapter.learningGoal.trim(), isNotEmpty, reason: '$where 缺學習目標');
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

  test('所有區塊 id 與章節 id 全域唯一', () {
    final blockIds = <String>{};
    final chapterIds = <String>{};
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        expect(chapterIds.add(chapter.id), isTrue,
            reason: '章節 id 重複：${chapter.id}');
        for (final block in chapter.blocks) {
          expect(blockIds.add(block.id), isTrue,
              reason: '區塊 id 重複：${block.id}');
        }
      }
    }
  });

  test('Quiz 選項不變量：id 唯一、feedback 非空、正解數合法', () {
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        for (final quiz in chapter.quizzes) {
          final ids = quiz.choices.map((choice) => choice.id).toList();
          expect(ids.toSet(), hasLength(ids.length),
              reason: '${quiz.id} 選項 id 重複');
          expect(quiz.choices.length, greaterThanOrEqualTo(2));
          expect(quiz.revision, greaterThanOrEqualTo(1));
          expect(quiz.takeaway.trim(), isNotEmpty, reason: '${quiz.id} 缺 takeaway');
          for (final choice in quiz.choices) {
            expect(choice.feedback.trim(), isNotEmpty,
                reason: '${quiz.id}/${choice.id} 缺 feedback');
            expect(choice.text.trim(), isNotEmpty);
          }
          switch (quiz.mode) {
            case EbookQuizMode.single:
              expect(quiz.correctChoiceIds, hasLength(1),
                  reason: '${quiz.id} 單選題正解數不是 1');
            case EbookQuizMode.multiple:
              expect(quiz.correctChoiceIds.length, greaterThanOrEqualTo(1),
                  reason: '${quiz.id} 複選題沒有正解');
              expect(quiz.correctChoiceIds.length,
                  lessThan(quiz.choices.length),
                  reason: '${quiz.id} 複選題全部都是正解');
          }
        }
      }
    }
  });

  test('Checklist 只保存 id 與勾選狀態所需的最小資料', () {
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        for (final checklist in chapter.checklists) {
          expect(checklist.items, isNotEmpty);
          final ids = checklist.items.map((item) => item.id).toList();
          expect(ids.toSet(), hasLength(ids.length),
              reason: '${checklist.id} 項目 id 重複');
        }
      }
    }
  });

  test('涉及邀約／拒絕／升級的章節必須有安全 callout', () {
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        final text = _chapterText(chapter);
        final triggers =
            _safetyTriggers.where((trigger) => text.contains(trigger)).toList();
        if (triggers.isEmpty) continue;
        expect(
          chapter.hasSafetyCallout,
          isTrue,
          reason: '${book.id}/${chapter.id} 命中 $triggers 卻沒有安全 callout',
        );
      }
    }
  });

  test('反效果技巧只出現在警告框架裡', () {
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        final text = _chapterText(chapter);
        final hits =
            _manipulationTerms.where((term) => text.contains(term)).toList();
        if (hits.isEmpty) continue;
        final hasWarningFrame = chapter.blocks.any(
          (block) =>
              block is EbookCalloutBlock &&
              (block.tone == EbookCalloutTone.warning ||
                  block.tone == EbookCalloutTone.safety),
        );
        expect(
          hasWarningFrame,
          isTrue,
          reason: '${book.id}/${chapter.id} 提到 $hits 卻沒有 warning/safety 框架',
        );
      }
    }
  });

  test('來源校正與調性禁語不得回歸', () {
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        final text = _chapterText(chapter);
        for (final phrase in _forbiddenPhrases) {
          expect(
            text.contains(phrase),
            isFalse,
            reason: '${book.id}/${chapter.id} 出現禁語「$phrase」',
          );
        }
      }
    }
  });

  test('五標記與三燈用語一致', () {
    final markerBook = catalog.findBook('ebook-2-conversation');
    expect(markerBook, isNotNull);
    final markerText = markerBook!.chapters.map(_chapterText).join('\n');
    for (final marker in ['V 價值', 'F 框架', 'E 情緒', 'I 投資', 'R 互惠']) {
      expect(markerText.contains(marker), isTrue, reason: '缺少標記說明：$marker');
    }
    for (final light in ['綠燈', '黃燈', '紅燈']) {
      expect(markerText.contains(light), isTrue, reason: '缺少燈號說明：$light');
    }
  });

  test('案例數校正為十四個', () {
    final rescue = catalog.findBook('ebook-3-rescue');
    expect(rescue, isNotNull);
    final text = rescue!.chapters.map(_chapterText).join('\n');
    expect(text.contains('十四個案例'), isTrue);
  });

  test('照片位數校正為六個功能位', () {
    final bottleneck = catalog.findBook('ebook-1-bottleneck');
    expect(bottleneck, isNotNull);
    final text = bottleneck!.chapters.map(_chapterText).join('\n');
    expect(text.contains('六個功能位'), isTrue);
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

  test('Book 1 結尾提供「應讀哪一本」導覽', () {
    final bottleneck = catalog.findBook('ebook-1-bottleneck')!;
    final text = bottleneck.chapters.first.blocks
        .whereType<EbookBulletListBlock>()
        .expand((block) => block.items)
        .join('\n');
    for (final title in const ['看懂一段對話', '對話急救室', '從聊天走到見面']) {
      expect(text.contains(title), isTrue, reason: '診斷導覽缺少《$title》');
    }
  });

  test('Book 4 收錄安全、同意與個資提醒', () {
    final meeting = catalog.findBook('ebook-4-meeting')!;
    final safetyText = meeting.chapters
        .expand((chapter) => chapter.blocks)
        .whereType<EbookCalloutBlock>()
        .where((block) => block.tone == EbookCalloutTone.safety)
        .map((block) => '${block.title ?? ''}\n${block.text}')
        .join('\n');

    for (final requirement in const [
      '公開場所',
      '交通',
      '朋友',
      '不推定',
      '明確',
      '沉默',
      '個資',
      '詐騙',
    ]) {
      expect(
        safetyText.contains(requirement),
        isTrue,
        reason: 'Book 4 的安全 callout 缺少「$requirement」相關內容',
      );
    }
  });

  test('每本書都有 checklist 或明確的自評工具（Book 1 與 Book 4）', () {
    for (final bookId in const ['ebook-1-bottleneck', 'ebook-4-meeting']) {
      final book = catalog.findBook(bookId)!;
      final checklists = book.chapters.expand((c) => c.checklists);
      expect(checklists, isNotEmpty, reason: '$bookId 缺 checklist');
    }
  });
}
