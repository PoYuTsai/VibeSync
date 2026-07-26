// test/unit/features/learning/ebook_catalog_test.dart
//
// Catalog 與 JSON parser 的行為測試。重點是 fail closed：未知 block type、
// 缺欄位、單選題正解數不對、id 重複、access 違反權限拍板都必須拋錯，
// 而不是靜默跳過造成「看起來讀完了但少一個互動」。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_catalog_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';

import '../../../helpers/ebook_test_content.dart';

Map<String, Object?> _minimalBook({
  required String id,
  required int number,
  String access = 'free',
  List<Map<String, Object?>>? extraBlocks,
  List<Map<String, Object?>>? chapters,
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'id': id,
    'contentVersion': 1,
    'number': number,
    'title': '書名',
    'subtitle': '副標',
    'goal': '目標。',
    'access': access,
    'theme': 'compass',
    'estimatedMinutes': 30,
    'sourceRefs': [
      {'document': 'five-stage-course', 'sections': ['第一節']},
    ],
    'chapters': chapters ??
        [
          <String, Object?>{
            'id': '$id-chapter-1',
            'number': '$number.1',
            'title': '章名',
            'learningGoal': '這一章只回答一個問題。',
            'estimatedMinutes': 5,
            'sourceRefs': [
              {'document': 'five-stage-course', 'sections': ['第一節']},
            ],
            'blocks': [
              <String, Object?>{
                'type': 'paragraph',
                'id': '$id-c1-p1',
                'text': '段落。',
              },
              ...?extraBlocks,
            ],
          },
        ],
  };
}

Map<String, Object?> _quizBlock({
  String id = 'q1',
  String mode = 'single',
  List<bool> correctness = const [true, false],
  int revision = 1,
}) {
  return <String, Object?>{
    'type': 'quiz',
    'id': id,
    'mode': mode,
    'revision': revision,
    'question': '問題？',
    'takeaway': '帶走一句。',
    'choices': [
      for (var index = 0; index < correctness.length; index++)
        <String, Object?>{
          'id': '$id-c$index',
          'text': '選項 $index',
          'isCorrect': correctness[index],
          'feedback': '回饋 $index',
        },
    ],
  };
}

Ebook _parse(Map<String, Object?> json) =>
    parseBookJson(jsonEncode(json), assetPath: 'test.json');

