// Deterministic visual proof for the 2026-08-13 anti-AI-template UI pass.
// Renders the six authorized screens to before/ or after/ depending on
// ANTI_AI_UI_STAGE. Collection and practice opening use stable seeded state.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/app/main_shell.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/follow_up_notification/data/follow_up_opt_in_store.dart';
import 'package:vibesync/features/follow_up_notification/data/providers/follow_up_notification_service.dart';
import 'package:vibesync/features/follow_up_notification/domain/follow_up_opt_in.dart';
import 'package:vibesync/features/learning/data/providers/learning_providers.dart';
import 'package:vibesync/features/learning/data/services/article_read_service.dart';
import 'package:vibesync/features/learning/presentation/screens/learning_screen.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/add_partner_screen.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_list_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/getting_started_checklist.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_collection_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_collection_screen.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';
import 'package:hive_ce/hive_ce.dart' show Box;

import 'proof_support.dart';

/// 沒帶 `--dart-define=ANTI_AI_UI_STAGE=...` 就整支跳過：跑全套時預設值會把
/// before/ 基準圖蓋掉（本機對照就廢了），而且這支是產圖工具不是回歸測試。
const _stage = String.fromEnvironment('ANTI_AI_UI_STAGE');

String _stagePath(String name) => outPath('anti_ai_ui/$_stage/$name');

Future<void> _loadFonts() async {
  for (final path in const [
    '/mnt/c/Windows/Fonts/msjh.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    await (FontLoader('AppTC')
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
    break;
  }
  await loadProofFonts();
}

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

class _NullUserProfileController extends UserProfileController {
  @override
  Future<UserProfile?> build() async => null;
}

class _FilledUserProfileController extends UserProfileController {
  @override
  Future<UserProfile?> build() async =>
      UserProfile(notes: '已填', updatedAt: DateTime(2026, 8, 1));
}

class _FakeOptInStore extends FollowUpOptInStore {
  @override
  FollowUpOptIn read() => FollowUpOptIn.unknown;

  @override
  Future<void> write(FollowUpOptIn value) async {}
}

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

class _UnusedPracticeSessionBox extends Fake implements Box<PracticeSession> {}

class _FakePracticeSessionRepository extends PracticeSessionRepository {
  _FakePracticeSessionRepository() : super(_UnusedPracticeSessionBox());

  @override
  List<PracticeSession> recentSessions() => const [];

  @override
  Future<void> save(PracticeSession session) async {}
}

PracticeChatApiService _unusedApi() => PracticeChatApiService(
      invoker: (name, {required body}) async =>
          throw UnimplementedError('anti-ai-ui proof 不應打 practice-chat'),
    );

class _SeededPracticeChatController extends PracticeChatController {
  _SeededPracticeChatController(PracticeChatState seed)
      : super(
          api: _unusedApi(),
          repository: _FakePracticeSessionRepository(),
          sessionId: seed.sessionId,
          createdAt: seed.createdAt,
        ) {
    state = seed;
  }
}

List<Override> _homeOverrides() => [
      subscriptionProvider.overrideWith(
        (_) => _SeededSubscriptionNotifier(
          const SubscriptionState(
            tier: SubscriptionTierHelper.free,
            monthlyMessagesUsed: 7,
            monthlyLimit: 30,
          ),
        ),
      ),
      subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
      userProfileControllerProvider
          .overrideWith(_NullUserProfileController.new),
      analysisHistoryEventsProvider
          .overrideWithValue(const <AnalysisHistoryEvent>[]),
      followUpOptInStoreProvider.overrideWithValue(_FakeOptInStore()),
    ];

Partner _p(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u-proof',
    );

PartnerAggregateView _agg({
  int? heat,
  List<String> interests = const [],
  List<String> traits = const [],
  int daysAgo = 5,
}) =>
    PartnerAggregateView(
      unionInterests: interests,
      unionTraits: traits,
      unionNotes: null,
      latestHeat: heat,
      totalRounds: heat == null ? 0 : 3,
      totalMessages: 0,
      lastInteraction: DateTime.now().subtract(Duration(days: daysAgo)),
    );

class _PartnerHomeProof extends StatelessWidget {
  const _PartnerHomeProof();

  @override
  Widget build(BuildContext context) {
    return BrandPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          centerTitle: false,
          titleSpacing: 16,
          elevation: 0,
          title: Row(
            children: [
              Text(
                'VibeSync',
                style: AppTypography.headlineMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 12),
                decoration: const BoxDecoration(
                  color: AppColors.ctaStart,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.settings_rounded, size: 20),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: AppColors.onBackgroundPrimary,
                  shape: const CircleBorder(),
                ),
                onPressed: () {},
              ),
            ),
          ],
        ),
        body: const PartnerListScreen(
          bottomPadding: 32,
        ),
        floatingActionButton: const HomeFab(),
        bottomNavigationBar: _ProofBottomNav(selectedIndex: 0),
      ),
    );
  }
}

