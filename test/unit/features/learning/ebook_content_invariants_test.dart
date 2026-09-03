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
import 'dart:convert';
import 'dart:io';

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

/// 原課本的指涉寫法：頁碼、節號、階段編號、類型 A／B、⚠ 6.x、DHV。
/// App 裡沒有這些座標，讀者看到等於死巷；工作包 2（2026-09-03）起一律改成
/// 冊章（「第 2 冊 2.4」）或前往按鈕。
///
/// 單一來源：直接讀 tools/content/audit_rules.json 的 textbookRefs（R11），
/// 不在這裡手抄一份，兩邊才不會漂移。這幾條用到的 \s、\d、lookahead 在
/// Python 與 Dart 的 regex 語法相同。
final _textbookRefPatterns = _loadTextbookRefPatterns();

List<RegExp> _loadTextbookRefPatterns() {
  final patterns = _ruleStrings('textbookRefs').map(RegExp.new);
  return List.unmodifiable(patterns);
}

/// tools/content/audit_rules.json 是內容規則的單一來源（R10–R13 也讀它）。
Map<String, dynamic> _readAuditRules() => jsonDecode(
      File('tools/content/audit_rules.json').readAsStringSync(),
    ) as Map<String, dynamic>;

List<String> _ruleStrings(String key) =>
    (_readAuditRules()[key] as List<dynamic>).cast<String>();

/// 定稿句與禁用詞比對時忽略空白，跟 audit 的 key 折疊一致。
String _squash(String text) => text.replaceAll(RegExp(r'\s+'), '');

