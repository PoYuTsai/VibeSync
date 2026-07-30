// test/unit/features/learning/ebook_essential_unit_test.dart
//
// 「成為獎賞：魅力進階課」單元的付費邊界。
//
// 這一支守的是一個很容易破、而且破了不會有任何錯誤訊息的洞：
// `SubscriptionState.isPremium` 是 `isStarter || isEssential`，所以任何
// 「照抄 isPremium」的判斷都會讓 Starter 使用者讀到 Essential 專屬單元。
// 2026-07-30 Eric 拍板這個單元只給 Essential、且一章都不試讀。
//
// 另一半守的是 catalog 驗證：舊規則是 `index == 0 ? free : premium`，
// 用「全域位置」決定權限。第二個單元一出現，它的第一本就會被要求是免費書
// ——付費牆直接破洞，而且是在內容檔而不是程式碼裡破。
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_catalog_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';

import '../../../helpers/ebook_test_content.dart';

/// 只帶必要欄位的書 JSON。
Map<String, Object?> _book({
  required String id,
  required int number,
  required String unit,
  required String access,
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'id': id,
    'contentVersion': 1,
    'number': number,
    'unit': unit,
    'title': '書名',
    'subtitle': '副標',
    'goal': '目標。',
    'access': access,
    'theme': 'compass',
    'estimatedMinutes': 30,
    'sourceRefs': [
      {
        'document': 'src',
        'sections': ['第一節'],
      },
    ],
    'chapters': [
      <String, Object?>{
        'id': '$id-chapter-1',
        'number': '$number.1',
        'title': '章名',
        'learningGoal': '一個問題。',
        'estimatedMinutes': 5,
        'sourceRefs': [
          {
            'document': 'src',
            'sections': ['第一節'],
          },
        ],
        'blocks': [
          {'type': 'paragraph', 'id': '$id-c1-b1', 'text': '段落。'},
        ],
      },
    ],
  };
}

/// 以記憶體資產載入一組書，回傳 catalog 或讓 EbookContentException 冒出來。
Future<EbookCatalog> _load(List<Map<String, Object?>> books) {
  final entries = <String, String>{};
  final paths = <String>[];
  for (var i = 0; i < books.length; i++) {
    final path = 'memory/book_$i.json';
    paths.add(path);
    entries[path] = jsonEncode(books[i]);
  }
  return EbookCatalogRepository(
    bundle: _MemoryBundle(entries),
    assetPaths: paths,
  ).load();
}

class _MemoryBundle extends CachingAssetBundle {
  _MemoryBundle(this.entries);

  final Map<String, String> entries;

  @override
  Future<ByteData> load(String key) async {
    final value = entries[key];
    if (value == null) throw StateError('missing asset $key');
    final bytes = utf8.encode(value);
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final value = entries[key];
    if (value == null) throw StateError('missing asset $key');
    return value;
  }
}

