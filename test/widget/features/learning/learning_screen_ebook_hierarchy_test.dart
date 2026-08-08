// test/widget/features/learning/learning_screen_ebook_hierarchy_test.dart
//
// 學習頁階層回歸：
//   Practice Hero → 聊天測驗 → 互動電子書 → 短篇實戰文章 → 24 篇文章 grid。
//
// 2026-07-31 起測驗插在電子書之前（§11 決定 1）：電子書是讀的，測驗是練的。
//
// 重點是 quota 提示只出現在文章區（電子書不消耗文章額度），
// 以及既有 24 篇文章與 article id 沒有被電子書改動。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

Future<void> pumpLearningScreen(
  WidgetTester tester, {
  required String tier,
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.free(),
  Object? quizCatalogError,
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
          EbookProgressRepository(box: InMemoryHiveBox()),
        ),
      ],
      // 練習室入口卡包了 LiquidMotionFrame（無限 ticker）；關動畫讓
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

    await tester.scrollUntilVisible(find.text('短篇實戰文章'), 300);
    await tester.pumpAndSettle();
    expect(find.text('短篇實戰文章'), findsOneWidget);
  });

  testWidgets('測驗區塊只有入口卡，第 2 期的東西都不出現', (tester) async {
    await pumpLearningScreen(tester, tier: SubscriptionTierHelper.free);

    expect(find.text('聊天測驗'), findsOneWidget);
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

    await tester.scrollUntilVisible(find.text('短篇實戰文章'), 300);
    await tester.pumpAndSettle();
    expect(find.text('短篇實戰文章'), findsOneWidget);
  });

  testWidgets('免費使用者的每日額度提示只出現在文章區，並註明電子書不計入', (tester) async {
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