String _catalogText(EbookCatalog catalog) => catalog.books
    .expand((book) => book.chapters)
    .map(_chapterText)
    .join('\n');

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
        expect(chapter.estimatedMinutes, greaterThan(0),
            reason: '$where 缺閱讀時間');
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
            expect(text.trim(), isNotEmpty, reason: '${block.id} 有空字串');
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

  // 原文到處寫「見案例 K」「課本 6.1」「階段 2.6」「類型 A」，但案例庫在第 2 本、
  // 警告區在第 3 本，App 裡也沒有「階段 2.6」這種座標；沒有按鈕時那行字等於
  // 死巷。工作包 2 把它們全部改成冊章或前往按鈕，這裡守住不再長回來；
  // 按鈕的目標是否存在由下一條測試守。
  test('內文不得再有 App 內無法理解的原課本指涉', () {
    // 規則檔讀不到或清單空掉時要紅，不能空轉變綠。
    expect(_textbookRefPatterns.length, greaterThanOrEqualTo(8));
    final hits = <String>[];
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        for (final block in _flatten(chapter.blocks)) {
          for (final text in _blockTexts(block)) {
            for (final pattern in _textbookRefPatterns) {
              final match = pattern.firstMatch(text);
              if (match != null) {
                hits.add('${book.id}/${chapter.id}/${block.id}：${match[0]}');
              }
            }
          }
        }
      }
    }
    expect(hits, isEmpty, reason: '這些原課本指涉在 App 裡無法理解：$hits');
  });

  test('清單與條目不再用「｜」模擬表格欄位', () {
    // 原課本的表格轉成手機內容時，欄位分隔符「｜」被原樣留在字串裡；
    // 工作包 2 把它們改成 bulletList、comparison 或 checklist。
    final hits = <String>[];
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        for (final block in _flatten(chapter.blocks)) {
          for (final text in _blockTexts(block)) {
            if (text.contains('｜')) hits.add('${block.id}：$text');
          }
        }
      }
    }
    expect(hits, isEmpty, reason: '這些欄位還在用「｜」分隔：$hits');
  });

  test('畢業標準一律是 goal callout，標題就叫「畢業標準」', () {
    var count = 0;
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        for (final block in _flatten(chapter.blocks)) {
          if (block is! EbookCalloutBlock) continue;
          final isGraduation = RegExp(r'-grad\d+$').hasMatch(block.id) ||
              (block.title ?? '').contains('畢業標準') ||
              block.text.startsWith('畢業標準');
          if (!isGraduation) continue;
          count++;
          expect(block.tone, EbookCalloutTone.goal,
              reason: '${block.id} 不是 goal');
          expect(block.title, '畢業標準', reason: '${block.id} 標題不對');
          expect(block.text.startsWith('畢業標準'), isFalse,
              reason: '${block.id} 內文重複了「畢業標準：」前綴');
        }
      }
    }
    // 第 1 冊 1.3、1.4，第 2 冊 2.4，第 4 冊 4.3、4.5（2026-09-03 工作包 2）。
    expect(count, 5);
  });

  test('第 3 冊 3.1 診斷樹五層一眼可見：第一層是警告，其餘四層緊接成編號清單', () {
    final chapter = catalog.findChapter('ebook-3-rescue', 'ebook-3-chapter-1')!;
    final blocks = chapter.blocks;
    final firstIndex = blocks.indexWhere(
      (block) =>
          block is EbookCalloutBlock && (block.title ?? '').startsWith('第一層'),
    );
    expect(firstIndex, greaterThanOrEqualTo(0), reason: '找不到第一層');
    expect(
      (blocks[firstIndex] as EbookCalloutBlock).tone,
      EbookCalloutTone.warning,
    );
    final next = blocks[firstIndex + 1];
    expect(next, isA<EbookBulletListBlock>(), reason: '四層清單要緊接在第一層之後');
    final layers = next as EbookBulletListBlock;
    expect(layers.ordered, isTrue);
    expect(
      layers.items.map((item) => item.substring(0, 3)).toList(),
      ['第二層', '第三層', '第四層', '第五層'],
    );
  });

  test('paragraph、caption、annotation 不再一個欄位塞好幾段', () {
    // 原文一段落裡用空行隔出兩三段，手機上讀起來是一面牆；工作包 3
    // （2026-09-03）把它們拆成獨立區塊，這裡守住不再長回來。
    final hits = <String>[];
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        for (final block in _flatten(chapter.blocks)) {
          final List<String?> texts = switch (block) {
            EbookParagraphBlock(:final text) => [text],
            EbookComparisonBlock(:final caption) => [caption],
            EbookDialogueBlock(:final caption, :final lines) => [
                caption,
                for (final line in lines) line.annotation,
              ],
            EbookEntryListBlock(:final caption) => [caption],
            EbookChecklistBlock(:final caption) => [caption],
            _ => const <String?>[],
          };
          for (final text in texts.whereType<String>()) {
            if (text.contains('\n\n')) hits.add(block.id);
          }
        }
      }
    }
    expect(hits, isEmpty, reason: '這些欄位還塞著多段：$hits');
  });

  test('第 5 冊 5.6 切成「先辨認互動感受」「再選擇回應方式」兩段', () {
    final chapter = catalog.findChapter('ebook-5-core', 'ebook-5-chapter-6')!;
    final headings = chapter.blocks
        .whereType<EbookHeadingBlock>()
        .map((heading) => heading.text)
        .toList();
    expect(headings, ['先辨認互動感受', '再選擇回應方式']);
  });

  test('第 4 冊 4.5 十二週計畫有四段週次標題與三張可勾自評', () {
    final chapter =
        catalog.findChapter('ebook-4-meeting', 'ebook-4-chapter-5')!;
    final weekHeadings = chapter.blocks
        .whereType<EbookHeadingBlock>()
        .map((heading) => heading.text)
        .where((text) => text.startsWith('第') && text.contains('週'))
        .toList();
    expect(weekHeadings, hasLength(4), reason: '週次標題：$weekHeadings');
    expect(chapter.blocks.whereType<EbookChecklistBlock>(), hasLength(3));
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
    // 這批按鈕至少全部在（2026-07-27 是 8 顆；2026-09-03 工作包 2 後是 21 顆）。
    expect(count, greaterThanOrEqualTo(21));
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

  test('來源校正：六個功能位與五個變數的 glossary 名稱', () {
    final bottleneck = catalog.findBook('ebook-1-bottleneck')!;
    expect(
      bottleneck.chapters.map(_chapterText).join('\n').contains('六個功能位'),
      isTrue,
    );
    // 第 2 冊 2.1 五個變數的名稱以 audit_rules.json 的 glossary.required 為準
    // （R10；工作包 4 起「R」是「興趣回應」，不再是「互惠」）。
    final glossary = _readAuditRules()['glossary'] as Map<String, dynamic>;
    final chapter = catalog.findChapter(
      glossary['bookId'] as String,
      glossary['chapterId'] as String,
    )!;
    final text = _chapterText(chapter);
    for (final name in (glossary['required'] as List<dynamic>).cast<String>()) {
      expect(text.contains(name), isTrue, reason: '缺少變數名稱：$name');
    }
  });

  // 規格 §5 的十一條定稿句是整套教材的 canonical rule（工作包 4，2026-09-03）。
  // 單一來源：audit_rules.json 的 canonicalRequired（R13）；這裡守「還在」。
  test('P0 定稿句每一句都還在教材裡', () {
    final text = _squash(_catalogText(catalog));
    for (final sentence in _ruleStrings('canonicalRequired')) {
      expect(text.contains(_squash(sentence)), isTrue,
          reason: '找不到定稿句：$sentence');
    }
  });

  // 舊的矛盾句（行為＞情緒＞字面、拒絕階梯、假定同意、她冷的不是你……）
  // 由 audit_rules.json 的 bannedPhrases（R12）列出；一句都不能再長回來。
  test('禁用詞一句都不能再出現', () {
    final phrases = _ruleStrings('bannedPhrases').map(_squash).toList();
    final hits = <String>[];
    for (final book in catalog.books) {
      for (final chapter in book.chapters) {
        final texts = [
          chapter.title,
          chapter.learningGoal,
          for (final block in _flatten(chapter.blocks)) ..._blockTexts(block),
        ];
        for (final text in texts) {
          final squashed = _squash(text);
          for (final phrase in phrases) {
            if (squashed.contains(phrase)) hits.add('${chapter.id}：$phrase');
          }
        }
      }
    }
    expect(hits, isEmpty, reason: '這些禁用詞還在：$hits');
  });

  test('第 1 冊不得提前使用第 2 冊才定義的變數代碼', () {
    // V↑／E↑／F↑／I↑／R↑ 這套標記在第 2 冊 2.1 才教；免費讀者先讀第 1 冊，
    // 看到代碼等於沒看懂。工作包 5（2026-09-03）把 1.5 的 caption 改成中文判讀。
    // 單一來源：audit_rules.json 的 undefinedCodes（R09）。
    final rule = _readAuditRules()['undefinedCodes'] as Map<String, dynamic>;
    final code = RegExp(rule['pattern'] as String);
    final book = catalog.findBook(rule['bookId'] as String)!;
    final hits = <String>[];
    for (final chapter in book.chapters) {
      for (final block in _flatten(chapter.blocks)) {
        for (final text in _blockTexts(block)) {
          if (code.hasMatch(text)) hits.add('${block.id}：${code.firstMatch(text)![0]}');
        }
      }
    }
    expect(hits, isEmpty, reason: '第 1 冊還有未定義的代碼：$hits');
  });

  test('第 4、7 冊用同一句定義種子', () {
    // 規格 §5.4／§12.3 第 10 條：兩冊的邀約流程要能用同一條說明。
    const seed = '種子是先提一個具體活動，暫時不定時間，看看她想不想接';
    for (final bookId in const ['ebook-4-meeting', 'ebook-7-chat']) {
      final book = catalog.findBook(bookId)!;
      expect(
        book.chapters.map(_chapterText).join('\n').contains(seed),
        isTrue,
        reason: '$bookId 沒有種子定稿句',
      );
    }
  });

  test('單元構成：終極指引四本各五章，成為獎賞第一冊七章', () {
    final guide = catalog.books
        .where((book) => book.unit == EbookUnit.ultimateGuide)
        .toList();
    final prize = catalog.books
        .where((book) => book.unit == EbookUnit.becomeThePrize)
        .toList();

    expect(guide, hasLength(4));
    for (final book in guide) {
      expect(book.chapters, hasLength(5), reason: '${book.id} 章數不是 5');
    }

    // 成為獎賞三冊全數上線（2026-07-30），寫死目前狀態，加冊時更新。
    expect(
      prize.map((book) => book.id),
      ['ebook-5-core', 'ebook-6-frames', 'ebook-7-chat'],
    );
    expect(prize[0].chapters, hasLength(7));
    expect(prize[1].chapters, hasLength(6));
    expect(prize[2].chapters, hasLength(6));
  });

  test('權限分界：Book 1 免費，Books 2–4 訂閱，成為獎賞全 Essential', () {
    expect(catalog.books.first.id, 'ebook-1-bottleneck');
    expect(catalog.books.first.access, EbookAccess.free);
    for (final book in catalog.books.skip(1)) {
      expect(
        book.access,
        book.unit == EbookUnit.becomeThePrize
            ? EbookAccess.essential
            : EbookAccess.premium,
        reason: '${book.id} 權限級別不對',
      );
    }
  });

  test('免費閱讀範圍＝第一冊全部＋第二冊第一章', () {
    // 2026-07-27 夥伴回饋（Eric 轉達）。第 3、4 本一章都不開；
    // 成為獎賞（Essential 專屬）也一章都不試讀（2026-07-30 拍板）。
    final books = catalog.books;
    expect(books[0].freePreviewChapterCount, books[0].chapterCount);
    expect(books[1].freePreviewChapterCount, 1);
    expect(books[1].previewChapterId, books[1].chapters.first.id);
    for (final book in books.skip(2)) {
      expect(book.freePreviewChapterCount, 0, reason: '${book.id} 不該有試讀章');
      expect(book.previewChapterId, isNull, reason: '${book.id} 不該有試讀章');
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