void main() {
  group('parseBookJson', () {
    test('parses a minimal book with typed blocks', () {
      final book = _parse(_minimalBook(id: 'b1', number: 1));

      expect(book.id, 'b1');
      expect(book.access, EbookAccess.free);
      expect(book.theme, EbookTheme.compass);
      expect(book.chapters, hasLength(1));
      expect(book.chapters.single.blocks.single, isA<EbookParagraphBlock>());
    });

    test('parses every supported block type', () {
      final book = _parse(
        _minimalBook(
          id: 'b1',
          number: 1,
          extraBlocks: [
            {'type': 'heading', 'id': 'h1', 'text': '標題'},
            {
              'type': 'bulletList',
              'id': 'bl1',
              'items': ['一', '二'],
              'ordered': true,
            },
            {
              'type': 'callout',
              'id': 'co1',
              'tone': 'safety',
              'title': '安全',
              'text': '提醒。',
            },
            {
              'type': 'comparison',
              'id': 'cm1',
              'items': [
                {'id': 'cm1-a', 'stance': 'weak', 'label': '弱', 'text': '弱句'},
                {'id': 'cm1-b', 'stance': 'strong', 'label': '強', 'text': '強句'},
              ],
            },
            {
              'type': 'dialogue',
              'id': 'dl1',
              'lines': [
                {
                  'id': 'dl1-l1',
                  'speaker': 'you',
                  'text': '嗨',
                  'annotation': 'I',
                },
                {
                  'id': 'dl1-l2',
                  'speaker': 'other',
                  'text': '對啊',
                  'signal': 'yellow',
                  'isDeathPoint': true,
                },
              ],
            },
            {
              'type': 'flipCard',
              'id': 'fc1',
              'frontTitle': '正面',
              'frontText': '情境',
              'backTitle': '背面',
              'backText': '機制',
              'backPoints': ['重點'],
            },
            _quizBlock(id: 'q1'),
            {
              'type': 'checklist',
              'id': 'cl1',
              'items': [
                {'id': 'cl1-i1', 'text': '項目一'},
              ],
            },
          ],
        ),
      );

      final blocks = book.chapters.single.blocks;
      expect(blocks.whereType<EbookHeadingBlock>(), hasLength(1));
      expect(blocks.whereType<EbookBulletListBlock>().single.ordered, isTrue);
      expect(
        blocks.whereType<EbookCalloutBlock>().single.tone,
        EbookCalloutTone.safety,
      );
      expect(blocks.whereType<EbookComparisonBlock>().single.items, hasLength(2));

      final dialogue = blocks.whereType<EbookDialogueBlock>().single;
      expect(dialogue.lines.first.speaker, EbookSpeaker.you);
      expect(dialogue.lines.last.signal, EbookSignal.yellow);
      expect(dialogue.lines.last.isDeathPoint, isTrue);

      expect(blocks.whereType<EbookFlipCardBlock>().single.backPoints, ['重點']);
      expect(blocks.whereType<EbookChecklistBlock>().single.items, hasLength(1));

      final quiz = blocks.whereType<EbookQuizBlock>().single;
      expect(quiz.mode, EbookQuizMode.single);
      expect(quiz.retryPolicy, EbookQuizRetryPolicy.untilCorrect);
      expect(quiz.correctChoiceIds, ['q1-c0']);
    });

    test('fails closed on an unknown block type', () {
      expect(
        () => _parse(
          _minimalBook(
            id: 'b1',
            number: 1,
            extraBlocks: [
              {'type': 'videoEmbed', 'id': 'v1', 'url': 'https://example.com'},
            ],
          ),
        ),
        throwsA(
          isA<EbookContentException>().having(
            (error) => error.message,
            'message',
            contains('未知的區塊型別'),
          ),
        ),
      );
    });

    test('fails closed on an unknown schema version', () {
      final json = _minimalBook(id: 'b1', number: 1)
        ..['schemaVersion'] = kEbookSchemaVersion + 1;
      expect(
        () => _parse(json),
        throwsA(
          isA<EbookContentException>().having(
            (error) => error.message,
            'message',
            contains('schemaVersion'),
          ),
        ),
      );
    });

    test('rejects malformed JSON', () {
      expect(
        () => parseBookJson('{ not json', assetPath: 'test.json'),
        throwsA(isA<EbookContentException>()),
      );
    });

    test('rejects a missing required field', () {
      final json = _minimalBook(id: 'b1', number: 1)..remove('title');
      expect(() => _parse(json), throwsA(isA<EbookContentException>()));
    });

    test('rejects an empty chapter block list', () {
      final json = _minimalBook(id: 'b1', number: 1);
      (json['chapters']! as List).first as Map<String, Object?>;
      ((json['chapters']! as List).first as Map<String, Object?>)['blocks'] =
          <Object?>[];
      expect(() => _parse(json), throwsA(isA<EbookContentException>()));
    });

    test('single-choice quiz must have exactly one correct answer', () {
      for (final correctness in <List<bool>>[
        [false, false],
        [true, true],
      ]) {
        expect(
          () => _parse(
            _minimalBook(
              id: 'b1',
              number: 1,
              extraBlocks: [_quizBlock(correctness: correctness)],
            ),
          ),
          throwsA(
            isA<EbookContentException>().having(
              (error) => error.message,
              'message',
              contains('單選題'),
            ),
          ),
          reason: '$correctness 應該被擋下',
        );
      }
    });

    test('multiple-choice quiz needs at least one correct and one wrong', () {
      expect(
        () => _parse(
          _minimalBook(
            id: 'b1',
            number: 1,
            extraBlocks: [
              _quizBlock(mode: 'multiple', correctness: [false, false]),
            ],
          ),
        ),
        throwsA(isA<EbookContentException>()),
      );
      expect(
        () => _parse(
          _minimalBook(
            id: 'b1',
            number: 1,
            extraBlocks: [
              _quizBlock(mode: 'multiple', correctness: [true, true]),
            ],
          ),
        ),
        throwsA(isA<EbookContentException>()),
      );
      expect(
        _parse(
          _minimalBook(
            id: 'b1',
            number: 1,
            extraBlocks: [
              _quizBlock(mode: 'multiple', correctness: [true, true, false]),
            ],
          ),
        ).chapters.single.quizzes.single.correctChoiceIds,
        hasLength(2),
      );
    });

    test('rejects duplicate choice ids inside one quiz', () {
      final quiz = _quizBlock();
      final choices = (quiz['choices']! as List).cast<Map<String, Object?>>();
      choices[1]['id'] = choices[0]['id'];
      expect(
        () => _parse(
          _minimalBook(id: 'b1', number: 1, extraBlocks: [quiz]),
        ),
        throwsA(isA<EbookContentException>()),
      );
    });

    test('rejects duplicate block ids inside one chapter', () {
      expect(
        () => _parse(
          _minimalBook(
            id: 'b1',
            number: 1,
            extraBlocks: [
              {'type': 'heading', 'id': 'b1-c1-p1', 'text': '撞號'},
            ],
          ),
        ),
        throwsA(
          isA<EbookContentException>().having(
            (error) => error.message,
            'message',
            contains('區塊 id 重複'),
          ),
        ),
      );
    });

    test('quiz revision must be a positive integer', () {
      expect(
        () => _parse(
          _minimalBook(
            id: 'b1',
            number: 1,
            extraBlocks: [_quizBlock(revision: 0)],
          ),
        ),
        throwsA(isA<EbookContentException>()),
      );
    });

    test('EbookQuizBlock.isSolvedBy needs the exact correct set', () {
      final quiz = _parse(
        _minimalBook(
          id: 'b1',
          number: 1,
          extraBlocks: [
            _quizBlock(mode: 'multiple', correctness: [true, true, false]),
          ],
        ),
      ).chapters.single.quizzes.single;

      expect(quiz.isSolvedBy({'q1-c0', 'q1-c1'}), isTrue);
      expect(quiz.isSolvedBy({'q1-c0'}), isFalse);
      expect(quiz.isSolvedBy({'q1-c0', 'q1-c1', 'q1-c2'}), isFalse);
      expect(quiz.isSolvedBy(const <String>{}), isFalse);
    });
  });

  group('EbookCatalogRepository', () {
    Future<EbookCatalog> loadBooks(List<Map<String, Object?>> books) {
      final paths = <String>[];
      final entries = <String, String>{};
      for (var index = 0; index < books.length; index++) {
        final path = 'memory/book_$index.json';
        paths.add(path);
        entries[path] = jsonEncode(books[index]);
      }
      return EbookCatalogRepository(
        bundle: MapAssetBundle(entries),
        assetPaths: paths,
      ).load();
    }

    test('loads books in asset order and finds by id', () async {
      final catalog = await loadBooks([
        _minimalBook(id: 'b1', number: 1),
        _minimalBook(id: 'b2', number: 2, access: 'premium'),
      ]);

      expect(catalog.books.map((book) => book.id), ['b1', 'b2']);
      expect(catalog.findBook('b2')?.title, '書名');
      expect(catalog.findBook('nope'), isNull);
      expect(catalog.findChapter('b1', 'b1-chapter-1'), isNotNull);
      expect(catalog.findChapter('b1', 'nope'), isNull);
      expect(catalog.findChapter('nope', 'b1-chapter-1'), isNull);
    });

    test('rejects a book whose number does not match asset order', () async {
      expect(
        loadBooks([
          _minimalBook(id: 'b1', number: 1),
          _minimalBook(id: 'b2', number: 3, access: 'premium'),
        ]),
        throwsA(isA<EbookContentException>()),
      );
    });

    test('rejects duplicate book ids', () async {
      expect(
        loadBooks([
          _minimalBook(id: 'same', number: 1),
          _minimalBook(id: 'same', number: 2, access: 'premium'),
        ]),
        throwsA(isA<EbookContentException>()),
      );
    });

    test('rejects globally duplicated block ids across books', () async {
      expect(
        loadBooks([
          _minimalBook(
            id: 'b1',
            number: 1,
            extraBlocks: [
              {'type': 'heading', 'id': 'shared-block', 'text': '一'},
            ],
          ),
          _minimalBook(
            id: 'b2',
            number: 2,
            access: 'premium',
            extraBlocks: [
              {'type': 'heading', 'id': 'shared-block', 'text': '二'},
            ],
          ),
        ]),
        throwsA(
          isA<EbookContentException>().having(
            (error) => error.message,
            'message',
            contains('全域重複'),
          ),
        ),
      );
    });

    test('第一本必須免費，其餘必須訂閱（權限拍板 fail closed）', () async {
      expect(
        loadBooks([_minimalBook(id: 'b1', number: 1, access: 'premium')]),
        throwsA(
          isA<EbookContentException>().having(
            (error) => error.message,
            'message',
            contains('權限拍板'),
          ),
        ),
      );
      expect(
        loadBooks([
          _minimalBook(id: 'b1', number: 1),
          _minimalBook(id: 'b2', number: 2),
        ]),
        throwsA(isA<EbookContentException>()),
      );
    });

    // 交叉指涉大多跨書（案例庫在第 2 本、引用它的問答在第 3 本）。目標若靜默
    // 失效，讀者按到的是一顆什麼都沒發生的按鈕——比沒有按鈕更糟。
    Map<String, Object?> crossRef({
      String bookId = 'b1',
      String chapterId = 'b1-chapter-1',
      String? entryId,
    }) =>
        <String, Object?>{
          'type': 'crossRef',
          'id': 'xref-1',
          'label': '案例 K',
          'contextLabel': '《書名》第 1 章',
          'targetBookId': bookId,
          'targetChapterId': chapterId,
          if (entryId != null) 'targetEntryId': entryId,
        };

    Map<String, Object?> library() => <String, Object?>{
          'type': 'entryList',
          'id': 'b1-lib',
          'entries': [
            for (var i = 1; i <= 2; i++)
              <String, Object?>{
                'id': 'b1-lib-e$i',
                'title': '案例 $i',
                'blocks': [
                  {'type': 'paragraph', 'id': 'b1-lib-e$i-b1', 'text': '內文。'},
                ],
              },
          ],
        };

    test('交叉指涉的目標書必須存在', () async {
      expect(
        loadBooks([
          _minimalBook(id: 'b1', number: 1, extraBlocks: [crossRef(bookId: '不存在的書')]),
        ]),
        throwsA(
          isA<EbookContentException>().having(
            (error) => error.message,
            'message',
            contains('targetBookId'),
          ),
        ),
      );
    });

    test('交叉指涉的目標章必須屬於那本書', () async {
      expect(
        loadBooks([
          _minimalBook(
            id: 'b1',
            number: 1,
            extraBlocks: [crossRef(chapterId: 'b1-chapter-9')],
          ),
        ]),
        throwsA(
          isA<EbookContentException>().having(
            (error) => error.message,
            'message',
            contains('targetChapterId'),
          ),
        ),
      );
    });

    test('交叉指涉的目標條目必須存在', () async {
      expect(
        loadBooks([
          _minimalBook(
            id: 'b1',
            number: 1,
            extraBlocks: [library(), crossRef(entryId: 'b1-lib-e9')],
          ),
        ]),
        throwsA(
          isA<EbookContentException>().having(
            (error) => error.message,
            'message',
            contains('targetEntryId'),
          ),
        ),
      );
    });

    test('交叉指涉的目標條目必須真的在它宣稱的那一章', () async {
      expect(
        loadBooks([
          _minimalBook(id: 'b1', number: 1, extraBlocks: [library()]),
          _minimalBook(
            id: 'b2',
            number: 2,
            access: 'premium',
            extraBlocks: [
              crossRef(
                bookId: 'b2',
                chapterId: 'b2-chapter-1',
                entryId: 'b1-lib-e1',
              ),
            ],
          ),
        ]),
        throwsA(
          isA<EbookContentException>().having(
            (error) => error.message,
            'message',
            contains('不一致'),
          ),
        ),
      );
    });

    test('目標齊全時載入成功，條目 id 一路帶到 model', () async {
      final catalog = await loadBooks([
        _minimalBook(id: 'b1', number: 1, extraBlocks: [library()]),
        _minimalBook(
          id: 'b2',
          number: 2,
          access: 'premium',
          extraBlocks: [
            crossRef(entryId: 'b1-lib-e2'),
          ],
        ),
      ]);

      final block = catalog
          .findChapter('b2', 'b2-chapter-1')!
          .blocks
          .whereType<EbookCrossRefBlock>()
          .single;
      expect(block.targetBookId, 'b1');
      expect(block.targetEntryId, 'b1-lib-e2');
      expect(block.contextLabel, '《書名》第 1 章');
    });

    test('surfaces a readable error when an asset is missing', () async {
      expect(
        EbookCatalogRepository(
          bundle: MapAssetBundle(const {}),
          assetPaths: const ['missing.json'],
        ).load(),
        throwsA(
          isA<EbookContentException>().having(
            (error) => error.message,
            'message',
            contains('無法讀取電子書資產'),
          ),
        ),
      );
    });

    test('production catalog declares exactly four assets', () {
      expect(EbookCatalogRepository.productionAssetPaths, hasLength(4));
      expect(EbookCatalogRepository().assetPaths,
          EbookCatalogRepository.productionAssetPaths);
    });

    test('real bundled assets parse and satisfy catalog invariants', () async {
      final catalog = await loadProductionCatalog();

      expect(catalog.books, hasLength(4));
      expect(catalog.books.first.access, EbookAccess.free);
      expect(
        catalog.books.skip(1).map((book) => book.access),
        everyElement(EbookAccess.premium),
      );
      expect(
        catalog.books.map((book) => book.number),
        [1, 2, 3, 4],
      );
      expect(
        catalog.books.map((book) => book.id).toSet(),
        hasLength(4),
      );
    });
  });
}