void main() {
  final essentialBook = buildTestEbook(
    id: 'prize-1',
    number: 1,
    unit: EbookUnit.becomeThePrize,
    access: EbookAccess.essential,
    chapterCount: 3,
  );
  final premiumBook = buildTestEbook(
    id: 'guide-2',
    number: 2,
    access: EbookAccess.premium,
    chapterCount: 3,
  );

  group('Essential 專屬單元的權限判斷', () {
    // 這是整支測試最重要的一條。
    test('Starter 讀不到 Essential 專屬單元', () {
      const starter = EbookSubscriptionAccess(
        isPremium: true,
        isEssential: false,
        isResolving: false,
        hasError: false,
        hasUnexpiredPaidEntitlement: true,
      );

      expect(
        ebookAccessFor(essentialBook, starter),
        EbookAccessDecision.locked,
        reason: 'isPremium 對 Starter 也是 true；照抄它就會讓 Starter 讀到整個單元',
      );
      // 對照組：同一個 Starter 讀得到終極指引的付費書。
      expect(
        ebookAccessFor(premiumBook, starter),
        EbookAccessDecision.allowed,
      );
    });

    test('Essential 讀得到', () {
      expect(
        ebookAccessFor(essentialBook, const EbookSubscriptionAccess.essential()),
        EbookAccessDecision.allowed,
      );
    });

    test('免費使用者讀不到', () {
      expect(
        ebookAccessFor(essentialBook, const EbookSubscriptionAccess.free()),
        EbookAccessDecision.locked,
      );
    });

    test('訂閱狀態未確認時不下結論，不會誤判成可讀', () {
      expect(
        ebookAccessFor(
          essentialBook,
          const EbookSubscriptionAccess.resolving(),
        ),
        EbookAccessDecision.resolving,
      );
      expect(
        ebookAccessFor(
          essentialBook,
          const EbookSubscriptionAccess.unavailable(),
        ),
        EbookAccessDecision.unavailable,
      );
    });

    test('離線快取顯示 Starter 時，仍然讀不到 Essential 單元', () {
      const cachedStarter = EbookSubscriptionAccess.cachedPremium();
      expect(
        ebookAccessFor(essentialBook, cachedStarter),
        EbookAccessDecision.resolving,
        reason: '不放行，但也不當成免費使用者',
      );
      expect(
        ebookAccessFor(
          essentialBook,
          const EbookSubscriptionAccess.cachedPremium(essential: true),
        ),
        EbookAccessDecision.allowed,
      );
    });
  });

  group('Essential 單元一章都不試讀', () {
    test('freePreviewChapterCount 為 0', () {
      expect(essentialBook.freePreviewChapterCount, 0);
      expect(essentialBook.previewChapterId, isNull);
      expect(essentialBook.isPreviewChapter('prize-1-chapter-1'), isFalse);
    });

    test('章節層判斷不會把第一章降級成試讀', () {
      expect(
        ebookChapterAccessFor(
          essentialBook,
          'prize-1-chapter-1',
          const EbookSubscriptionAccess.free(),
        ),
        EbookAccessDecision.locked,
      );
    });

    test('對照：終極指引第 2 本仍然開第一章試讀（沒有被順手改掉）', () {
      expect(premiumBook.freePreviewChapterCount, 1);
      expect(
        ebookChapterAccessFor(
          premiumBook,
          'guide-2-chapter-1',
          const EbookSubscriptionAccess.free(),
        ),
        EbookAccessDecision.preview,
      );
    });
  });

  group('catalog 權限拍板', () {
    test('兩個單元併存時載入成功，書號在單元內各自從 1 開始', () async {
      final catalog = await _load([
        _book(id: 'g1', number: 1, unit: 'ultimateGuide', access: 'free'),
        _book(id: 'g2', number: 2, unit: 'ultimateGuide', access: 'premium'),
        _book(id: 'p1', number: 1, unit: 'becomeThePrize', access: 'essential'),
        _book(id: 'p2', number: 2, unit: 'becomeThePrize', access: 'essential'),
      ]);

      expect(catalog.books, hasLength(4));
      final sections = catalog.unitSections;
      expect(sections, hasLength(2));
      expect(sections[0].unit, EbookUnit.ultimateGuide);
      expect(sections[0].books.map((b) => b.number), [1, 2]);
      expect(sections[1].unit, EbookUnit.becomeThePrize);
      expect(sections[1].books.map((b) => b.number), [1, 2]);
    });

    test('成為獎賞的書寫成 premium 會被擋下', () {
      expect(
        () => _load([
          _book(id: 'g1', number: 1, unit: 'ultimateGuide', access: 'free'),
          _book(id: 'p1', number: 1, unit: 'becomeThePrize', access: 'premium'),
        ]),
        throwsA(
          isA<EbookContentException>().having(
            (e) => e.message,
            'message',
            contains('違反權限拍板'),
          ),
        ),
      );
    });

    test('成為獎賞的第一本寫成 free 會被擋下——舊的位置規則擋不住這個', () {
      expect(
        () => _load([
          _book(id: 'g1', number: 1, unit: 'ultimateGuide', access: 'free'),
          _book(id: 'p1', number: 1, unit: 'becomeThePrize', access: 'free'),
        ]),
        throwsA(isA<EbookContentException>()),
      );
    });

    test('終極指引第一本仍然必須免費', () {
      expect(
        () => _load([
          _book(id: 'g1', number: 1, unit: 'ultimateGuide', access: 'premium'),
        ]),
        throwsA(
          isA<EbookContentException>().having(
            (e) => e.message,
            'message',
            contains('違反權限拍板'),
          ),
        ),
      );
    });

    test('書號跳號會被擋下（單元內必須連號）', () {
      expect(
        () => _load([
          _book(id: 'g1', number: 1, unit: 'ultimateGuide', access: 'free'),
          _book(id: 'p1', number: 3, unit: 'becomeThePrize', access: 'essential'),
        ]),
        throwsA(
          isA<EbookContentException>().having(
            (e) => e.message,
            'message',
            contains('不一致'),
          ),
        ),
      );
    });

    test('同一單元被切成兩段會被擋下（否則書架分組會裂開）', () {
      expect(
        () => _load([
          _book(id: 'g1', number: 1, unit: 'ultimateGuide', access: 'free'),
          _book(id: 'p1', number: 1, unit: 'becomeThePrize', access: 'essential'),
          _book(id: 'g2', number: 2, unit: 'ultimateGuide', access: 'premium'),
        ]),
        throwsA(
          isA<EbookContentException>().having(
            (e) => e.message,
            'message',
            contains('必須連續排列'),
          ),
        ),
      );
    });

    test('未知的 unit 值會被擋下，不會靜默當成終極指引', () {
      expect(
        () => _load([
          _book(id: 'g1', number: 1, unit: 'somethingElse', access: 'free'),
        ]),
        throwsA(isA<EbookContentException>()),
      );
    });
  });

  group('production 資產', () {
    test('終極指引四冊之外，成為獎賞三冊已上線且為 Essential 專屬', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final catalog = await EbookCatalogRepository().load();
      expect(catalog.unitSections, hasLength(2));
      expect(
        catalog.unitSections[0].books
            .every((b) => b.unit == EbookUnit.ultimateGuide),
        isTrue,
      );
      final prize = catalog.unitSections[1].books;
      expect(
        prize.map((b) => b.id),
        ['ebook-5-core', 'ebook-6-frames', 'ebook-7-chat'],
      );
      expect(prize.every((b) => b.isEssentialOnly), isTrue);
      expect(prize.every((b) => b.freePreviewChapterCount == 0), isTrue);
    });
  });
}
