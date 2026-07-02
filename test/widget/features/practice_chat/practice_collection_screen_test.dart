import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/learning/presentation/screens/learning_screen.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_collection_store.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_collection_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

/// 同其他 widget test 的 seeded-notifier idiom：constructor 在 super 同步初始化後
/// 直接覆寫 state；無 Supabase user 時後續 async 初始化全 no-op。
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

PracticeCollectionNotifier _seededCollection(Set<String> unlocked) {
  final store = InMemoryPracticeCollectionStore();
  for (final id in unlocked) {
    store.add(id);
  }
  return PracticeCollectionNotifier(store);
}

Widget collectionApp({Set<String> unlocked = const {}}) {
  return ProviderScope(
    overrides: [
      practiceCollectionProvider
          .overrideWith((ref) => _seededCollection(unlocked)),
    ],
    child: const MaterialApp(home: PracticeCollectionScreen()),
  );
}

void main() {
  // practice_girl_001 = Alice（slow_worker → N）
  // practice_girl_004 = Mia（teasing_humor → SR）
  Future<void> pumpCollection(
    WidgetTester tester, {
    Set<String> unlocked = const {},
    Size surface = const Size(500, 1600),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(collectionApp(unlocked: unlocked));
    await tester.pump();
  }

  group('PracticeCollectionScreen', () {
    testWidgets('完成度數字與標頭正確', (tester) async {
      await pumpCollection(
        tester,
        unlocked: {'practice_girl_001', 'practice_girl_004'},
      );

      expect(find.text('角色圖鑑'), findsOneWidget); // AppBar 標題
      expect(find.text('VIBESYNC · GACHA'), findsOneWidget);
      expect(find.text('Collection'), findsOneWidget);
      expect(find.text('COMPLETION 完成度'), findsOneWidget);

      final count = tester.widget<Text>(
        find.byKey(const ValueKey('collection-completion-count')),
      );
      expect(count.data, '2');
      expect(find.text(' / 60'), findsOneWidget);
      expect(find.byKey(const ValueKey('collection-progress-fill')),
          findsOneWidget);
    });

    testWidgets('catalog 之外的髒 profileId 不灌水完成度', (tester) async {
      await pumpCollection(
        tester,
        unlocked: {'practice_girl_001', 'bogus_id'},
      );
      final count = tester.widget<Text>(
        find.byKey(const ValueKey('collection-completion-count')),
      );
      expect(count.data, '1');
    });

    testWidgets('鎖卡顯「？？？」＋鎖 icon；解鎖卡顯名字＋職業＋星等', (tester) async {
      await pumpCollection(tester, unlocked: {'practice_girl_004'});

      // 鎖卡：practice_girl_001（Alice）未解鎖
      final lockedCard =
          find.byKey(const ValueKey('collection-card-practice_girl_001'));
      expect(lockedCard, findsOneWidget);
      expect(
        find.descendant(of: lockedCard, matching: find.text('？？？')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: lockedCard, matching: find.text('Alice')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('collection-lock-practice_girl_001')),
        findsOneWidget,
      );
      // 鎖卡無星等
      expect(
        find.descendant(
            of: lockedCard, matching: find.byIcon(Icons.star_rounded)),
        findsNothing,
      );

      // 解鎖卡：practice_girl_004（Mia，teasing_humor → SR 4 星）
      final unlockedCard =
          find.byKey(const ValueKey('collection-card-practice_girl_004'));
      expect(
        find.descendant(of: unlockedCard, matching: find.text('Mia')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: unlockedCard, matching: find.text('咖啡師')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: unlockedCard, matching: find.text('SR')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: unlockedCard, matching: find.byIcon(Icons.star_rounded)),
        findsNWidgets(4),
      );
      expect(
        find.descendant(
            of: unlockedCard,
            matching: find.byIcon(Icons.star_outline_rounded)),
        findsNWidgets(1),
      );
      expect(
        find.byKey(const ValueKey('collection-lock-practice_girl_004')),
        findsNothing,
      );
    });

    testWidgets('稀有度篩選 chip 過濾 grid', (tester) async {
      await pumpCollection(tester);

      // 預設全部：N 的 001 與 SR 的 004 都在
      expect(find.byKey(const ValueKey('collection-card-practice_girl_001')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('collection-card-practice_girl_004')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('collection-filter-sr')));
      await tester.pump();

      // SR only：001（N）消失、004（SR）仍在
      expect(find.byKey(const ValueKey('collection-card-practice_girl_001')),
          findsNothing);
      expect(find.byKey(const ValueKey('collection-card-practice_girl_004')),
          findsOneWidget);

      // 切回全部
      await tester.tap(find.byKey(const ValueKey('collection-filter-all')));
      await tester.pump();
      expect(find.byKey(const ValueKey('collection-card-practice_girl_001')),
          findsOneWidget);
    });

    testWidgets('點鎖卡 → SnackBar「每日翻牌有機會遇到她」', (tester) async {
      await pumpCollection(tester);

      await tester
          .tap(find.byKey(const ValueKey('collection-card-practice_girl_001')));
      await tester.pump();

      expect(find.text('每日翻牌有機會遇到她'), findsOneWidget);
    });

    testWidgets('點解鎖卡 → 開全圖 viewer', (tester) async {
      await pumpCollection(tester, unlocked: {'practice_girl_004'});

      await tester
          .tap(find.byKey(const ValueKey('collection-card-practice_girl_004')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('practice-girl-full-photo-viewer')),
        findsOneWidget,
      );
    });
  });

  group('learning 入口 chip', () {
    testWidgets('顯示解鎖數且點擊導航到圖鑑頁', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const Scaffold(body: LearningScreen()),
          ),
          GoRoute(
            path: '/practice-collection',
            builder: (context, state) => const PracticeCollectionScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceCollectionProvider.overrideWith(
              (ref) => _seededCollection(
                  {'practice_girl_001', 'practice_girl_004'}),
            ),
            // 付費 tier：跳過 free 每日閱讀提示（避免觸 usage box）。
            subscriptionProvider.overrideWith(
              (ref) => _SeededSubscriptionNotifier(
                const SubscriptionState(
                  tier: SubscriptionTierHelper.starter,
                  monthlyLimit: 100,
                  dailyLimit: 30,
                ),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      final chip =
          find.byKey(const ValueKey('practice-collection-entry-chip'));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.text('角色圖鑑 2/60')),
        findsOneWidget,
      );

      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(find.text('COMPLETION 完成度'), findsOneWidget);
    });
  });
}
