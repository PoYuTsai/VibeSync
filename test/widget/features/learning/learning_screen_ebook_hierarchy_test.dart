// test/widget/features/learning/learning_screen_ebook_hierarchy_test.dart
//
// 學習頁階層回歸：
//   Practice Hero → 聊天測驗 → 互動電子書 → 短篇實戰文章 → 24 篇文章 grid。
//
// 2026-07-31 起測驗插在電子書之前（§11 決定 1）：電子書是讀的，測驗是練的。
//
// 重點是 quota 提示只出現在文章區（電子書不消耗文章額度），
// 以及既有 24 篇文章與 article id 沒有被電子書改動。
//
// 2026-08-09 學習頁減長批：
//   - 書架改單元群組收合。無進度＝展開第一單元；有進度＝全收合＋繼續閱讀卡。
//   - 文章 grid 上方加分類篩選 chips（全部＋4 分類）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/learning/data/articles_data.dart';
import 'package:vibesync/features/learning/data/providers/chat_quiz_providers.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/data/providers/learning_providers.dart';
import 'package:vibesync/features/learning/data/repositories/chat_quiz_progress_repository.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_progress_repository.dart';
import 'package:vibesync/features/learning/data/services/article_read_service.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/presentation/screens/learning_screen.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';
import 'package:vibesync/features/learning/presentation/widgets/chat_quiz_section.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_shelf_section.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

import '../../../helpers/chat_quiz_test_content.dart';
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
ChatQuizCatalog? _quizCatalog;

/// scrollUntilVisible 的明確目標：頁面現在有兩個 Scrollable（外層
/// CustomScrollView＋分類 chips 的水平列），不指定會在 chips 進入 cache
/// extent 後炸 ambiguous。`.first` 依 element 樹序永遠是外層垂直捲動。
final Finder _verticalScrollable = find.byType(Scrollable).first;

