import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_game_intro_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_hint.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_learning_mode.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

/// 沿用 practice_difficulty_chips_test.dart 的 harness 慣例：
/// seeded-notifier idiom＋in-memory repository。
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

class _UnusedPracticeSessionBox extends Fake implements Box<PracticeSession> {}

class _MemoryPracticeSessionRepository extends PracticeSessionRepository {
  _MemoryPracticeSessionRepository() : super(_UnusedPracticeSessionBox());

  @override
  Future<void> save(PracticeSession session) async {}

  @override
  List<PracticeSession> recentSessions() => const [];
}

class _NoopPracticeChatApi extends PracticeChatApiService {
  @override
  Future<PracticeChatReply> sendMessage({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    PracticeLearningMode practiceMode = PracticeLearningMode.standard,
    int? temperatureScore,
    int? familiarityScore,
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
    PracticeHintReplyType? appliedHintType,
    String? appliedHintText,
  }) =>
      throw UnimplementedError();

  @override
  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    PracticeLearningMode practiceMode = PracticeLearningMode.standard,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
    List<PracticeAppliedHintTurnDto> appliedHintTurns = const [],
  }) =>
      throw UnimplementedError();
}

class _SeededPracticeChatController extends PracticeChatController {
  _SeededPracticeChatController({
    required PracticeChatState seed,
    required super.repository,
  }) : super(
          api: _NoopPracticeChatApi(),
          sessionId: seed.sessionId,
          createdAt: seed.createdAt,
        ) {
    state = seed;
  }
}

