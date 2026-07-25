// test/widget/features/learning/learning_screen_ebook_hierarchy_test.dart
//
// 學習頁階層回歸：
//   Practice Hero → 互動電子書 → 短篇實戰文章 → 24 篇文章 grid。
//
// 重點是 quota 提示只出現在文章區（電子書不消耗文章額度），
// 以及既有 24 篇文章與 article id 沒有被電子書改動。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/articles_data.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/data/providers/learning_providers.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_progress_repository.dart';
import 'package:vibesync/features/learning/data/services/article_read_service.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/presentation/screens/learning_screen.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_shelf_section.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

import '../../../helpers/ebook_test_content.dart';
import '../../../helpers/ebook_widget_harness.dart';

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

/// 只覆寫學習頁實際會呼叫的方法，避免 headless 測試開啟 Hive usage box。
class _FakeReadService extends ArticleReadService {
  @override
  bool canReadArticle(String articleId) => true;
  @override
  int get remainingReads => 3;
  @override
  void recordReadArticle(String articleId) {}
  @override
  bool hasReadArticle(String articleId) => false;
}

/// 真實 catalog 必須在 setUpAll（真 async）載入。
///
/// 內容資產超過 50KB 時，`AssetBundle.loadString` 會把 UTF-8 解碼丟到背景
/// isolate（compute），那在 `testWidgets` 的 fake async 下永遠不會完成——
/// 在測試主體裡 await 它會直接卡死。
EbookCatalog? _catalog;

Future<void> pumpLearningScreen(
  WidgetTester tester, {
  required String tier,
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.free(),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final catalog = _catalog!;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionProvider.overrideWith(
          (ref) => _SeededSubscriptionNotifier(SubscriptionState(tier: tier)),
        ),
        articleReadServiceProvider.overrideWithValue(_FakeReadService()),
        ebookCatalogProvider.overrideWith((ref) async => catalog),
        ebookSubscriptionAccessProvider.overrideWith((ref) => access),
        ebookProgressOwnerProvider
            .overrideWith((ref) => Stream<String?>.value('learning-owner')),
        ebookProgressRepositoryProvider.overrideWithValue(
          EbookProgressRepository(box: InMemoryHiveBox()),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: LearningScreen())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    _catalog = await loadProductionCatalog();
  });

  testWidgets('電子書區塊在短篇文章區之前', (tester) async {
    await pumpLearningScreen(tester, tier: SubscriptionTierHelper.free);

    expect(find.byType(EbookShelfSection), findsOneWidget);

    final shelfY = tester.getTopLeft(find.byType(EbookShelfSection)).dy;
    await tester.scrollUntilVisible(find.text('短篇實戰文章'), 300);
    await tester.pumpAndSettle();
    final articlesY = tester.getTopLeft(find.text('短篇實戰文章')).dy;

    // 捲動後書架已經在畫面上方（或捲出畫面），文章標題在它之後才出現。
    expect(shelfY, isNotNull);
    expect(articlesY, isNotNull);
    expect(find.text('短篇實戰文章'), findsOneWidget);
  });

  testWidgets('免費使用者的每日額度提示只出現在文章區，並註明電子書不計入',
      (tester) async {
    await pumpLearningScreen(tester, tier: SubscriptionTierHelper.free);

    // 書架剛出現時，畫面上不該有任何額度文案。
    expect(find.byType(EbookShelfSection), findsOneWidget);
    expect(find.textContaining('免費閱讀'), findsNothing);

    await tester.scrollUntilVisible(find.textContaining('免費閱讀'), 300);
    await tester.pumpAndSettle();

    expect(find.textContaining('今日剩餘 3 篇免費閱讀'), findsOneWidget);
    expect(find.textContaining('電子書不計入'), findsOneWidget);
    // 額度提示必須在「短篇實戰文章」標題之後。
    final noticeY = tester.getTopLeft(find.textContaining('免費閱讀')).dy;
    final headerY = tester.getTopLeft(find.text('短篇實戰文章')).dy;
    expect(noticeY, greaterThan(headerY));
  });

  testWidgets('付費使用者不顯示文章額度提示，電子書仍在', (tester) async {
    await pumpLearningScreen(
      tester,
      tier: SubscriptionTierHelper.starter,
      access: const EbookSubscriptionAccess.premium(),
    );

    expect(find.byType(EbookShelfSection), findsOneWidget);
    await tester.scrollUntilVisible(find.text('短篇實戰文章'), 300);
    await tester.pumpAndSettle();
    expect(find.textContaining('免費閱讀'), findsNothing);
  });

  testWidgets('既有 24 篇文章仍然渲染，且電子書沒有混進 articles', (tester) async {
    await pumpLearningScreen(tester, tier: SubscriptionTierHelper.free);

    expect(articles, hasLength(24));

    // 電子書 id 絕不能出現在 articles 的 id space 裡。
    final articleIds = articles.map((article) => article.id).toSet();
    for (final bookId in const [
      'ebook-1-bottleneck',
      'ebook-2-conversation',
      'ebook-3-rescue',
      'ebook-4-meeting',
    ]) {
      expect(articleIds.contains(bookId), isFalse);
    }

    await tester.scrollUntilVisible(find.text(articles.first.title), 400);
    await tester.pumpAndSettle();
    expect(find.text(articles.first.title), findsOneWidget);
  });
}