Future<void> pumpLearningScreen(
  WidgetTester tester, {
  required String tier,
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.free(),
  Object? quizCatalogError,
  Box? progressBox,
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
        if (quizCatalogError != null)
          chatQuizCatalogProvider
              .overrideWith((ref) async => throw quizCatalogError)
        else
          chatQuizCatalogProvider.overrideWith((ref) async => _quizCatalog!),
        chatQuizProgressOwnerProvider
            .overrideWith((ref) => Stream<String?>.value('learning-owner')),
        chatQuizProgressRepositoryProvider.overrideWithValue(
          ChatQuizProgressRepository(box: InMemoryHiveBox()),
        ),
        ebookSubscriptionAccessProvider.overrideWith((ref) => access),
        ebookProgressOwnerProvider
            .overrideWith((ref) => Stream<String?>.value('learning-owner')),
        ebookProgressRepositoryProvider.overrideWithValue(
          EbookProgressRepository(box: progressBox ?? InMemoryHiveBox()),
        ),
      ],
      // 練習室入口卡已無 LiquidMotionFrame；關動畫讓
      // pumpAndSettle 可收斂。copyWith 保留視窗尺寸給入口卡的
      // MediaQuery.sizeOf fallback。
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: LearningScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    _catalog = await loadProductionCatalog();
    _quizCatalog = await loadProductionChatQuizCatalog();
  });

  testWidgets('三段順序：練習室 → 測驗 → 電子書 → 短篇文章', (tester) async {
    await pumpLearningScreen(tester, tier: SubscriptionTierHelper.free);

    expect(find.byType(ChatQuizSection), findsOneWidget);
    expect(find.byType(EbookShelfSection), findsOneWidget);

    // 測驗與電子書都在首屏之後，兩者的相對位置直接比 y。
    final quizY = tester.getTopLeft(find.byType(ChatQuizSection)).dy;
    final shelfY = tester.getTopLeft(find.byType(EbookShelfSection)).dy;
    expect(quizY, lessThan(shelfY), reason: '聊天測驗必須在電子書之前');

    await tester.scrollUntilVisible(find.text('短篇實戰文章'), 300,
        scrollable: _verticalScrollable);
    await tester.pumpAndSettle();
    expect(find.text('短篇實戰文章'), findsOneWidget);
  });

  testWidgets('測驗區塊只有入口卡，第 2 期的東西都不出現', (tester) async {
    await pumpLearningScreen(tester, tier: SubscriptionTierHelper.free);

    expect(find.text('聊天新手村'), findsOneWidget);
    expect(find.text('全部關卡 →'), findsOneWidget);
    expect(find.text('15 關 · 225 題'), findsOneWidget);

    // 第 2 期才做的東西，第 1 期一個都不畫。
    expect(find.textContaining('今日'), findsNothing);
    expect(find.textContaining('連續'), findsNothing);
    expect(find.textContaining('準確率'), findsNothing);
    expect(find.textContaining('錯題'), findsNothing);
    // 付費入口只在關卡地圖出現一次，學習頁區塊不放。
    expect(find.text('看訂閱方案'), findsNothing);
  });

  testWidgets('測驗內容解析失敗時，電子書與文章列表仍然渲染得出來', (tester) async {
    await pumpLearningScreen(
      tester,
      tier: SubscriptionTierHelper.free,
      quizCatalogError: StateError('quiz boom'),
    );

    expect(find.text('聊天測驗暫時讀不到，其他內容不受影響。'), findsOneWidget);
    expect(find.byType(EbookShelfSection), findsOneWidget);

    await tester.scrollUntilVisible(find.text('短篇實戰文章'), 300,
        scrollable: _verticalScrollable);
    await tester.pumpAndSettle();
    expect(find.text('短篇實戰文章'), findsOneWidget);
  });

  testWidgets('免費使用者的每日額度提示只出現在文章區，並註明電子書不計入', (tester) async {
    await pumpLearningScreen(tester, tier: SubscriptionTierHelper.free);

    // 書架剛出現時，畫面上不該有任何額度文案。
    expect(find.byType(EbookShelfSection), findsOneWidget);
    expect(find.textContaining('免費閱讀'), findsNothing);

    await tester.scrollUntilVisible(find.textContaining('免費閱讀'), 300,
        scrollable: _verticalScrollable);
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
    await tester.scrollUntilVisible(find.text('短篇實戰文章'), 300,
        scrollable: _verticalScrollable);
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

    await tester.scrollUntilVisible(find.text(articles.first.title), 400,
        scrollable: _verticalScrollable);
    await tester.pumpAndSettle();
    expect(find.text(articles.first.title), findsOneWidget);
  });

  testWidgets('書架預設：無進度展開第一單元，第二單元點了才展開', (tester) async {
    await pumpLearningScreen(tester, tier: SubscriptionTierHelper.free);

    await tester.scrollUntilVisible(
      find.byKey(ebookUnitGroupKey(EbookUnit.becomeThePrize)),
      300,
      scrollable: _verticalScrollable,
    );
    await tester.pumpAndSettle();

    // 書架入口（工作包 7）：大標不得被順手改掉，說明句是規格 §8 的定稿句。
    expect(find.text('高階互動指南'), findsOneWidget);
    expect(find.textContaining('先看你卡在配對、聊天，還是邀約'), findsOneWidget);

    // 無進度：沒有繼續閱讀卡；第一單元的書直接可見，第二單元收合。
    expect(find.byKey(ebookResumeCardKey), findsNothing);
    expect(find.text('診斷 · 配對開場'), findsOneWidget);
    expect(find.text('已開始 0／4 本'), findsOneWidget);
    expect(find.text('已開始 0／3 本'), findsOneWidget);
    expect(find.text('內核 · 吸引怎麼發生'), findsNothing);

    await tester.tap(find.byKey(ebookUnitGroupKey(EbookUnit.becomeThePrize)));
    await tester.pumpAndSettle();
    expect(find.text('內核 · 吸引怎麼發生'), findsOneWidget);
    expect(find.text('框架 · 這段關係誰在主導'), findsOneWidget);
    expect(find.text('進階聊天 · 讀懂反應再出手'), findsOneWidget);
  });

  testWidgets('書架有進度：兩單元收合、改出繼續閱讀捷徑卡', (tester) async {
    final box = InMemoryHiveBox();
    await EbookProgressRepository(box: box).markChapterCompleted(
      ownerUserId: 'learning-owner',
      bookId: 'ebook-2-conversation',
      chapterId: 'ebook-2-chapter-1',
    );
    await pumpLearningScreen(
      tester,
      tier: SubscriptionTierHelper.free,
      progressBox: box,
    );

    await tester.scrollUntilVisible(
      find.byKey(ebookResumeCardKey),
      300,
      scrollable: _verticalScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('繼續閱讀'), findsOneWidget);
    // 捷徑卡指向開始過且未讀完的那本；書卡本身收合不出現。
    expect(find.text('續航 · 讓對話活下去'), findsOneWidget);
    expect(find.text('已開始 1／4 本'), findsOneWidget);
    expect(find.text('診斷 · 配對開場'), findsNothing);
    expect(find.text('內核 · 吸引怎麼發生'), findsNothing);
  });

  testWidgets('分類 chips 過濾文章 grid，全部＝24 篇', (tester) async {
    await pumpLearningScreen(tester, tier: SubscriptionTierHelper.free);

    await tester.scrollUntilVisible(
      find.byKey(learningArticleFilterAllKey),
      400,
      scrollable: _verticalScrollable,
    );
    await tester.pumpAndSettle();

    int gridCount() {
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      return (grid.delegate as SliverChildBuilderDelegate).childCount!;
    }

    expect(gridCount(), 24);

    // 從資料推導期望值，新增文章不必改這個測試。
    const category = '深度交流';
    final expected =
        articles.where((article) => article.category == category).length;
    expect(expected, greaterThan(0));

    await tester.tap(find.byKey(learningArticleFilterKey(category)));
    await tester.pumpAndSettle();
    expect(gridCount(), expected);
    // grid 首篇必是該分類文章。
    final firstFiltered =
        articles.firstWhere((article) => article.category == category);
    expect(find.text(firstFiltered.title), findsOneWidget);

    await tester.tap(find.byKey(learningArticleFilterAllKey));
    await tester.pumpAndSettle();
    expect(gridCount(), 24);
  });
}