void main() {
  late PracticeSessionRepository repo;
  late InMemoryPracticeGameIntroStore introStore;

  setUp(() {
    repo = _MemoryPracticeSessionRepository();
    introStore = InMemoryPracticeGameIntroStore();
  });

  final srGirl = practiceGirlProfiles
      .firstWhere((girl) => girl.rarity == PracticeGirlRarity.sr);
  final nonSrGirl = practiceGirlProfiles
      .firstWhere((girl) => girl.rarity != PracticeGirlRarity.sr);

  PracticeChatState seedState({
    required bool sr,
    PracticeLearningMode learningMode = PracticeLearningMode.standard,
    List<PracticeMessage> messages = const [],
  }) {
    final girl = sr ? srGirl : nonSrGirl;
    return PracticeChatState(
      sessionId: 'game-intro-test',
      createdAt: DateTime(2026, 8, 8, 13),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      learningMode: learningMode,
      temperatureScore: learningMode.usesAssistedLearning ? 40 : null,
      familiarityScore: learningMode.usesAssistedLearning ? 5 : null,
      messages: messages,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    PracticeChatController controller, {
    String tier = SubscriptionTierHelper.free,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
          practiceGameIntroStoreProvider.overrideWithValue(introStore),
          subscriptionProvider.overrideWith(
            (ref) => _SeededSubscriptionNotifier(
              SubscriptionState(
                tier: tier,
                monthlyLimit: 100,
                dailyLimit: 30,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 需要驗證導頁去向的測試用：真 GoRouter＋假圖鑑頁。
  Future<void> pumpScreenWithRouter(
    WidgetTester tester,
    PracticeChatController controller, {
    String tier = SubscriptionTierHelper.free,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const PracticeChatScreen(),
        ),
        GoRoute(
          path: '/practice-collection',
          builder: (_, __) => const Scaffold(
            key: ValueKey('fake-practice-collection'),
            body: SizedBox.shrink(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
          practiceGameIntroStoreProvider.overrideWithValue(introStore),
          subscriptionProvider.overrideWith(
            (ref) => _SeededSubscriptionNotifier(
              SubscriptionState(
                tier: tier,
                monthlyLimit: 100,
                dailyLimit: 30,
              ),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapGameSegment(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('practice-learning-mode-game')),
    );
    await tester.pumpAndSettle();
  }

  /// 兩頁教學卡：收合 CTA（開始攻略／知道了／去圖鑑翻牌）與訂閱鈎子都在
  /// 第二頁（節奏與計分），要先按「下一頁」翻過去。
  Future<void> goToMechanicsPage(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('practice-game-intro-next')),
    );
    await tester.pumpAndSettle();
  }

  group('教學卡觸發', () {
    testWidgets('SR 卡首次選 Game → 彈教學卡；關閉即 markSeen', (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: true),
        repository: repo,
      );
      await pumpScreen(tester, controller);
      expect(
        find.byKey(const ValueKey('practice-game-intro-sheet')),
        findsNothing,
      );

      await tapGameSegment(tester);

      expect(
        find.byKey(const ValueKey('practice-game-intro-sheet')),
        findsOneWidget,
      );
      expect(find.text('Game 攻略指南'), findsOneWidget);

      await goToMechanicsPage(tester);
      await tester.tap(
        find.byKey(const ValueKey('practice-game-intro-cta')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('practice-game-intro-sheet')),
        findsNothing,
      );
      expect(await introStore.isSeen(), isTrue);
    });

    testWidgets('已看過 → 選 Game 不再彈', (tester) async {
      introStore = InMemoryPracticeGameIntroStore(seen: true);
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: true),
        repository: repo,
      );
      await pumpScreen(tester, controller);

      await tapGameSegment(tester);

      expect(controller.currentState.learningMode, PracticeLearningMode.game);
      expect(
        find.byKey(const ValueKey('practice-game-intro-sheet')),
        findsNothing,
      );
    });

    testWidgets('草稿還原成 Game 進場（首幀即 game）→ post-frame 補彈一次',
        (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: true, learningMode: PracticeLearningMode.game),
        repository: repo,
      );
      await pumpScreen(tester, controller);

      expect(
        find.byKey(const ValueKey('practice-game-intro-sheet')),
        findsOneWidget,
      );
    });

    testWidgets('SR 局教學卡第一頁 CTA 是「下一頁」，第二頁是「開始攻略」',
        (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: true, learningMode: PracticeLearningMode.game),
        repository: repo,
      );
      await pumpScreen(tester, controller);

      expect(find.text('下一頁：節奏與計分'), findsOneWidget);
      expect(find.text('開始攻略'), findsNothing);

      await goToMechanicsPage(tester);

      expect(find.text('開始攻略'), findsOneWidget);
      expect(find.text('分數怎麼算'), findsOneWidget);
    });
  });

  group('鎖定 Game 點擊（非 SR 也要認識玩法）', () {
    testWidgets('非 SR + Free 點 Game → 不切模式、彈教學卡、含訂閱鈎子、CTA 是「知道了」',
        (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: false),
        repository: repo,
      );
      await pumpScreen(tester, controller);

      await tapGameSegment(tester);

      expect(
        controller.currentState.learningMode,
        PracticeLearningMode.standard,
      );
      expect(
        find.byKey(const ValueKey('practice-game-intro-sheet')),
        findsOneWidget,
      );

      await goToMechanicsPage(tester);

      expect(
        find.byKey(const ValueKey('practice-game-intro-upsell')),
        findsOneWidget,
      );
      expect(find.text('知道了'), findsOneWidget);
      expect(find.text('開始攻略'), findsNothing);
    });

    testWidgets('非 SR 關閉教學卡 → markSeen、模式維持不變', (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: false),
        repository: repo,
      );
      await pumpScreen(tester, controller);

      await tapGameSegment(tester);
      await goToMechanicsPage(tester);
      await tester.tap(
        find.byKey(const ValueKey('practice-game-intro-cta')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('practice-game-intro-sheet')),
        findsNothing,
      );
      expect(
        controller.currentState.learningMode,
        PracticeLearningMode.standard,
      );
      expect(await introStore.isSeen(), isTrue);
    });

    testWidgets('非 SR + Starter 點 Game → 彈教學卡、無鈎子、CTA 是「去圖鑑翻牌」',
        (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: false),
        repository: repo,
      );
      await pumpScreen(
        tester,
        controller,
        tier: SubscriptionTierHelper.starter,
      );

      await tapGameSegment(tester);

      expect(
        find.byKey(const ValueKey('practice-game-intro-sheet')),
        findsOneWidget,
      );

      await goToMechanicsPage(tester);

      expect(
        find.byKey(const ValueKey('practice-game-intro-upsell')),
        findsNothing,
      );
      expect(find.text('去圖鑑翻牌'), findsOneWidget);
      expect(find.text('開始攻略'), findsNothing);
    });

    testWidgets('非 SR + Starter 點「去圖鑑翻牌」→ 導角色圖鑑', (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: false),
        repository: repo,
      );
      await pumpScreenWithRouter(
        tester,
        controller,
        tier: SubscriptionTierHelper.starter,
      );

      await tapGameSegment(tester);
      await goToMechanicsPage(tester);
      await tester.tap(
        find.byKey(const ValueKey('practice-game-intro-cta')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('fake-practice-collection')),
        findsOneWidget,
      );
    });
  });

  group('重看入口', () {
    testWidgets('Game 選中時副文案列尾有 info icon，點擊重開教學卡', (tester) async {
      introStore = InMemoryPracticeGameIntroStore(seen: true);
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: true, learningMode: PracticeLearningMode.game),
        repository: repo,
      );
      await pumpScreen(tester, controller);

      final infoIcon = find.byKey(const ValueKey('practice-game-intro-info'));
      expect(infoIcon, findsOneWidget);

      await tester.tap(infoIcon);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('practice-game-intro-sheet')),
        findsOneWidget,
      );
    });

    testWidgets('標準模式選中時沒有 info icon', (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: true),
        repository: repo,
      );
      await pumpScreen(tester, controller);

      expect(
        find.byKey(const ValueKey('practice-game-intro-info')),
        findsNothing,
      );
    });
  });

  group('訂閱鈎子', () {
    testWidgets('Free 帳號教學卡內含訂閱鈎子', (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: true, learningMode: PracticeLearningMode.game),
        repository: repo,
      );
      await pumpScreen(tester, controller);
      await goToMechanicsPage(tester);

      expect(
        find.byKey(const ValueKey('practice-game-intro-upsell')),
        findsOneWidget,
      );
      expect(find.text('查看方案'), findsOneWidget);
      // 批 2 機制上線後的具體承諾（訂閱送 SR 限定翻牌＝馬上解鎖 Game）；
      // 泛泛升級話術不回歸。
      expect(find.text('訂閱直接解鎖 Game'), findsOneWidget);
      expect(find.textContaining('SR 限定翻牌'), findsOneWidget);
      expect(find.text('想每天都有新對象可攻略？'), findsNothing);
    });

    testWidgets('付費帳號教學卡不顯示訂閱鈎子', (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: true, learningMode: PracticeLearningMode.game),
        repository: repo,
      );
      await pumpScreen(
        tester,
        controller,
        tier: SubscriptionTierHelper.starter,
      );

      expect(
        find.byKey(const ValueKey('practice-game-intro-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('practice-game-intro-upsell')),
        findsNothing,
      );
    });
  });

  group('對話內教練訊息', () {
    testWidgets('Game 開場前 hero 顯示 Game 版引導文案', (tester) async {
      introStore = InMemoryPracticeGameIntroStore(seen: true);
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: true, learningMode: PracticeLearningMode.game),
        repository: repo,
      );
      await pumpScreen(tester, controller);

      expect(find.textContaining('這局是 Game：照五階段推進'), findsOneWidget);
    });

    testWidgets('標準模式 hero 維持通用引導文案', (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(sr: true),
        repository: repo,
      );
      await pumpScreen(tester, controller);

      expect(find.textContaining('對方是個有自己個性的陪練女孩'), findsOneWidget);
      expect(find.textContaining('這局是 Game'), findsNothing);
    });

    testWidgets('Game 開聊後訊息列表頂部固定教練泡泡，且不動 state.messages',
        (tester) async {
      introStore = InMemoryPracticeGameIntroStore(seen: true);
      final messages = [
        const PracticeMessage(role: 'user', text: '今天遇到超好笑的事'),
        const PracticeMessage(role: 'ai', text: '哈哈說來聽聽'),
      ];
      final controller = _SeededPracticeChatController(
        seed: seedState(
          sr: true,
          learningMode: PracticeLearningMode.game,
          messages: messages,
        ),
        repository: repo,
      );
      await pumpScreen(tester, controller);

      expect(
        find.byKey(const ValueKey('practice-game-coach-intro')),
        findsOneWidget,
      );
      expect(find.textContaining('Game 進行中'), findsOneWidget);
      // UI-only：教練泡泡絕不進 state.messages（API payload 不受影響）。
      expect(controller.currentState.messages, hasLength(2));
    });

    testWidgets('標準模式開聊後不顯示教練泡泡', (tester) async {
      final controller = _SeededPracticeChatController(
        seed: seedState(
          sr: true,
          messages: const [
            PracticeMessage(role: 'user', text: '哈囉'),
            PracticeMessage(role: 'ai', text: '嗨'),
          ],
        ),
        repository: repo,
      );
      await pumpScreen(tester, controller);

      expect(
        find.byKey(const ValueKey('practice-game-coach-intro')),
        findsNothing,
      );
    });
  });
}