class _LearningProof extends StatelessWidget {
  const _LearningProof();

  @override
  Widget build(BuildContext context) {
    return BrandPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          centerTitle: false,
          titleSpacing: 16,
          elevation: 0,
          title: Row(
            children: [
              Text(
                'VibeSync',
                style: AppTypography.headlineMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 12),
                decoration: const BoxDecoration(
                  color: AppColors.ctaStart,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.settings_rounded, size: 20),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: AppColors.onBackgroundPrimary,
                  shape: const CircleBorder(),
                ),
                onPressed: () {},
              ),
            ),
          ],
        ),
        body: const LearningScreen(),
        bottomNavigationBar: _ProofBottomNav(selectedIndex: 2),
      ),
    );
  }
}

class _ProofBottomNav extends StatelessWidget {
  const _ProofBottomNav({required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.brandInk.withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ProofTab(
              icon: Icons.home,
              label: '首頁',
              selected: selectedIndex == 0,
            ),
            _ProofTab(
              icon: Icons.bar_chart_outlined,
              label: '報告',
              selected: selectedIndex == 1,
            ),
            _ProofTab(
              icon: Icons.menu_book_outlined,
              label: '學習',
              selected: selectedIndex == 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProofTab extends StatelessWidget {
  const _ProofTab({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppColors.ctaStart : Colors.white.withValues(alpha: 0.62);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 72, minHeight: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

PracticeChatState _openingSeed() {
  final girl = practiceGirlProfiles.firstWhere(
    (profile) => profile.profileId == 'practice_girl_067',
  );
  return PracticeChatState(
    sessionId: 'anti-ai-ui-opening',
    createdAt: DateTime(2026, 8, 13, 12, 23),
    girl: girl,
    personaId: girl.personaId,
    personaLabel: '幽默吐槽型',
    difficulty: 'normal',
    difficultyLabel: '一般',
    messages: const [],
    drawFreeAllowance: 6,
    drawFreeRemaining: 4,
    drawNextResetAt: '2999-01-01T04:00:00.000Z',
  );
}

PracticeCollectionNotifier _seededCollection(Set<String> unlocked) {
  final store = InMemoryPracticeCollectionStore();
  for (final id in unlocked) {
    store.add(id);
  }
  return PracticeCollectionNotifier(store);
}

void main() {
  if (_stage.isEmpty) {
    test('anti-ai-ui proof（需 --dart-define=ANTI_AI_UI_STAGE）', () {
      markTestSkipped('未指定 ANTI_AI_UI_STAGE，跳過產圖');
    });
    return;
  }
  setUpAll(_loadFonts);

  testWidgets('anti-ai-ui home populated', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final partners = [
        _p('amy', 'Amy'),
        _p('jenny', 'Jenny'),
        _p('joyce', 'Joyce'),
        _p('nina', 'Nina'),
        _p('gigi', 'Gigi'),
        _p('tina', 'Tina'),
      ];
      await pumpAndCapture(
        tester,
        child: ProviderScope(
          overrides: [
            ..._homeOverrides(),
            authConversationScopeProvider.overrideWith(
              (_) => Stream.value('u-proof'),
            ),
            partnerListProvider.overrideWith((_) => partners),
            partnerAggregateProvider('amy').overrideWith((_) => _agg()),
            partnerAggregateProvider('jenny').overrideWith((_) => _agg()),
            partnerAggregateProvider('joyce').overrideWith(
              (_) => _agg(
                heat: 68,
                interests: const ['茄汁牛肉飯'],
                traits: const ['喜歡碎碎念'],
              ),
            ),
            partnerAggregateProvider('nina').overrideWith(
              (_) => _agg(
                heat: 82,
                interests: const ['美食'],
                traits: const ['主動分享', '可愛自嘲'],
              ),
            ),
            partnerAggregateProvider('gigi').overrideWith(
              (_) => _agg(
                heat: 85,
                interests: const ['可愛小物'],
                traits: const ['活潑', 'QQ恐龍'],
              ),
            ),
            partnerAggregateProvider('tina').overrideWith(
              (_) => _agg(
                heat: 85,
                interests: const ['健身'],
                traits: const ['主動分享', '瑜伽'],
                daysAgo: 6,
              ),
            ),
            for (final partner in partners)
              conversationsByPartnerProvider(partner.id)
                  .overrideWith((_) => const <Conversation>[]),
          ],
          child: const _PartnerHomeProof(),
        ),
        outPath: _stagePath('home_populated.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('anti-ai-ui home empty', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpAndCapture(
        tester,
        child: ProviderScope(
          overrides: [
            ..._homeOverrides(),
            authConversationScopeProvider.overrideWith(
              (_) => Stream.value('u-proof'),
            ),
            partnerListProvider.overrideWith((_) => const <Partner>[]),
          ],
          child: const _PartnerHomeProof(),
        ),
        rasterDecodeWait: const Duration(milliseconds: 600),
        outPath: _stagePath('home_empty.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // 空態第二屏（夥伴稿 3）：兩張卡之後接著流，得先捲下去才拍得到完整空態。
  testWidgets('anti-ai-ui home empty page 2', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpAndCapture(
        tester,
        child: ProviderScope(
          overrides: [
            ..._homeOverrides(),
            authConversationScopeProvider.overrideWith(
              (_) => Stream.value('u-proof'),
            ),
            partnerListProvider.overrideWith((_) => const <Partner>[]),
          ],
          child: const _PartnerHomeProof(),
        ),
        rasterDecodeWait: const Duration(milliseconds: 600),
        beforeCapture: (t) async {
          // iOS bouncing physics：拉過頭要 settle 才會彈回 maxScrollExtent，
          // 只 pump 一幀會停在空白的 overscroll 區。
          await t.drag(
              find.byType(SingleChildScrollView), const Offset(0, -2000));
          await t.pumpAndSettle();
        },
        outPath: _stagePath('home_empty_page2.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // 起步清單完成後：空態退回單頁，Sydney 也回到原本置中的 h340。
  testWidgets('anti-ai-ui home empty single page', (tester) async {
    await pumpAndCapture(
      tester,
      child: ProviderScope(
        overrides: [
          subscriptionProvider.overrideWith(
            (_) => _SeededSubscriptionNotifier(
              const SubscriptionState(
                tier: SubscriptionTierHelper.free,
                monthlyMessagesUsed: 7,
                monthlyLimit: 30,
              ),
            ),
          ),
          subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
          followUpOptInStoreProvider.overrideWithValue(_FakeOptInStore()),
          userProfileControllerProvider
              .overrideWith(_FilledUserProfileController.new),
          analysisHistoryEventsProvider.overrideWithValue([
            AnalysisHistoryEvent(
              id: 'e1',
              kind: AnalysisHistoryKind.analyze,
              createdAt: DateTime(2026, 8, 1),
            ),
          ]),
          onboardingDrawRewardDismissedProvider.overrideWith((_) async => true),
          authConversationScopeProvider.overrideWith(
            (_) => Stream.value('u-proof'),
          ),
          partnerListProvider.overrideWith((_) => const <Partner>[]),
        ],
        child: const _PartnerHomeProof(),
      ),
      rasterDecodeWait: const Duration(milliseconds: 600),
      outPath: _stagePath('home_empty_single.png'),
    );
  });

  testWidgets('anti-ai-ui add partner', (tester) async {
    await pumpAndCapture(
      tester,
      child: ProviderScope(
        overrides: [
          authConversationScopeProvider.overrideWith(
            (ref) => Stream.value('u-proof'),
          ),
        ],
        child: const AddPartnerScreen(),
      ),
      outPath: _stagePath('add_partner.png'),
    );
  });

  testWidgets('anti-ai-ui learning hero', (tester) async {
    await tester.binding.setSurfaceSize(kPhone);
    final rootKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'AppTC'),
          child: RepaintBoundary(
            key: rootKey,
            child: ProviderScope(
              overrides: [
                subscriptionProvider.overrideWith(
                  (ref) => _SeededSubscriptionNotifier(
                    const SubscriptionState(tier: SubscriptionTierHelper.free),
                  ),
                ),
                articleReadServiceProvider
                    .overrideWithValue(_FakeReadService()),
              ],
              child: const _LearningProof(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    tester.takeException();
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 600),
        ));
    await tester.pump();
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      (File(_stagePath('learning_hero.png'))..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('anti-ai-ui collection', (tester) async {
    await pumpAndCapture(
      tester,
      rasterDecodeWait: const Duration(milliseconds: 700),
      child: ProviderScope(
        overrides: [
          practiceCollectionProvider.overrideWith(
            (ref) => _seededCollection({
              'practice_girl_030',
              'practice_girl_067',
            }),
          ),
          practiceChatControllerProvider.overrideWith(
            (ref) => _SeededPracticeChatController(_openingSeed()),
          ),
          subscriptionProvider.overrideWith(
            (ref) => _SeededSubscriptionNotifier(
              const SubscriptionState(
                tier: SubscriptionTierHelper.free,
                monthlyMessagesUsed: 7,
                monthlyLimit: 30,
              ),
            ),
          ),
          subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
        ],
        child: const PracticeCollectionScreen(),
      ),
      outPath: _stagePath('collection.png'),
    );
  });

  testWidgets('anti-ai-ui practice opening', (tester) async {
    await pumpAndCapture(
      tester,
      rasterDecodeWait: const Duration(milliseconds: 700),
      child: ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith(
            (ref) => _SeededPracticeChatController(_openingSeed()),
          ),
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
        child: const PracticeChatScreen(),
      ),
      outPath: _stagePath('practice_opening.png'),
    );
  });
}
