import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/practice_reveal_palette.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_draw_draft_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_game_intro_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_hint.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_learning_mode.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_profile.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_rarity.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_temperature.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_sfx.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_card.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_painters.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_theme.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_timing.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/subscription/presentation/paywall_entry.dart';
import 'package:vibesync/shared/widgets/ai_data_sharing_consent.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';
import 'package:vibesync/shared/widgets/chat_bubble.dart';

class _UnusedPracticeSessionBox extends Fake implements Box<PracticeSession> {}

/// 同其他 widget test 的 seeded-notifier idiom：constructor 在 super 同步初始化後
/// 直接覆寫 state；無 Supabase user 時後續 async 初始化全 no-op。
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

class _MemoryPracticeSessionRepository extends PracticeSessionRepository {
  _MemoryPracticeSessionRepository([Iterable<PracticeSession> seed = const []])
      : super(_UnusedPracticeSessionBox()) {
    for (final session in seed) {
      _sessions[session.id] = session;
    }
  }

  final Map<String, PracticeSession> _sessions = {};

  @override
  Future<void> save(PracticeSession session) async {
    _sessions[session.id] = session;
  }

  @override
  List<PracticeSession> recentSessions() {
    final sorted = _sessions.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final seen = <String>{};
    final result = <PracticeSession>[];
    for (final s in sorted) {
      if (seen.add(PracticeSessionRepository.threadKeyOf(s))) result.add(s);
    }
    return result.take(PracticeSessionRepository.maxThreads).toList();
  }

  @override
  PracticeSession? getById(String id) => _sessions[id];

  @override
  Future<void> delete(String id) async {
    _sessions.remove(id);
  }

  @override
  Future<void> deleteVisibleThread(String threadKey) async {
    _sessions.removeWhere(
      (_, s) => PracticeSessionRepository.threadKeyOf(s) == threadKey,
    );
  }
}

PracticeDrawResult _drawResultFor(PracticeGirlProfile g) {
  return PracticeDrawResult(
    profile: PracticeDrawnProfile(
      profileId: g.profileId,
      nameId: g.nameId,
      professionId: g.professionId,
      photoId: g.photoId,
      personaId: g.personaId,
    ),
    draw: const PracticeDrawReceipt(
      costMessages: 0,
      freeAllowance: 1,
      freeUsed: 1,
      freeRemaining: 0,
      extraCostMessages: 5,
      nextResetAt: '2999-01-01T04:00:00.000Z',
    ),
    usage: const PracticeDrawUsage(
      monthlyUsed: 0,
      monthlyLimit: 30,
      dailyUsed: 0,
      dailyLimit: 30,
    ),
  );
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
  }) {
    throw UnimplementedError();
  }

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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PracticeDrawResult> drawProfile({
    required String requestId,
    String? currentProfileId,
    String? visiblePracticeThreadId,
    bool srTicket = false,
  }) async {
    // 換一位／翻牌：回固定一位（與目前不同），給 seeded 控制器的 draw 路徑用。
    final next = practiceGirlProfiles.firstWhere(
      (g) => g.profileId != currentProfileId,
      orElse: () => practiceGirlProfiles.first,
    );
    return _drawResultFor(next);
  }
}

/// 翻牌入口測試用：drawProfile 可設定成功回某位或拋指定例外。
class _DrawApi extends PracticeChatApiService {
  _DrawApi(this._handler);

  final Future<PracticeDrawResult> Function()? _handler;
  int drawCalls = 0;

  @override
  Future<PracticeDrawResult> drawProfile({
    required String requestId,
    String? currentProfileId,
    String? visiblePracticeThreadId,
    bool srTicket = false,
  }) {
    drawCalls++;
    return _handler!();
  }

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

/// 翻牌音效 spy：記錄各呼叫點次數與呼叫順序（[calls]），`looping` 由 start/stop 差推導，
/// 用來斷言「等待 loop 不殘留」。預設 no-op 行為（不真的播放）。
class _SpyPracticeDrawSfx implements PracticeDrawSfx {
  int whoosh = 0;
  int whooshStop = 0;
  int preload = 0;
  int waitingStart = 0;
  int waitingStop = 0;
  int bedStart = 0;
  int bedStop = 0;
  int archive = 0;
  final List<String> calls = [];

  /// start 次數多於 stop ⇒ loop 仍在播（用來驗證離開 drawing 後必為 false）。
  bool get looping => waitingStart > waitingStop;

  /// bed start 多於 stop ⇒ 配樂仍在播（驗證每個離開出口後必收掉）。
  bool get bedPlaying => bedStart > bedStop;

  @override
  void playWhoosh() {
    whoosh++;
    calls.add('whoosh');
  }

  @override
  void stopWhoosh() {
    whooshStop++;
    calls.add('whooshStop');
  }

  @override
  void preloadReveal() {
    preload++;
    calls.add('preload');
  }

  @override
  void playWaitingLoop() {
    waitingStart++;
    calls.add('waitingStart');
  }

  @override
  void stopWaitingLoop() {
    waitingStop++;
    calls.add('waitingStop');
  }

  @override
  void playRevealBed() {
    bedStart++;
    calls.add('bedStart');
  }

  @override
  void stopRevealBed() {
    bedStop++;
    calls.add('bedStop');
  }

  @override
  void playArchive() {
    archive++;
    calls.add('archive');
  }
}

class _HintApi extends _NoopPracticeChatApi {
  _HintApi(this.result);

  final PracticeHintResult result;
  int hintCalls = 0;

  @override
  Future<PracticeHintResult> requestHint({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
    String? requestId,
    int? expectedAiCount,
    PracticeLearningMode practiceMode = PracticeLearningMode.beginner,
  }) async {
    hintCalls++;
    return result;
  }
}

class _MessageApi extends _NoopPracticeChatApi {
  _MessageApi(this._handler);

  final Future<PracticeChatReply> Function(List<PracticeTurnDto> turns)
      _handler;
  int sendCalls = 0;
  PracticeHintReplyType? lastAppliedHintType;
  String? lastAppliedHintText;
  List<PracticeTurnDto> lastTurns = const [];

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
  }) {
    sendCalls++;
    lastAppliedHintType = appliedHintType;
    lastAppliedHintText = appliedHintText;
    lastTurns = turns;
    return _handler(turns);
  }
}

/// save 一律失敗：驗「完成」收尾失敗時不得靜默離開。
class _FailingSavePracticeSessionRepository
    extends _MemoryPracticeSessionRepository {
  _FailingSavePracticeSessionRepository(super.seed);

  @override
  Future<void> save(PracticeSession session) async {
    throw StateError('simulated close save failure');
  }
}

class _SeededPracticeChatController extends PracticeChatController {
  _SeededPracticeChatController({
    required PracticeChatState seed,
    required super.repository,
    PracticeChatApiService? api,
  }) : super(
          api: api ?? _NoopPracticeChatApi(),
          sessionId: seed.sessionId,
          createdAt: seed.createdAt,
        ) {
    state = seed;
  }
}

/// 圖鑑點卡縫（startProfileId）：只錄 startSessionWithProfile 呼叫（含參數）。
class _StartProfileSpyController extends _SeededPracticeChatController {
  _StartProfileSpyController({required super.seed, required super.repository});

  final List<String> startSessionCalls = [];

  @override
  void startSessionWithProfile(String profileId) {
    startSessionCalls.add(profileId);
  }
}

/// 拆解卡同意閘：只錄 endPractice 有沒有真的被叫到（不打 API）。
class _EndPracticeSpyController extends _SeededPracticeChatController {
  _EndPracticeSpyController({required super.seed, required super.repository});

  int endPracticeCalls = 0;

  @override
  Future<void> endPractice() async {
    endPracticeCalls++;
  }
}

/// Task 4b：儀式 overlay 的 production 掛載點已搬到角色圖鑑頁（唯一掛載，
/// 見 practice_collection_screen.dart 與其測試）。本檔的儀式時間軸／音效行為
/// 測試驗的是 ceremony 狀態機（watch controller 驅動、與掛載頁無關）。
/// Task 5 後練習室本體已無翻牌觸發點（入口全收斂圖鑑），host 用隱形測試鈕
/// （沿用 key `practice-draw-cta`）直呼 controller.drawNewPracticeGirl 保住
/// 既有觸發路徑；練習室不再掛儀式，另有專測釘住。
class _CeremonyTestHost extends ConsumerWidget {
  const _CeremonyTestHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        const PracticeChatScreen(),
        const Positioned.fill(child: PracticeDrawCeremony()),
        Positioned(
          left: 0,
          top: 0,
          child: GestureDetector(
            key: const ValueKey('practice-draw-cta'),
            behavior: HitTestBehavior.opaque,
            onTap: () => ref
                .read(practiceChatControllerProvider.notifier)
                .drawNewPracticeGirl(),
            child: const SizedBox(width: 24, height: 24),
          ),
        ),
      ],
    );
  }
}

// ── V3 翻牌揭曉（規格 docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md）──
const _ceremonyBackKey = ValueKey('practice-draw-ceremony-back');
const _ceremonyFrontKey = ValueKey('practice-draw-ceremony-front');
const _ceremonyHintKey = ValueKey('practice-draw-ceremony-hint');
const _ceremonyContinueKey = ValueKey('practice-draw-ceremony-continue');

/// 揭曉時間軸上的一段時長（pump 用）：節點一律由 [PracticeRevealTiming] 推導，
/// 與儀式 widget 共用單一真相（重新調節點不會讓測試落點失準）。
Duration revealAt(double ms) => Duration(milliseconds: ms.round());

/// 揭曉走完會停在 holding（畫面靜止）；點「繼續」收卡、收掉 overlay。結尾再推
/// 250 ms：SR celebrate 等觸覺內部的 Future.delayed 不留 pending timer。
Future<void> finishCeremony(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final continueButton = find.byKey(_ceremonyContinueKey);
  if (continueButton.evaluate().isNotEmpty) {
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
  }
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  late PracticeSessionRepository repo;
  late InMemoryPracticeDrawDraftStore draftStore;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = _MemoryPracticeSessionRepository();
    draftStore = InMemoryPracticeDrawDraftStore();
  });

  testWidgets('renders practice bubbles on the light conversation workspace',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final seed = PracticeChatState(
      sessionId: 'practice-style-test',
      createdAt: DateTime(2026, 6, 24, 15, 30),
      aiReplyCount: 1,
      girl: practiceGirlProfiles.first,
      personaId: 'slow_worker',
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      messages: const [
        PracticeMessage(role: 'user', text: '今天好無聊'),
        PracticeMessage(role: 'ai', text: '認真的嗎？我今天事情多到爆炸，超想喊假的。'),
      ],
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    final workspace = tester.widget<Container>(
      find.byKey(const ValueKey('practice-chat-workspace')),
    );
    final decoration = workspace.decoration! as BoxDecoration;

    expect(decoration.color, AppColors.transcriptBoard);
    expect(decoration.border, isNull);
    expect(find.text('我說'), findsNothing);
    expect(find.text('她說'), findsNothing);
    expect(find.bySemanticsLabel('我說\n今天好無聊\n已讀'), findsOneWidget);
    expect(find.bySemanticsLabel('她說\n認真的嗎？我今天事情多到爆炸，超想喊假的。'), findsOneWidget);
    expect(find.text('今天好無聊'), findsOneWidget);
    expect(find.textContaining('認真的嗎'), findsOneWidget);

    final userText = tester.widget<Text>(find.text('今天好無聊'));
    expect(userText.style?.color, AppColors.glassTextPrimary);
    semantics.dispose();
  });

  testWidgets(
      'shared bubbles keep reveal timing and accessible visible text at 320',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        practiceChatControllerProvider
            .overrideWith((ref) => _SeededPracticeChatController(
                  repository: repo,
                  seed: PracticeChatState(
                    sessionId: 'shared-bubble-reveal',
                    personaId: 'slow_worker',
                    personaLabel: '慢熱上班族',
                    difficulty: 'normal',
                    difficultyLabel: '一般',
                    createdAt: DateTime(2026, 10, 5),
                    girl: practiceGirlProfiles.first,
                    aiReplyCount: 1,
                    messages: [
                      const PracticeMessage(role: 'user', text: '好'),
                      PracticeMessage(
                        role: 'ai',
                        text: '先喝杯水\n等一下再聊',
                        sentAt: DateTime(2026, 10, 5, 15, 26),
                      ),
                    ],
                  ),
                )),
        subscriptionProvider.overrideWith((ref) => _SeededSubscriptionNotifier(
              const SubscriptionState(
                tier: SubscriptionTierHelper.starter,
                monthlyLimit: 100,
                dailyLimit: 30,
              ),
            )),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: const PracticeChatScreen(),
      ),
    ));
    expect(find.text('先喝杯水'), findsOneWidget);
    expect(find.text('等一下再聊'), findsNothing);
    expect(find.bySemanticsLabel('她說\n先喝杯水\n下午 3:26'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('practice-bubble-avatar')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('practice-profile-avatar')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 999));
    expect(find.text('等一下再聊'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('等一下再聊'), findsOneWidget);
    expect(find.bySemanticsLabel('她說\n先喝杯水\n等一下再聊\n下午 3:26'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('practice-bubble-avatar')), findsOneWidget);
    expect(find.byKey(const ValueKey('practice-message-time')), findsOneWidget);
    final first =
        find.ancestor(of: find.text('先喝杯水'), matching: find.byType(ChatBubble));
    final second = find.ancestor(
        of: find.text('等一下再聊'), matching: find.byType(ChatBubble));
    expect(tester.widget<ChatBubble>(first).tail, isTrue);
    expect(tester.widget<ChatBubble>(second).tail, isFalse);
    expect(tester.getTopLeft(second).dx, tester.getTopLeft(first).dx);
    expect(tester.getTopLeft(second).dy - tester.getBottomLeft(first).dy, 2);
    expect(tester.getSize(first).width, lessThanOrEqualTo(320 * .7));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  for (final profileId in <String?>[
    null,
    'retired-profile',
    'practice_girl_005'
  ]) {
    testWidgets('history bubble avatars handle profile $profileId',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await repo.save(PracticeSession(
        id: 'shared-bubble-history',
        closed: true,
        createdAt: DateTime(2026, 10, 5),
        profileId: profileId,
        aiReplyCount: 2,
        messages: const [
          PracticeMessage(role: 'user', text: '泡泡回顧測試'),
          PracticeMessage(role: 'ai', text: '第一段\n第二段'),
          PracticeMessage(role: 'ai', text: '接著說'),
        ],
      ));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ));
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();
      await tester.tap(find.text('泡泡回顧測試').last);
      await tester.pumpAndSettle();
      final known = profileId == 'practice_girl_005';
      expect(find.byKey(const ValueKey('practice-bubble-avatar')),
          known ? findsOneWidget : findsNothing);
      expect(find.byType(ChatAvatarGutter),
          known ? findsNWidgets(3) : findsNothing);
      final first = find.ancestor(
          of: find.text('第一段'), matching: find.byType(ChatBubble));
      final second = find.ancestor(
          of: find.text('第二段'), matching: find.byType(ChatBubble));
      final next = find.ancestor(
          of: find.text('接著說'), matching: find.byType(ChatBubble));
      expect(tester.widget<ChatBubble>(first).tail, isTrue);
      expect(tester.widget<ChatBubble>(second).tail, isFalse);
      expect(tester.widget<ChatBubble>(next).tail, isFalse);
      expect(tester.getTopLeft(next).dx, tester.getTopLeft(first).dx);
      expect(tester.getTopLeft(next).dy - tester.getBottomLeft(second).dy, 4);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('進房沒有 session/draft → locked 翻牌入口，不顯示任何對象', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    // 翻牌入口已收斂圖鑑：這裡只給導引鈕（Task 5）。
    expect(find.text('翻牌解鎖新女孩'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-goto-collection-cta')),
      findsOneWidget,
    );
    expect(find.text('去圖鑑翻牌'), findsOneWidget);
    expect(find.text('到角色圖鑑翻開今日對象，開始練習。'), findsOneWidget);
    // 不顯示任何對象（無 hero、無頭像、無開場前控制）。
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsNothing);
    expect(
      find.byKey(const ValueKey('practice-profile-avatar')),
      findsNothing,
    );
    expect(find.text('換一位'), findsNothing);
  });

  testWidgets('opens unfinished local session for continuation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await repo.save(PracticeSession(
      id: 'resume-widget',
      createdAt: DateTime(2026, 6, 24, 15, 58),
      aiReplyCount: 1,
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗨～你今天怎麼樣？'),
      ],
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.text('嗨'), findsOneWidget);
    expect(find.text('嗨～你今天怎麼樣？'), findsOneWidget);
    expect(find.textContaining('本場已扣 1 則'), findsOneWidget);
  });

  testWidgets('recent sessions can be deleted from the history sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await repo.save(PracticeSession(
      id: 'delete-me',
      createdAt: DateTime(2026, 6, 24, 15, 58),
      aiReplyCount: 1,
      messages: const [PracticeMessage(role: 'user', text: '嗨')],
      debriefSummary: '已拆解',
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-practice-delete-me')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();

    expect(repo.getById('delete-me'), isNull);
    expect(find.text('還沒有練習紀錄'), findsOneWidget);
  });

  testWidgets('history sheet 批次刪除：選取→全選→確認後全刪、離開選取模式', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final id in ['s1', 's2', 's3']) {
      await repo.save(PracticeSession(
        id: id,
        createdAt: DateTime(2026, 6, 24, 15, 58),
        aiReplyCount: 1,
        messages: [PracticeMessage(role: 'user', text: '第 $id 場')],
        debriefSummary: '已拆解',
      ));
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('practice-session-select')));
    await tester.pump();
    expect(find.text('已選 0 場'), findsOneWidget);
    // 選取模式下每列的單刪垃圾桶要收起來。
    expect(find.byKey(const ValueKey('delete-practice-s1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('practice-session-select-all')));
    await tester.pump();
    expect(find.text('已選 3 場'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('practice-session-batch-delete')));
    await tester.pumpAndSettle();
    expect(find.text('刪除 3 場練習？'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('practice-session-batch-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(repo.getById('s1'), isNull);
    expect(repo.getById('s2'), isNull);
    expect(repo.getById('s3'), isNull);
    expect(find.text('已刪除 3 場練習'), findsOneWidget);
    expect(find.text('還沒有練習紀錄'), findsOneWidget);
  });

  for (final mode in <(String, String)>[
    ('beginner', 'practice_girl_005'),
    ('game', 'practice_girl_004'),
  ]) {
    testWidgets(
        '${mode.$1} history hides an unversioned Debrief behind the retired notice',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final transcript = '舊版 ${mode.$1} 對話';
      await repo.save(PracticeSession(
        id: 'legacy-debrief-${mode.$1}',
        createdAt: DateTime(2026, 7, 12, 13),
        aiReplyCount: 1,
        messages: [
          PracticeMessage(role: 'user', text: transcript),
          const PracticeMessage(role: 'ai', text: '舊版回覆'),
        ],
        profileId: mode.$2,
        practiceMode: mode.$1,
        debriefSummary: '不該顯示的舊版摘要 ${mode.$1}',
        debriefSuggestedLine: '不該顯示的舊版下一句 ${mode.$1}',
        debriefGameNextFirstLine: mode.$1 == 'game' ? '不該顯示的舊版 Game 下一句' : null,
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceSessionRepositoryProvider.overrideWithValue(repo),
            practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
          ],
          child: const MaterialApp(home: PracticeChatScreen()),
        ),
      );

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();
      await tester.tap(find.text(transcript));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('practice-retired-debrief-notice')),
        findsOneWidget,
      );
      expect(find.text('舊版拆解已停用，請開始新一場取得新版。'), findsOneWidget);
      expect(find.text('不該顯示的舊版摘要 ${mode.$1}'), findsNothing);
      expect(find.text('不該顯示的舊版下一句 ${mode.$1}'), findsNothing);
      expect(find.text('不該顯示的舊版 Game 下一句'), findsNothing);
    });

    testWidgets('${mode.$1} history renders a current-version Debrief normally',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final transcript = '新版 ${mode.$1} 對話';
      await repo.save(PracticeSession(
        id: 'current-debrief-${mode.$1}',
        createdAt: DateTime(2026, 7, 12, 13, 1),
        aiReplyCount: 1,
        messages: [
          PracticeMessage(role: 'user', text: transcript),
          const PracticeMessage(role: 'ai', text: '新版回覆'),
        ],
        profileId: mode.$2,
        practiceMode: mode.$1,
        debriefSummary: '新版具體摘要 ${mode.$1}',
        debriefSuggestedLine: '新版具體下一句 ${mode.$1}',
        debriefGamePhaseReached: mode.$1 == 'game' ? '破冰' : null,
        debriefGameMissedVariable: mode.$1 == 'game' ? '沒接住她的興趣線' : null,
        debriefGameFailureState: mode.$1 == 'game' ? '話題斷裂' : null,
        debriefGameNextFirstLine: mode.$1 == 'game' ? '新版 Game 具體下一句' : null,
        debriefGameInviteDirection: mode.$1 == 'game' ? '再觀察一輪' : null,
        debriefQualitySchemaVersion: kPracticeDebriefQualitySchemaVersion,
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceSessionRepositoryProvider.overrideWithValue(repo),
            practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
          ],
          child: const MaterialApp(home: PracticeChatScreen()),
        ),
      );

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();
      await tester.tap(find.text(transcript));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('practice-retired-debrief-notice')),
        findsNothing,
      );
      expect(find.text('新版具體摘要 ${mode.$1}'), findsOneWidget);
      expect(find.text('新版具體下一句 ${mode.$1}'), findsOneWidget);
      if (mode.$1 == 'game') {
        expect(find.textContaining('新版 Game 具體下一句'), findsOneWidget);
      }
    });
  }

  testWidgets('deleting a continued conversation removes all its rounds',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 同一位續玩兩輪：共用 visiblePracticeThreadId，各自 billing session id。
    await repo.save(PracticeSession(
      id: 'thread-a-r1',
      createdAt: DateTime(2026, 6, 24, 15, 50),
      aiReplyCount: 20,
      visiblePracticeThreadId: 'thread-a',
      roundIndex: 1,
      messages: const [PracticeMessage(role: 'user', text: '第一輪')],
    ));
    await repo.save(PracticeSession(
      id: 'thread-a-r2',
      createdAt: DateTime(2026, 6, 24, 15, 58),
      aiReplyCount: 3,
      visiblePracticeThreadId: 'thread-a',
      roundIndex: 2,
      messages: const [PracticeMessage(role: 'user', text: '第二輪')],
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    // 去重後同一位只顯示一筆（最新一輪 r2）。
    expect(
      find.byKey(const ValueKey('delete-practice-thread-a-r2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('delete-practice-thread-a-r1')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('delete-practice-thread-a-r2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();

    // 刪掉整段對話：兩輪都要消失，不能只刪最新一輪讓舊輪浮回。
    expect(repo.getById('thread-a-r1'), isNull);
    expect(repo.getById('thread-a-r2'), isNull);
    expect(find.text('還沒有練習紀錄'), findsOneWidget);
  });

  testWidgets('翻牌後（revealed、未送出）顯示 hero + 難度 chips（換一位已收斂圖鑑）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final girl = practiceGirlProfiles.first;
    final seed = PracticeChatState(
      sessionId: 'revealed-pre-msg',
      createdAt: DateTime(2026, 6, 26, 13),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      messages: const [],
    );
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    // 揭曉後（開場前）：首屏 hero 大卡 + 難度 chips；換一位入口已收斂圖鑑。
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    expect(find.text('換一位'), findsNothing);
    expect(find.text('為你抽了一位，先看看再開練'), findsNothing);
    expect(find.text('輕鬆'), findsOneWidget);
    expect(find.text('一般'), findsOneWidget);
    expect(find.text('挑戰'), findsOneWidget);
    expect(find.text('隨機'), findsOneWidget);
  });

  testWidgets('started room hides persona changer and keeps profile visible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await repo.save(PracticeSession(
      id: 'started',
      createdAt: DateTime(2026, 6, 24, 18),
      aiReplyCount: 1,
      personaId: 'cool_rational',
      personaLabel: '高冷理性型',
      difficulty: 'challenge',
      difficultyLabel: '挑戰',
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗯？'),
      ],
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    // 開聊後：compact header 顯示名字/職業＋難度，隱藏換一位與難度 chips。
    expect(find.textContaining('航空業空服員'), findsWidgets);
    expect(find.textContaining('挑戰'), findsOneWidget);
    expect(find.text('換一位'), findsNothing);
    expect(find.text('輕鬆'), findsNothing);
  });

  testWidgets('profile bar 顯示對象 name/profession 與頭像（對齊 profileId）',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await repo.save(PracticeSession(
      id: 'with-girl',
      createdAt: DateTime(2026, 6, 24, 18),
      aiReplyCount: 1,
      profileId: 'practice_girl_003', // Zoe · 醫院護理師
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗯？'),
      ],
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.textContaining('Zoe'), findsWidgets);
    expect(find.textContaining('醫院護理師'), findsWidgets);
    expect(
      find.byKey(const ValueKey('practice-profile-avatar')),
      findsOneWidget,
    );
  });

  // ── 拆解後續玩 CTA（Eric 決策：續玩當主鈕）─────────────────────────────
  PracticeChatState debriefSeed({
    int roundIndex = 1,
    String persona = '慢熱上班族',
    bool includeInviteInsight = false,
  }) {
    return PracticeChatState(
      sessionId: 'debrief-sess',
      createdAt: DateTime(2026, 6, 24, 16),
      girl: practiceGirlProfiles.first,
      personaId: 'slow_worker',
      personaLabel: persona,
      difficulty: 'normal',
      difficultyLabel: '一般',
      roundIndex: roundIndex,
      visiblePracticeThreadId: 'debrief-sess',
      aiReplyCount: 3,
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗯？'),
      ],
      sessionComplete: true,
      ended: true,
      debrief: PracticeDebrief(
        summary: '整體不錯',
        strengths: ['開場好'],
        watchouts: [],
        suggestedLine: '約她',
        vibe: '暖',
        dateChance: includeInviteInsight ? 'high' : null,
        dateChanceReason: includeInviteInsight ? '她已經主動接住話題。' : null,
        nextInviteMove: includeInviteInsight ? '用模糊邀約測窗口。' : null,
      ),
    );
  }

  Future<void> pumpDebrief(
    WidgetTester tester, {
    required PracticeChatController controller,
    SubscriptionState? subscription,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
          if (subscription != null)
            subscriptionProvider.overrideWith(
                (ref) => _SeededSubscriptionNotifier(subscription)),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );
  }

  testWidgets('拆解後：續玩當主鈕、附扣費說明、加去圖鑑換人與完成', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: debriefSeed(),
      repository: repo,
    );
    await pumpDebrief(
      tester,
      controller: controller,
      subscription: const SubscriptionState(
        tier: SubscriptionTierHelper.starter,
        monthlyLimit: 100,
        dailyLimit: 30,
      ),
    );

    expect(find.text('續聊同一位'), findsOneWidget);
    expect(find.textContaining('再扣 1 則'), findsOneWidget);
    expect(find.text('去圖鑑換人'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('拆解卡顯示邀約判斷欄位', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: debriefSeed(includeInviteInsight: true),
      repository: repo,
    );
    await pumpDebrief(tester, controller: controller);

    expect(find.text('邀約判斷'), findsOneWidget);
    expect(find.text('機會 高'), findsOneWidget);
    expect(find.text('她已經主動接住話題。'), findsOneWidget);
    expect(find.textContaining('下一步：用模糊邀約測窗口。'), findsOneWidget);
  });

  testWidgets('第 3 輪拆解後：仍可續聊同一位', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: debriefSeed(roundIndex: 3),
      repository: repo,
    );
    await pumpDebrief(
      tester,
      controller: controller,
      subscription: const SubscriptionState(
        tier: SubscriptionTierHelper.starter,
        monthlyLimit: 100,
        dailyLimit: 30,
      ),
    );

    expect(find.text('續聊同一位'), findsOneWidget);
    expect(find.textContaining('再扣 1 則'), findsOneWidget);
    expect(find.text('去圖鑑換人'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('付費點續聊同一位 → 進新一輪（roundIndex 2、清拆解、可送）', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: debriefSeed(),
      repository: repo,
    );
    await pumpDebrief(
      tester,
      controller: controller,
      subscription:
          const SubscriptionState(tier: SubscriptionTierHelper.starter),
    );

    await tester.tap(find.text('續聊同一位'));
    await tester.pump();

    final s = controller.currentState;
    expect(s.roundIndex, 2);
    expect(s.debrief, isNull);
    expect(s.messages.map((m) => m.text).toList(), ['嗨', '嗯？']);
    expect(s.canSend, true);
    expect(s.upgradeRequired, false);
  });

  testWidgets('Free 點續聊同一位 → 付費牆提示，拆解與訊息不動', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: debriefSeed(),
      repository: repo,
    );
    await pumpDebrief(
      tester,
      controller: controller,
      subscription: const SubscriptionState(tier: SubscriptionTierHelper.free),
    );

    await tester.tap(find.text('續聊同一位'));
    await tester.pump();

    final s = controller.currentState;
    expect(s.upgradeRequired, true);
    expect(s.debrief, isNotNull); // 不清拆解
    expect(s.messages.length, 2); // 不動 transcript
    expect(find.text('升級'), findsOneWidget); // 錯誤橫幅導付費牆
  });

  testWidgets('拆解後點去圖鑑換人 → 導回圖鑑、不在練習室觸發 draw', (tester) async {
    final api = _DrawApi(() async => _drawResultFor(practiceGirlProfiles[3]));
    final controller = _SeededPracticeChatController(
      seed: debriefSeed(),
      repository: repo,
      api: api,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const PracticeChatScreen(),
        ),
        GoRoute(
          path: '/practice-collection',
          builder: (context, state) => const Scaffold(
            body: SizedBox(key: ValueKey('practice-test-collection')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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

    await tester.tap(find.text('去圖鑑換人'));
    await tester.pumpAndSettle();

    // 導回圖鑑（go 收斂 stack）；draw 只在圖鑑翻牌鈕觸發，這裡絕不打 API。
    // （controller 是 autoDispose，離開練習室後不可再讀 state；
    //   drawCalls == 0 已足證換人不再走 draw。）
    expect(
      find.byKey(const ValueKey('practice-test-collection')),
      findsOneWidget,
    );
    expect(api.drawCalls, 0);
  });

  // ── 照片＋Profile 首屏體驗 ───────────────────────────────────────────
  testWidgets('首屏 hero：大照片＋名字/年齡/職業/城市/標籤/自我介紹', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final zoe = practiceGirlProfiles[2];
    final seed = PracticeChatState(
      sessionId: 'hero-test',
      createdAt: DateTime(2026, 6, 25, 10),
      girl: zoe,
      personaId: zoe.personaId,
      personaLabel: '高冷理性型',
      difficulty: 'normal',
      difficultyLabel: '一般',
      messages: const [],
    );
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    expect(find.text('${zoe.displayName}，${zoe.age}'), findsOneWidget);
    expect(find.textContaining(zoe.professionLabel), findsWidgets);
    expect(find.textContaining(zoe.city), findsWidgets);
    expect(find.text(zoe.selfIntro), findsOneWidget);
  });

  testWidgets('聊天 compact header：照片key＋名字/職業＋難度，點開 profile sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final zoe = practiceGirlProfiles[2];
    final seed = PracticeChatState(
      sessionId: 'compact-test',
      createdAt: DateTime(2026, 6, 25, 11),
      girl: zoe,
      personaId: zoe.personaId,
      personaLabel: '高冷理性型',
      difficulty: 'challenge',
      difficultyLabel: '挑戰',
      aiReplyCount: 1,
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗯？'),
      ],
    );
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(
      find.byKey(const ValueKey('practice-profile-avatar')),
      findsOneWidget,
    );
    expect(find.textContaining(zoe.displayName), findsWidgets);
    expect(find.textContaining('挑戰'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('practice-profile-avatar')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('practice-profile-sheet')),
      findsOneWidget,
    );
    expect(find.text(zoe.selfIntro), findsOneWidget);
  });

  testWidgets('拆解失敗後顯示重試與完成，不把使用者卡在輸入列', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final girl = practiceGirlProfiles.first;
    final seed = PracticeChatState(
      sessionId: 'debrief-failed-test',
      createdAt: DateTime(2026, 6, 25, 18),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      aiReplyCount: 1,
      ended: true,
      debriefFailed: true,
      errorMessage: '拆解卡生成失敗，可以再按一次。',
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗯？'),
      ],
    );
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.text('拆解卡暫時沒有產生'), findsOneWidget);
    expect(find.text('再試一次'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('輸入訊息…'), findsNothing);
  });

  testWidgets('不可重試的拆解失敗只顯示完成', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final girl = practiceGirlProfiles.first;
    final seed = PracticeChatState(
      sessionId: 'debrief-limit-test',
      createdAt: DateTime(2026, 6, 25, 18),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      aiReplyCount: 1,
      ended: true,
      debriefFailed: true,
      debriefRetryable: false,
      errorMessage: '這場練習的拆解次數已用完。',
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗯？'),
      ],
    );
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.text('這場練習已結束'), findsOneWidget);
    expect(find.text('再試一次'), findsNothing);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('輸入訊息…'), findsNothing);
  });

  testWidgets('拆解失敗按完成：先持久化 closed 再離開畫面', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final girl = practiceGirlProfiles.first;
    final open = PracticeSession(
      id: 'debrief-failed-close',
      createdAt: DateTime(2026, 6, 25, 18),
      aiReplyCount: 1,
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗯？'),
      ],
      profileId: girl.profileId,
    );
    final sessionRepo = _MemoryPracticeSessionRepository([open]);
    final seed = PracticeChatState(
      sessionId: 'debrief-failed-close',
      createdAt: DateTime(2026, 6, 25, 18),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      aiReplyCount: 1,
      ended: true,
      debriefFailed: true,
      messages: open.messages,
    );
    final controller =
        _SeededPracticeChatController(seed: seed, repository: sessionRepo);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/practice'),
              child: const Text('進練習室'),
            ),
          ),
        ),
        GoRoute(
          path: '/practice',
          builder: (context, state) => const PracticeChatScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('進練習室'));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(sessionRepo.getById('debrief-failed-close')!.closed, true);
    expect(find.text('進練習室'), findsOneWidget); // 已 pop 回上一頁
  });

  testWidgets('拆解失敗按完成但存檔失敗：留在畫面並提示，不靜默漏標記', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final girl = practiceGirlProfiles.first;
    final open = PracticeSession(
      id: 'debrief-failed-close-fail',
      createdAt: DateTime(2026, 6, 25, 18),
      aiReplyCount: 1,
      messages: const [
        PracticeMessage(role: 'user', text: '嗨'),
        PracticeMessage(role: 'ai', text: '嗯？'),
      ],
      profileId: girl.profileId,
    );
    final sessionRepo = _FailingSavePracticeSessionRepository([open]);
    final seed = PracticeChatState(
      sessionId: 'debrief-failed-close-fail',
      createdAt: DateTime(2026, 6, 25, 18),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      aiReplyCount: 1,
      ended: true,
      debriefFailed: true,
      messages: open.messages,
    );
    final controller =
        _SeededPracticeChatController(seed: seed, repository: sessionRepo);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('完成'), findsOneWidget); // 沒離開畫面
    expect(find.text('收尾沒有存檔成功，請再按一次「完成」。'), findsOneWidget);
    expect(
      sessionRepo.getById('debrief-failed-close-fail')!.closed,
      false,
    );
  });

  testWidgets('首屏點大照可看未裁切全圖', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final girl = practiceGirlProfiles[4];
    final seed = PracticeChatState(
      sessionId: 'full-photo-test',
      createdAt: DateTime(2026, 6, 25, 18, 10),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: '自然生活型',
      difficulty: 'normal',
      difficultyLabel: '一般',
    );
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.text('點照片看全圖'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('practice-profile-hero-photo')));
    await tester.pumpAndSettle();

    final fullPhoto =
        find.byKey(const ValueKey('practice-girl-full-photo-viewer'));
    expect(fullPhoto, findsOneWidget);
    expect(find.text('點一下關閉'), findsOneWidget);
    final image = tester.widget<Image>(
      find.descendant(of: fullPhoto, matching: find.byType(Image)).first,
    );
    expect((image.image as AssetImage).assetName, girl.photoAssetPath);
    expect(image.fit, BoxFit.contain);

    await tester.tap(fullPhoto);
    await tester.pumpAndSettle();

    expect(fullPhoto, findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero-photo')),
        findsOneWidget);
  });

  // ── 每日翻牌入口（locked → draw）─────────────────────────────────────────
  /// [surface]／[padding]：模擬不同手機的螢幕與安全區（預設 390×844、無安全區）。
  Future<void> pumpLocked(
    WidgetTester tester, {
    required PracticeChatApiService api,
    Size surface = const Size(390, 844),
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
          practiceChatApiServiceProvider.overrideWithValue(api),
        ],
        // 儀式行為測試 host：練習室內容＋ceremony overlay（掛載點見檔頭註解）。
        child: MaterialApp(
          builder: padding == EdgeInsets.zero
              ? null
              : (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(padding: padding, viewPadding: padding),
                    child: child!,
                  ),
          home: const _CeremonyTestHost(),
        ),
      ),
    );
  }

  testWidgets('點翻牌 CTA → 呼叫 draw、成功後顯示 server 給的對象', (tester) async {
    final zoe = practiceGirlProfiles[2];
    final api = _DrawApi(() async => _drawResultFor(zoe));
    await pumpLocked(tester, api: api);

    expect(find.byKey(const ValueKey('practice-draw-cta')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    await tester.pump(); // revealed

    expect(api.drawCalls, 1);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    expect(find.text('${zoe.displayName}，${zoe.age}'), findsOneWidget);
  });

  testWidgets('翻牌 402 → 顯示升級 CTA、不顯示任何對象、不再重抽', (tester) async {
    final api = _DrawApi(
      () async => throw PracticeDrawUpgradeRequiredException(
        extraCostMessages: 5,
        nextResetAt: '2026-06-27T04:00:00.000Z',
      ),
    );
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('practice-draw-upgrade-primary')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('practice-draw-upgrade')), findsOneWidget);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsNothing);
    // 402 鎖住後主鈕換升級：導引鈕不再出現。
    expect(
      find.byKey(const ValueKey('practice-goto-collection-cta')),
      findsNothing,
    );
  });

  testWidgets('翻牌 429 → 顯示額度錯誤、不顯示任何對象', (tester) async {
    final api = _DrawApi(
      () async => throw PracticeQuotaExceededException('本月額度已用完',
          monthlyRemaining: 0, dailyRemaining: 0),
    );
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('practice-draw-quota')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-draw-upgrade-primary')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsNothing);
    // 429 鎖住後主鈕換方案：導引鈕不再出現。
    expect(
      find.byKey(const ValueKey('practice-goto-collection-cta')),
      findsNothing,
    );
  });

  // ── revealed 狀態下換一位失敗：error banner 要帶升級入口（P2 修補）──────────
  PracticeChatState revealedPreMsgSeed() {
    final girl = practiceGirlProfiles.first;
    return PracticeChatState(
      sessionId: 'revealed-pre',
      createdAt: DateTime(2026, 6, 26, 13),
      girl: girl,
      personaId: girl.personaId,
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
      messages: const [],
    );
  }

  testWidgets('beginner mode toggle reveals temperature meter', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: revealedPreMsgSeed(),
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(
      find.byKey(const ValueKey('practice-learning-mode-standard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-temperature-meter')),
      findsNothing,
    );

    await tester
        .tap(find.byKey(const ValueKey('practice-learning-mode-beginner')));
    await tester.pumpAndSettle();

    expect(controller.currentState.learningMode, PracticeLearningMode.beginner);
    expect(
      find.byKey(const ValueKey('practice-temperature-meter')),
      findsOneWidget,
    );
  });

  testWidgets('SR card enables Game mode without mobile overflow',
      (tester) async {
    final srGirl = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.sr);
    final controller = _SeededPracticeChatController(
      seed: revealedPreMsgSeed().copyWith(
        girl: srGirl,
        personaId: srGirl.personaId,
        personaLabel: 'SR',
      ),
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(
      find.byKey(const ValueKey('practice-learning-mode-standard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-learning-mode-beginner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-learning-mode-game')),
      findsOneWidget,
    );
    expect(find.text('真人感'), findsOneWidget);
    expect(find.text('有提示'), findsOneWidget);
    expect(find.text('SR速約'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('practice-learning-mode-game')));
    await tester.pumpAndSettle();

    expect(controller.currentState.learningMode, PracticeLearningMode.game);
    expect(
      find.byKey(const ValueKey('practice-temperature-meter')),
      findsOneWidget,
    );
    expect(find.text('Game｜她會考你、會給診斷，目標是速約'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-SR card keeps Game visible; locked tap opens intro sheet',
      (tester) async {
    final nGirl = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.n);
    final controller = _SeededPracticeChatController(
      seed: revealedPreMsgSeed().copyWith(
        girl: nGirl,
        personaId: nGirl.personaId,
        personaLabel: 'N',
      ),
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
          practiceGameIntroStoreProvider
              .overrideWithValue(InMemoryPracticeGameIntroStore()),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(
      find.byKey(const ValueKey('practice-learning-mode-game')),
      findsOneWidget,
    );
    expect(find.text('SR解鎖'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('practice-learning-mode-game')));
    await tester.pumpAndSettle();

    // 點鎖定 Game 不切模式，改開教學卡（2026-08-08 拍板：不分 N/R/SR 都要
    // 認識玩法）；絕不掛全域 SnackBar：root messenger 會連點排隊（每顆 4 秒）
    // ＋跨路由殘留成白色橫條（2026-07-10 bug）。
    expect(controller.currentState.learningMode, PracticeLearningMode.standard);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.byKey(const ValueKey('practice-game-intro-sheet')),
      findsOneWidget,
    );
  });

  testWidgets('locked Game intro sheet can reopen after dismiss, never queues',
      (tester) async {
    final nGirl = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.n);
    final controller = _SeededPracticeChatController(
      seed: revealedPreMsgSeed().copyWith(
        girl: nGirl,
        personaId: nGirl.personaId,
        personaLabel: 'N',
      ),
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
          practiceGameIntroStoreProvider
              .overrideWithValue(InMemoryPracticeGameIntroStore()),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    final gameSegment =
        find.byKey(const ValueKey('practice-learning-mode-game'));
    final introSheet = find.byKey(const ValueKey('practice-game-intro-sheet'));

    await tester.tap(gameSegment);
    await tester.pumpAndSettle();
    expect(introSheet, findsOneWidget);

    // 點 barrier 收掉教學卡（已看過），再點鎖定分頁仍可重開，且一次只有一張。
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(introSheet, findsNothing);

    await tester.tap(gameSegment);
    await tester.pumpAndSettle();
    expect(introSheet, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('temperature meter keeps feedback compact and Traditional',
      (tester) async {
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 35,
      familiarityScore: 10,
      relationshipStageLabel: '建立熟悉中',
      lastTemperatureDelta: 3,
      temperatureReason: '回复展现了直接有梗的风格，按住了用户关于直接的调侃，符合角色喜欢有来有回和反打的偏好，有助于升温。',
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('practice-temperature-meter')),
        findsOneWidget);
    expect(find.textContaining('回复'), findsNothing);
    expect(find.textContaining('风格'), findsNothing);
    expect(find.text('建立熟悉中'), findsOneWidget);
    expect(find.textContaining('熟悉度'), findsNothing);
    expect(find.text('這輪有升溫'), findsOneWidget);
  });

  testWidgets('rapid send taps keep only one message submission in flight',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      AiDataSharingConsent.practiceConsentKey: true,
    });
    final replyCompleter = Completer<PracticeChatReply>();
    final api = _MessageApi(
      (_) => replyCompleter.future,
    );
    final controller = _SeededPracticeChatController(
      seed: revealedPreMsgSeed().copyWith(
        learningMode: PracticeLearningMode.beginner,
        temperatureScore: 30,
      ),
      repository: repo,
      api: api,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    // 首屏只有「開始和她聊」CTA；先進對話框才有輸入框。第二拍要推過
    // AppHaptics.strong() 的計時器，免得留下 pending Timer。
    await tester.tap(find.byKey(const ValueKey('practice-start-chat-cta')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    await tester.enterText(find.byType(TextField), 'huhu');
    // 送出鈕現在跟輸入內容連動（空字串灰階），打完字要先讓它重建成可送狀態。
    await tester.pump();
    final sendButton = find.byKey(const ValueKey('practice-send-button'));

    await tester.tap(sendButton);
    await tester.tap(sendButton);
    await tester.pump();

    expect(api.sendCalls, 1);
    expect(controller.currentState.isSending, true);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);

    replyCompleter.complete(
      const PracticeChatReply(
        reply: '嗨，怎麼突然這麼簡短？',
        aiTurnCount: 1,
        sessionComplete: false,
        costDeducted: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.currentState.messages.map((m) => m.role), ['user', 'ai']);
  });

  testWidgets('hint in flight disables the composer (no parallel send)',
      (tester) async {
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 30,
      messages: const [
        PracticeMessage(role: 'user', text: 'hello'),
        PracticeMessage(role: 'ai', text: 'hello back'),
      ],
      aiReplyCount: 1,
      isHintLoading: true,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    // 輸入框／送出鈕都吃 canSend：hint 在途時一律停用，避免平行送出。
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
  });

  testWidgets(
      'turn persistence disables composer and keeps debrief unavailable',
      (tester) async {
    final seed = revealedPreMsgSeed().copyWith(
      messages: const [
        PracticeMessage(role: 'user', text: 'hello'),
        PracticeMessage(role: 'ai', text: 'hello back'),
      ],
      aiReplyCount: 1,
      isPersistingTurn: true,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    expect(find.text('結束練習'), findsNothing);
  });

  // ── W1（2026-08-06）：她已封鎖時沒有可貼句，是合法結果不是失敗 ──
  // 真實事故：模型判斷「沒有任何可貼句能送出」是對的，但契約硬要兩句可貼回覆，
  // 於是判 duplicate_replies → 503。UI 要能畫出這個狀態，而且說明用小字並與
  // 可貼句按鈕明確區隔——它是說明不是話術，不該被複製貼出去。
  testWidgets('hint panel renders the no-pasteable notice instead of buttons',
      (tester) async {
    const reason = '她已經明確要求停止聯絡並封鎖了你，這輪沒有任何適合送出的訊息。';
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 20,
      messages: const [
        PracticeMessage(role: 'user', text: '妳不回我是什麼意思'),
        PracticeMessage(role: 'ai', text: '我說了不要再傳訊息給我'),
      ],
      aiReplyCount: 1,
      hintReplies: const [],
      hintNoPasteableReason: reason,
      hintCoaching: '她已經把界線畫死，再傳任何訊息都只會讓情況更糟。',
      hintUsedCount: 1,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('practice-hint-panel')), findsOneWidget);
    // 沒有可貼句＝不得畫出任何「套用」按鈕
    expect(find.byKey(const ValueKey('practice-hint-reply-0')), findsNothing);
    expect(find.text('套用'), findsNothing);
    // 有原因說明時自動展開，說明本身要看得到
    expect(find.byKey(const ValueKey('practice-hint-no-pasteable')),
        findsOneWidget);
    expect(find.textContaining('沒有任何適合送出的訊息'), findsOneWidget);
    // 死局的正確出口：引導去拆盤，不是原地重按提示（2026-08-08 Eric 拍板）。
    expect(find.byKey(const ValueKey('practice-hint-end-practice')),
        findsOneWidget);
  });

  // ── 2026-08-08：同一輪已判定沒有可貼句還再按提示 → 先確認再扣額度 ──
  // Eric 實測在死局連按兩次，各扣 1 則拿到同一個「收手」判定。她一回新訊息
  // reason 就會清掉（provider 側已修），確認框只擋原地重按。
  testWidgets('no-pasteable 狀態下再按提示先彈確認框，取消不扣額度', (tester) async {
    const reason = '她已經明確要求停止聯絡並封鎖了你，這輪沒有任何適合送出的訊息。';
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 20,
      messages: const [
        PracticeMessage(role: 'user', text: '妳不回我是什麼意思'),
        PracticeMessage(role: 'ai', text: '我說了不要再傳訊息給我'),
      ],
      aiReplyCount: 1,
      hintReplies: const [],
      hintNoPasteableReason: reason,
      hintCoaching: '她已經把界線畫死，再傳任何訊息都只會讓情況更糟。',
      hintUsedCount: 1,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-hint-button')));
    await tester.pumpAndSettle();
    expect(find.text('再要一次提示？'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-hint-recharge-confirm')),
      findsOneWidget,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('再要一次提示？'), findsNothing);
    // 取消＝沒有發出新請求（loading 沒被拉起、used count 不變）。
    expect(controller.currentState.isHintLoading, false);
    expect(controller.currentState.hintUsedCount, 1);
  });

  testWidgets('hint panel can fill the composer with a suggested reply',
      (tester) async {
    const suggestedReply = '我也想聽你多講一點。';
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 42,
      messages: const [
        PracticeMessage(role: 'user', text: 'hello'),
        PracticeMessage(role: 'ai', text: 'hello back'),
      ],
      aiReplyCount: 1,
      hintReplies: const [
        PracticeHintReply(
          type: PracticeHintReplyType.warmUp,
          label: '加分回覆',
          text: suggestedReply,
        ),
        PracticeHintReply(
          type: PracticeHintReplyType.steady,
          label: '不扣分回覆',
          text: '聽起來很棒，哪一段最有趣？',
        ),
      ],
      hintCoaching: '先接住情緒，再丟一個小問題。',
      hintUsedCount: 1,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('practice-hint-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('practice-hint-reply-0')), findsOneWidget);
    expect(find.text('套用'), findsNWidgets(2));
    expect(find.textContaining('接住情緒'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('practice-hint-reply-0')));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, suggestedReply);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.byKey(const ValueKey('practice-hint-collapsed-summary')),
        findsOneWidget);
  });

  testWidgets('game hint panel uses攻略 labels instead of beginner wording',
      (tester) async {
    const gameCoaching = 'Game 心法：現在是測試張力，目標是情緒與投入；下一句開低壓邀約窗口。';
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.game,
      temperatureScore: 76,
      messages: const [
        PracticeMessage(role: 'user', text: '妳講話很有畫面欸'),
        PracticeMessage(role: 'ai', text: '那你倒是說說看看到什麼'),
      ],
      aiReplyCount: 1,
      hintReplies: const [
        PracticeHintReply(
          type: PracticeHintReplyType.warmUp,
          label: '進攻回覆',
          text: '看到妳在測我穩不穩，那我先不照劇本走。',
        ),
        PracticeHintReply(
          type: PracticeHintReplyType.steady,
          label: '保守回覆',
          text: '看到妳很會丟球，我接一下。',
        ),
      ],
      hintCoaching: gameCoaching,
      hintUsedCount: 1,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.text('Game Hint 還剩 4 顆'), findsOneWidget);
    expect(find.text('攻略 1 則'), findsOneWidget);
    expect(find.text('看完整攻略'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('practice-hint-coaching-more')));
    await tester.pumpAndSettle();

    expect(find.text('Game 攻略'), findsOneWidget);
    expect(find.text(gameCoaching), findsWidgets);
  });

  testWidgets('beginner/game Hint generation failure shows retry, no replies',
      (tester) async {
    for (final mode in [
      PracticeLearningMode.beginner,
      PracticeLearningMode.game,
    ]) {
      final seed = revealedPreMsgSeed().copyWith(
        learningMode: mode,
        temperatureScore: 42,
        messages: const [
          PracticeMessage(role: 'user', text: '嗨'),
          PracticeMessage(role: 'ai', text: '你今天怎麼這麼早？'),
        ],
        aiReplyCount: 1,
        hintFailed: true,
        hintReplies: const [],
        hintCoaching: null,
        errorMessage: '提示暫時產生失敗，等一下再試。',
      );
      final controller = _SeededPracticeChatController(
        seed: seed,
        repository: repo,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceChatControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(home: PracticeChatScreen()),
        ),
      );

      expect(find.text('再試一次'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('practice-hint-retry-message')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('practice-hint-reply-0')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('sending an exact applied hint marks the hint type for scoring',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      AiDataSharingConsent.practiceConsentKey: true,
    });
    const suggestedReply = '我也想聽你多講一點。';
    final api = _MessageApi(
      (_) async => const PracticeChatReply(
        reply: '這樣回就自然多了。',
        aiTurnCount: 2,
        sessionComplete: false,
        costDeducted: 0,
        temperature: PracticeTemperature(
          score: 42,
          delta: 0,
          band: 'neutral',
          reason: '維持節奏',
        ),
      ),
    );
    final controller = _SeededPracticeChatController(
      seed: revealedPreMsgSeed().copyWith(
        learningMode: PracticeLearningMode.beginner,
        temperatureScore: 42,
        messages: const [
          PracticeMessage(role: 'user', text: 'hello'),
          PracticeMessage(role: 'ai', text: 'hello back'),
        ],
        aiReplyCount: 1,
        hintReplies: const [
          PracticeHintReply(
            type: PracticeHintReplyType.warmUp,
            label: '加分回覆',
            text: suggestedReply,
          ),
          PracticeHintReply(
            type: PracticeHintReplyType.steady,
            label: '不扣分回覆',
            text: '聽起來很棒，哪一段最有趣？',
          ),
        ],
        hintCoaching: '先接住情緒，再丟一個小問題。',
        hintUsedCount: 1,
      ),
      repository: repo,
      api: api,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-hint-reply-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-send-button')));
    await tester.pumpAndSettle();

    expect(api.sendCalls, 1);
    expect(api.lastAppliedHintType, PracticeHintReplyType.warmUp);
    expect(api.lastAppliedHintText, suggestedReply);
    expect(api.lastTurns.last.text, suggestedReply);
  });

  testWidgets(
      'editing an applied hint before sending keeps hint source for scoring',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      AiDataSharingConsent.practiceConsentKey: true,
    });
    const suggestedReply = '我也想聽你多講一點。';
    final api = _MessageApi(
      (_) async => const PracticeChatReply(
        reply: '有改過就算自己的回覆。',
        aiTurnCount: 2,
        sessionComplete: false,
        costDeducted: 0,
      ),
    );
    final controller = _SeededPracticeChatController(
      seed: revealedPreMsgSeed().copyWith(
        learningMode: PracticeLearningMode.beginner,
        temperatureScore: 42,
        messages: const [
          PracticeMessage(role: 'user', text: 'hello'),
          PracticeMessage(role: 'ai', text: 'hello back'),
        ],
        aiReplyCount: 1,
        hintReplies: const [
          PracticeHintReply(
            type: PracticeHintReplyType.warmUp,
            label: '加分回覆',
            text: suggestedReply,
          ),
          PracticeHintReply(
            type: PracticeHintReplyType.steady,
            label: '不扣分回覆',
            text: '聽起來很棒，哪一段最有趣？',
          ),
        ],
        hintCoaching: '先接住情緒，再丟一個小問題。',
        hintUsedCount: 1,
      ),
      repository: repo,
      api: api,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-hint-reply-0')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '$suggestedReply！');
    await tester.tap(find.byKey(const ValueKey('practice-send-button')));
    await tester.pumpAndSettle();

    expect(api.sendCalls, 1);
    expect(api.lastAppliedHintType, PracticeHintReplyType.warmUp);
    expect(api.lastAppliedHintText, suggestedReply);
    expect(api.lastTurns.last.text, '$suggestedReply！');
  });

  testWidgets('session change clears input and cannot send old Hint lineage',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      AiDataSharingConsent.practiceConsentKey: true,
    });
    const suggestedReply = PracticeHintReply(
      type: PracticeHintReplyType.warmUp,
      label: '加分回覆',
      text: '妳這個酒吧雷達是只對有故事的店有效嗎？',
      hintRequestId: 'hint-session-a',
      decision: PracticeHintDecision(
        phase: '建立互動',
        targetVariable: '投入感',
        move: '用 callback 延伸她的品味',
        rationale: '讓她補充自己的判斷，形成交換感',
        inviteRoute: 'hold',
      ),
    );
    final api = _MessageApi(
      (_) async => const PracticeChatReply(
        reply: 'B 的新回覆',
        aiTurnCount: 2,
        sessionComplete: false,
        costDeducted: 0,
      ),
    );
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 42,
      messages: const [
        PracticeMessage(role: 'user', text: 'A 開場'),
        PracticeMessage(role: 'ai', text: 'A 對方回覆'),
      ],
      aiReplyCount: 1,
      hintReplies: const [
        suggestedReply,
        PracticeHintReply(
          type: PracticeHintReplyType.steady,
          label: '穩住回覆',
          text: '我先記住這間，之後再跟妳交換口袋名單。',
        ),
      ],
      hintCoaching: '延伸 A 的酒吧話題。',
      hintUsedCount: 1,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
      api: api,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-hint-reply-0')));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      suggestedReply.text,
    );

    controller.resumeSession(PracticeSession(
      id: 'widget-session-b',
      createdAt: DateTime(2026, 7, 11, 22),
      messages: const [
        PracticeMessage(role: 'user', text: 'B 開場'),
        PracticeMessage(role: 'ai', text: 'B 對方回覆'),
      ],
      aiReplyCount: 1,
      profileId: seed.girl?.profileId,
      practiceMode: 'beginner',
      temperatureScore: 40,
    ));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    expect(controller.currentState.canSend, true);
    await tester.enterText(find.byType(TextField), 'B 自己寫的新回覆');
    await tester.pump();
    expect(
      tester
          .widget<GestureDetector>(
            find.byKey(const ValueKey('practice-send-button')),
          )
          .onTap,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('practice-send-button')));
    await tester.pumpAndSettle();

    expect(api.sendCalls, 1);
    expect(api.lastAppliedHintType, isNull);
    expect(api.lastAppliedHintText, isNull);
    expect(api.lastTurns.last.text, 'B 自己寫的新回覆');
  });

  testWidgets('failed exact hint send keeps marker for retry', (tester) async {
    SharedPreferences.setMockInitialValues({
      AiDataSharingConsent.practiceConsentKey: true,
    });
    const suggestedReply = '我喜歡你剛剛那個反應，有點可愛。';
    var attempts = 0;
    final api = _MessageApi((_) async {
      attempts++;
      if (attempts == 1) {
        throw PracticeGenerationFailedException('boom');
      }
      return const PracticeChatReply(
        reply: '這次成功了。',
        aiTurnCount: 2,
        sessionComplete: false,
        costDeducted: 0,
        temperature: PracticeTemperature(
          score: 42,
          delta: 0,
          band: 'neutral',
          reason: '套用提示回覆，維持不降溫',
        ),
      );
    });
    final controller = _SeededPracticeChatController(
      seed: revealedPreMsgSeed().copyWith(
        learningMode: PracticeLearningMode.beginner,
        temperatureScore: 42,
        messages: const [
          PracticeMessage(role: 'user', text: 'hello'),
          PracticeMessage(role: 'ai', text: 'hello back'),
        ],
        aiReplyCount: 1,
        hintReplies: const [
          PracticeHintReply(
            type: PracticeHintReplyType.warmUp,
            label: '加分回覆',
            text: suggestedReply,
          ),
          PracticeHintReply(
            type: PracticeHintReplyType.steady,
            label: '不扣分回覆',
            text: '聽起來很棒，哪一段最有趣？',
          ),
        ],
        hintCoaching: '先接住情緒，再丟一個小問題。',
        hintUsedCount: 1,
      ),
      repository: repo,
      api: api,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-hint-reply-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('practice-send-button')));
    await tester.pumpAndSettle();

    expect(api.sendCalls, 1);
    expect(api.lastAppliedHintType, PracticeHintReplyType.warmUp);
    expect(api.lastAppliedHintText, suggestedReply);

    await tester.tap(find.byKey(const ValueKey('practice-send-button')));
    await tester.pumpAndSettle();

    expect(api.sendCalls, 2);
    expect(api.lastAppliedHintType, PracticeHintReplyType.warmUp);
    expect(api.lastAppliedHintText, suggestedReply);
    expect(api.lastTurns.last.text, suggestedReply);
  });

  testWidgets('hint panel can collapse and expand after a hint is generated',
      (tester) async {
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 42,
      messages: const [
        PracticeMessage(role: 'user', text: '妳這樣會很常得罪人吧'),
        PracticeMessage(role: 'ai', text: '還好啊，我又不是沒事就亂噴人。'),
      ],
      aiReplyCount: 1,
      hintReplies: const [
        PracticeHintReply(
          type: PracticeHintReplyType.warmUp,
          label: '升溫回覆',
          text: '那你覺得我是會得罪你，還是你已經準備好被我得罪了？',
        ),
        PracticeHintReply(
          type: PracticeHintReplyType.steady,
          label: '穩住回覆',
          text: '至少我對有興趣的人還是很溫柔的喔。',
        ),
      ],
      hintCoaching: '她剛剛把你的吐槽反打回來，下一句要接住她的幽默。',
      hintUsedCount: 2,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('practice-hint-reply-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('practice-hint-toggle-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('practice-hint-reply-0')), findsNothing);
    expect(find.byKey(const ValueKey('practice-hint-collapsed-summary')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('practice-hint-toggle-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('practice-hint-reply-0')), findsOneWidget);
  });

  testWidgets('requesting hint dismisses the composer keyboard',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      AiDataSharingConsent.practiceConsentKey: true,
    });
    final api = _HintApi(
      const PracticeHintResult(
        replies: [
          PracticeHintReply(
            type: PracticeHintReplyType.warmUp,
            label: 'warm',
            text: 'warm reply',
          ),
          PracticeHintReply(
            type: PracticeHintReplyType.steady,
            label: 'steady',
            text: 'steady reply',
          ),
        ],
        coaching: 'read the latest reply, then answer.',
        costDeducted: 0,
        hintUsedCount: 1,
        qualitySchemaVersion: kPracticeHintQualitySchemaVersion,
      ),
    );
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 42,
      messages: const [
        PracticeMessage(role: 'user', text: 'first line'),
        PracticeMessage(role: 'ai', text: 'latest her line'),
      ],
      aiReplyCount: 1,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
      api: api,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'draft');
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byKey(const ValueKey('practice-hint-button')));
    await tester.pumpAndSettle();

    expect(api.hintCalls, 1);
    expect(find.byKey(const ValueKey('practice-hint-reply-0')), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('hint panel auto-expands when a generated hint arrives',
      (tester) async {
    const warmReply = PracticeHintReply(
      type: PracticeHintReplyType.warmUp,
      label: 'warm',
      text: 'warm reply',
    );
    final api = _HintApi(
      const PracticeHintResult(
        replies: [
          warmReply,
          PracticeHintReply(
            type: PracticeHintReplyType.steady,
            label: 'steady',
            text: 'steady reply',
          ),
        ],
        coaching: 'she answered the latest turn; you can reply lightly.',
        costDeducted: 0,
        hintUsedCount: 1,
        qualitySchemaVersion: kPracticeHintQualitySchemaVersion,
      ),
    );
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 42,
      messages: const [
        PracticeMessage(role: 'user', text: 'first line'),
        PracticeMessage(role: 'ai', text: 'latest her line'),
      ],
      aiReplyCount: 1,
      hintReplies: const [],
      hintCoaching: null,
      hintUsedCount: 0,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
      api: api,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('practice-hint-reply-0')), findsNothing);
    expect(find.byKey(const ValueKey('practice-hint-toggle-button')),
        findsNothing);

    await controller.requestHint();
    await tester.pumpAndSettle();

    expect(api.hintCalls, 1);
    expect(find.byKey(const ValueKey('practice-hint-toggle-button')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('practice-hint-reply-0')), findsOneWidget);
    expect(find.text(warmReply.text), findsOneWidget);
  });

  testWidgets('hint panel disables request button after fifth hint',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      AiDataSharingConsent.practiceConsentKey: true,
    });
    final api = _HintApi(
      const PracticeHintResult(
        replies: [
          PracticeHintReply(
            type: PracticeHintReplyType.warmUp,
            label: 'warm',
            text: 'warm reply',
          ),
          PracticeHintReply(
            type: PracticeHintReplyType.steady,
            label: 'steady',
            text: 'steady reply',
          ),
        ],
        coaching: 'read the latest reply, then answer.',
        costDeducted: 0,
        hintUsedCount: 5,
        qualitySchemaVersion: kPracticeHintQualitySchemaVersion,
      ),
    );
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 35,
      messages: const [
        PracticeMessage(role: 'user', text: 'first line'),
        PracticeMessage(role: 'ai', text: 'latest her line'),
      ],
      aiReplyCount: 1,
      hintReplies: const [
        PracticeHintReply(
          type: PracticeHintReplyType.warmUp,
          label: '升溫回覆',
          text: '我喜歡你剛剛那個反應，有點可愛。',
        ),
        PracticeHintReply(
          type: PracticeHintReplyType.steady,
          label: '穩住回覆',
          text: '那我慢慢聽你說。',
        ),
      ],
      hintCoaching: '先接住她的情緒，再丟一個好回的小問題。',
      hintUsedCount: 5,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
      api: api,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.text('Hint 還剩 0 顆'), findsOneWidget);
    expect(find.text('本輪已用完'), findsOneWidget);
    expect(find.textContaining('本輪提示已用完'), findsOneWidget);

    final button = tester
        .widget<TextButton>(find.byKey(const ValueKey('practice-hint-button')));
    expect(button.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('practice-hint-button')));
    await tester.pumpAndSettle();

    expect(api.hintCalls, 0);
  });

  testWidgets('hint coaching can open a full teaching sheet', (tester) async {
    const longCoaching =
        '她剛剛把你的吐槽反打回來，重點不是解釋自己沒有得罪人，而是順著她的幽默承接，讓互動保有輕鬆感，再丟一個低壓問題讓她願意繼續接話。';
    final seed = revealedPreMsgSeed().copyWith(
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 42,
      messages: const [
        PracticeMessage(role: 'user', text: '妳這樣會很常得罪人吧'),
        PracticeMessage(role: 'ai', text: '還好啊，我又不是沒事就亂噴人。'),
      ],
      aiReplyCount: 1,
      hintReplies: const [
        PracticeHintReply(
          type: PracticeHintReplyType.warmUp,
          label: '升溫回覆',
          text: '那你覺得我是會得罪你，還是你已經準備好被我得罪了？',
        ),
        PracticeHintReply(
          type: PracticeHintReplyType.steady,
          label: '穩住回覆',
          text: '至少我對有興趣的人還是很溫柔的喔。',
        ),
      ],
      hintCoaching: longCoaching,
      hintUsedCount: 2,
    );
    final controller = _SeededPracticeChatController(
      seed: seed,
      repository: repo,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-hint-coaching-more')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('practice-hint-coaching-sheet')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('practice-hint-coaching-sheet-text')),
        findsOneWidget);
    expect(find.text(longCoaching), findsWidgets);
  });

  // Task 5：換一位 gating（Free 導 paywall／扣費確認／額度鎖死）已整組搬到
  // 角色圖鑑翻牌鈕，行為測試見 practice_collection_screen_test.dart；
  // 這裡只留「revealed 帶 draw 旗標時 error banner 仍導升級」的殘餘 UI 保護
  // （state 由 draft 還原時仍可能帶旗標）。
  testWidgets('revealed 帶 draw 402 旗標（draft 還原）→ error banner 顯升級 CTA',
      (tester) async {
    final seed = revealedPreMsgSeed().copyWith(
      drawUpgradeRequired: true,
      errorMessage: '升級後每天可以翻更多陪練女孩。',
    );
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    // 原對象仍在（revealed、girl 不漂移），banner 有升級入口。
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    expect(find.text('升級'), findsOneWidget);
  });

  testWidgets('revealed 帶 draw 429 旗標（draft 還原）→ error banner 顯升級 CTA',
      (tester) async {
    final seed = revealedPreMsgSeed().copyWith(
      drawQuotaExceeded: true,
      errorMessage: '本月額度已用完',
    );
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    expect(find.text('升級'), findsOneWidget);
  });

  // Onboarding 第 2 步：翻牌撞牆的升級入口帶 PaywallEntry.practiceDraw（付費頁換
  // 翻牌大標、漏斗記 practice_draw）；共用額度用完、續聊被擋照舊一般入口。
  group('翻牌撞牆的付費頁入口', () {
    Future<void> pumpRouted(WidgetTester tester, PracticeChatState seed) async {
      final controller =
          _SeededPracticeChatController(seed: seed, repository: repo);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const PracticeChatScreen(),
          ),
          GoRoute(
            path: '/paywall',
            builder: (context, state) => Scaffold(
              body: Text(
                'entry:${PaywallEntry.fromRouteExtra(state.extra).name}',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceChatControllerProvider.overrideWith((ref) => controller),
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
    }

    Future<void> tapAndLand(WidgetTester tester, Finder target) async {
      await tester.tap(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    PracticeChatState lockedDrawSeed({
      bool upgradeRequired = false,
      bool quotaExceeded = false,
    }) =>
        PracticeChatState(
          sessionId: 'draw-entry-locked',
          createdAt: DateTime(2026, 10, 27, 13),
          girl: null,
          personaId: '',
          personaLabel: '',
          difficulty: 'normal',
          difficultyLabel: '一般',
          drawStatus: PracticeDrawStatus.locked,
          drawUpgradeRequired: upgradeRequired,
          drawQuotaExceeded: quotaExceeded,
        );

    testWidgets('錯誤橫幅：翻牌 402 旗標 → practiceDraw', (tester) async {
      await pumpRouted(
        tester,
        revealedPreMsgSeed().copyWith(
          drawUpgradeRequired: true,
          errorMessage: '升級後每天可以翻更多陪練女孩。',
        ),
      );
      await tapAndLand(tester, find.text('升級'));
      expect(find.text('entry:practiceDraw'), findsOneWidget);
    });

    testWidgets('錯誤橫幅：翻牌 429 旗標 → practiceDraw', (tester) async {
      await pumpRouted(
        tester,
        revealedPreMsgSeed().copyWith(
          drawQuotaExceeded: true,
          errorMessage: '今天的翻牌用完了，每天中午 12 點恢復；也可以升級。',
        ),
      );
      await tapAndLand(tester, find.text('升級'));
      expect(find.text('entry:practiceDraw'), findsOneWidget);
    });

    testWidgets('錯誤橫幅：共用額度用完 → 一般入口', (tester) async {
      await pumpRouted(
        tester,
        revealedPreMsgSeed().copyWith(
          quotaExceeded: true,
          errorMessage: '本月額度已用完',
        ),
      );
      await tapAndLand(tester, find.text('升級'));
      expect(find.text('entry:general'), findsOneWidget);
    });

    testWidgets('錯誤橫幅：續聊同一位被擋 → 一般入口', (tester) async {
      await pumpRouted(
        tester,
        revealedPreMsgSeed().copyWith(
          upgradeRequired: true,
          errorMessage: '升級後可以續聊同一位。',
        ),
      );
      await tapAndLand(tester, find.text('升級'));
      expect(find.text('entry:general'), findsOneWidget);
    });

    testWidgets('錯誤橫幅：共用額度與翻牌旗標同時在 → 一般入口（不確定是翻牌就不換大標）', (tester) async {
      await pumpRouted(
        tester,
        revealedPreMsgSeed().copyWith(
          quotaExceeded: true,
          drawQuotaExceeded: true,
          errorMessage: '本月額度已用完',
        ),
      );
      await tapAndLand(tester, find.text('升級'));
      expect(find.text('entry:general'), findsOneWidget);
    });

    testWidgets('翻牌鎖住（402）：主鈕帶 practiceDraw', (tester) async {
      await pumpRouted(tester, lockedDrawSeed(upgradeRequired: true));
      await tapAndLand(
        tester,
        find.byKey(const ValueKey('practice-draw-upgrade-primary')),
      );
      expect(find.text('entry:practiceDraw'), findsOneWidget);
    });

    testWidgets('翻牌鎖住（402）：「升級解鎖」帶 practiceDraw', (tester) async {
      await pumpRouted(tester, lockedDrawSeed(upgradeRequired: true));
      await tapAndLand(
        tester,
        find.byKey(const ValueKey('practice-draw-upgrade')),
      );
      expect(find.text('entry:practiceDraw'), findsOneWidget);
    });

    testWidgets('翻牌鎖住（429）：「查看方案」帶 practiceDraw，沒訊息時講中午 12 點恢復',
        (tester) async {
      await pumpRouted(tester, lockedDrawSeed(quotaExceeded: true));
      expect(
        find.text('今天的翻牌用完了，每天中午 12 點恢復；也可以升級。'),
        findsOneWidget,
      );
      await tapAndLand(
        tester,
        find.byKey(const ValueKey('practice-draw-upgrade-primary')),
      );
      expect(find.text('entry:practiceDraw'), findsOneWidget);
    });
  });

  // Onboarding 第 3 步補（Eric 2026-10-27「照預設」）：練習對話撞到共用額度時，橫幅照
  // 目前方案自己組字，跟開場救星、新話題同一個做法——先講恢復時間，本月或今日照伺服器
  // 說的；免費、Starter 再補升級，Essential 只講恢復時間、鈕寫「查看方案」。伺服器那句
  // 不分方案（本月那句沒寫恢復時間），不拿來顯示。走真的送出路徑。
  group('練習對話撞到共用額度：橫幅照目前方案講恢復時間', () {
    const serverMonthly = '本月額度已用完，升級方案可取得更多分析與教練額度。';
    const serverDaily = '今日額度已用完，每天早上 8 點恢復；也可以升級取得更多額度。';

    Future<void> sendIntoQuota(
      WidgetTester tester, {
      required String tier,
      required bool monthly,
    }) async {
      SharedPreferences.setMockInitialValues({
        AiDataSharingConsent.practiceConsentKey: true,
      });
      final api = _MessageApi(
        (_) async => throw PracticeQuotaExceededException(
          monthly ? serverMonthly : serverDaily,
          monthlyRemaining: monthly ? 0 : 20,
          dailyRemaining: 0,
          isMonthly: monthly,
        ),
      );
      final controller = _SeededPracticeChatController(
        seed: revealedPreMsgSeed(),
        repository: repo,
        api: api,
      );
      final limits = SubscriptionTierHelper.limitsFor(tier);

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceChatControllerProvider.overrideWith((ref) => controller),
            subscriptionProvider.overrideWith(
              (ref) => _SeededSubscriptionNotifier(
                SubscriptionState(
                  tier: tier,
                  monthlyLimit: limits.monthly,
                  dailyLimit: limits.daily,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: PracticeChatScreen()),
        ),
      );

      // 第二拍推過 AppHaptics.strong() 的計時器，免得留下 pending Timer。
      await tester.tap(find.byKey(const ValueKey('practice-start-chat-cta')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.enterText(find.byType(TextField), '嗨');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('practice-send-button')));
      await tester.pumpAndSettle();

      expect(api.sendCalls, 1);
      expect(controller.currentState.quotaExceeded, true);
      expect(controller.currentState.quotaExceededMonthly, monthly);
    }

    const upgradeableMonthly = '本月額度不足，每月 1 號早上 8 點恢復；也可以升級取得更多練習與分析額度。';
    const upgradeableDaily = '今日額度不足，每天早上 8 點恢復；也可以升級取得更多額度。';
    final cases = <({String tier, bool monthly, String text, String button})>[
      (
        tier: SubscriptionTierHelper.free,
        monthly: true,
        text: upgradeableMonthly,
        button: '升級',
      ),
      (
        tier: SubscriptionTierHelper.free,
        monthly: false,
        text: upgradeableDaily,
        button: '升級',
      ),
      (
        tier: SubscriptionTierHelper.starter,
        monthly: true,
        text: upgradeableMonthly,
        button: '升級',
      ),
      (
        tier: SubscriptionTierHelper.starter,
        monthly: false,
        text: upgradeableDaily,
        button: '升級',
      ),
      (
        tier: SubscriptionTierHelper.essential,
        monthly: true,
        text: '本月額度不足，每月 1 號早上 8 點恢復。',
        button: '查看方案',
      ),
      (
        tier: SubscriptionTierHelper.essential,
        monthly: false,
        text: '今日額度不足，每天早上 8 點恢復。',
        button: '查看方案',
      ),
    ];

    for (final c in cases) {
      testWidgets('${c.tier}・${c.monthly ? '每月' : '每日'}：${c.text}',
          (tester) async {
        await sendIntoQuota(tester, tier: c.tier, monthly: c.monthly);

        expect(find.text(c.text), findsOneWidget);
        expect(find.text(serverMonthly), findsNothing);
        expect(find.text(serverDaily), findsNothing);
        expect(find.text(c.button), findsOneWidget);
        if (c.tier == SubscriptionTierHelper.essential) {
          expect(c.text, isNot(contains('升級')));
          expect(find.text('升級'), findsNothing);
        }
        // 失敗觸覺若有第二下（90ms 間隔），推過去免得留下計時器。
        await tester.pump(const Duration(milliseconds: 200));
      });
    }
  });

  // ── 翻牌揭曉儀式 overlay（Batch 4 commit 2）─────────────────────────────
  testWidgets('儀式：seeded revealed（無抽牌轉場）→ overlay 休眠、不顯翻牌卡', (tester) async {
    final seed = revealedPreMsgSeed();
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: _CeremonyTestHost()),
      ),
    );

    // 進房就是 revealed（草稿還原情境）：儀式不得誤觸發。
    expect(find.byKey(_ceremonyBackKey), findsNothing);
    expect(find.byKey(_ceremonyFrontKey), findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
  });

  testWidgets('Task 4b：練習室本體不再掛儀式 overlay（抽牌中也無卡背，掛載點唯一在圖鑑）', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 刻意 pump「純 PracticeChatScreen」（production 組合，非 _CeremonyTestHost）。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
          practiceChatApiServiceProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.byType(PracticeDrawCeremony), findsNothing);

    // Task 5 後練習室無翻牌觸發點：直接呼叫 controller 進 drawing。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PracticeChatScreen)),
    );
    unawaited(
      container
          .read(practiceChatControllerProvider.notifier)
          .drawNewPracticeGirl(),
    );
    await tester.pump(); // drawing
    await tester.pump(const Duration(milliseconds: 300));

    // 抽牌中：本頁不再浮現儀式卡背（儀式只在圖鑑頁揭曉）。
    expect(find.byKey(_ceremonyBackKey), findsNothing);

    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
  });

  testWidgets('revealed 換一位等待 draw 時保留現有 hero，由翻牌 overlay 接管', (tester) async {
    final seed = revealedPreMsgSeed();
    final nextGirl = practiceGirlProfiles[3];
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo, api: api);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: _CeremonyTestHost()),
      ),
    );

    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);

    // Task 5 後換一位入口在圖鑑；host 測試鈕直呼 draw 觸發同一條路徑。
    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(controller.currentState.drawStatus, PracticeDrawStatus.drawing);
    expect(find.byKey(const ValueKey('practice-locked-entry')), findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    expect(find.byKey(_ceremonyBackKey), findsOneWidget);

    completer.complete(_drawResultFor(nextGirl));
    await finishCeremony(tester);
    expect(controller.currentState.girl!.profileId, nextGirl.profileId);
  });

  testWidgets('儀式：抽牌中浮現神秘卡背（不洩漏身份、無正面）', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    await tester.pump(const Duration(milliseconds: 160)); // 入場推進（0.1 s 起淡入）

    expect(find.byKey(_ceremonyBackKey), findsOneWidget);
    expect(find.byKey(_ceremonyFrontKey), findsNothing);

    // 收尾：完成抽牌、收卡收掉 overlay，避免殘留 ticker。
    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await finishCeremony(tester);
  });

  testWidgets('儀式（E3）：抽牌中卡背不再用金幣 auto_awesome 圖示', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    await tester.pump(const Duration(milliseconds: 160)); // 入場推進

    final back = find.byKey(_ceremonyBackKey);
    expect(back, findsOneWidget);
    // gap #2：金幣星芒（auto_awesome）退場；V3 卡背是四張素材依稀有度疊色，不用圖示。
    expect(
      find.descendant(of: back, matching: find.byIcon(Icons.auto_awesome)),
      findsNothing,
    );

    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await finishCeremony(tester);
  });

  testWidgets('儀式（V3）：揭曉走完停住等點擊，點擊收卡後 overlay 收掉、露出 hero（名字不重複）',
      (tester) async {
    final zoe = practiceGirlProfiles[2];
    final api = _DrawApi(() async => _drawResultFor(zoe));
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle(); // 揭曉走完：停在 holding（畫面靜止，pumpAndSettle 收斂）

    expect(find.byKey(_ceremonyFrontKey), findsOneWidget);
    expect(find.byKey(_ceremonyHintKey), findsOneWidget);
    expect(find.text('點擊任意處繼續'), findsOneWidget);
    // 名字只在 hero 出現一處（儀式正面不得用「名字，年齡」精確字串撞測試）。
    expect(find.text('${zoe.displayName}，${zoe.age}'), findsOneWidget);

    // 停住不會自己收掉：再等 10 秒正面卡仍在。
    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(_ceremonyFrontKey), findsOneWidget);

    await tester.tap(find.byKey(_ceremonyContinueKey));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-archive-orb')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_ceremonyBackKey), findsNothing);
    expect(find.byKey(_ceremonyFrontKey), findsNothing);
    expect(
        find.byKey(const ValueKey('practice-draw-ceremony-dim')), findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    expect(find.text('${zoe.displayName}，${zoe.age}'), findsOneWidget);
  });

  testWidgets('儀式：reduce-motion 跳過 3D 翻面、reveal 直接露出 hero', (tester) async {
    final zoe = practiceGirlProfiles[2];
    final api = _DrawApi(() async => _drawResultFor(zoe));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
          practiceChatApiServiceProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          // 把 disableAnimations 注入到 MaterialApp 自身 MediaQuery 之下，
          // 讓底下的 PracticeChatScreen 讀得到。
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const _CeremonyTestHost(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();

    // 跳過翻面：正面卡不出現、不停住，直接露出 hero。
    expect(find.byKey(_ceremonyFrontKey), findsNothing);
    expect(find.byKey(_ceremonyContinueKey), findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
  });

  // ── 抽牌等待期間卡背持續微動（Batch 4.6）────────────────────────────────
  double waitMotionDy(WidgetTester tester) {
    return tester
        .widget<Transform>(
          find.byKey(const ValueKey('practice-draw-ceremony-waiting-motion')),
        )
        .transform
        .getTranslation()
        .y;
  }

  testWidgets('儀式：抽牌等待期間卡背持續微動（float 隨時間變化、不洩漏正面）', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // 進入 drawing：啟動入場＋等待微動
    await tester.pump(const Duration(milliseconds: 600)); // intro 收斂、等待持續
    final y1 = waitMotionDy(tester);
    await tester.pump(const Duration(milliseconds: 650)); // 等待相位再推進
    final y2 = waitMotionDy(tester);

    // 等待期間卡背確實在浮動（兩個取樣時間的 float 位移明顯不同）。
    expect((y1 - y2).abs(), greaterThan(0.5));
    // 等待期間只顯卡背、絕不洩漏正面身份。
    expect(find.byKey(_ceremonyBackKey), findsOneWidget);
    expect(find.byKey(_ceremonyFrontKey), findsNothing);

    // 收尾：成功揭曉、收卡收掉 overlay（等待微動須已停，pumpAndSettle 才收斂）。
    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await finishCeremony(tester);
    expect(find.byKey(_ceremonyBackKey), findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
  });

  testWidgets('儀式：等待中 402 回來 → 停止微動、不誤觸成功揭曉（pumpAndSettle 收斂）', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing：等待微動啟動
    await tester.pump(const Duration(milliseconds: 600)); // 微動進行中

    // 等待途中 402：停止微動、走兜底淡出，不得翻面慶祝。
    completer.completeError(
      PracticeDrawUpgradeRequiredException(
        extraCostMessages: 5,
        nextResetAt: '2026-06-27T04:00:00.000Z',
      ),
    );
    // 若等待微動沒被停掉，這個 pumpAndSettle 會因 repeat 永不收斂而 timeout。
    await tester.pumpAndSettle();

    expect(find.byKey(_ceremonyFrontKey), findsNothing);
    expect(find.byKey(_ceremonyContinueKey), findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsNothing);
    expect(find.byKey(const ValueKey('practice-draw-upgrade')), findsOneWidget);
  });

  testWidgets('儀式：reduce-motion 等待期間卡背靜止（不啟動持續微動）', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
          practiceChatApiServiceProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const _CeremonyTestHost(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing（reduce-motion：卡背直接定住）
    final y1 = waitMotionDy(tester);
    await tester.pump(const Duration(milliseconds: 220));
    final y2 = waitMotionDy(tester);

    // reduce-motion：不啟動持續微動，float 位移恆定（靜止）。
    expect(y1, equals(y2));
    expect(find.byKey(_ceremonyBackKey), findsOneWidget);
    expect(find.byKey(_ceremonyFrontKey), findsNothing);

    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
  });

  // ── V3 單次翻牌（第一刀：結構與節奏）────────────────────────────────────
  Future<void> drawToReveal(
    WidgetTester tester, {
    required Completer<PracticeDrawResult> completer,
    required PracticeGirlProfile girl,
  }) async {
    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    await tester.pump(const Duration(milliseconds: 600)); // 卡背入場走完、等待微動
    completer.complete(_drawResultFor(girl));
    await tester.pump(); // 進入 revealing：_reveal.forward(from:0)
  }

  double opacityAbove(WidgetTester tester, Finder finder) => tester
      .widget<Opacity>(
        find.ancestor(of: finder, matching: find.byType(Opacity)).first,
      )
      .opacity;

  testWidgets('V3：全程只翻一次——翻牌峰值前只有卡背，正面出現後卡背不再回來', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester,
        completer: completer, girl: practiceGirlProfiles[2]);

    var elapsed = 0.0;
    var sawFront = false;
    while (elapsed <= PracticeRevealTiming.revealMs) {
      final back = find.byKey(_ceremonyBackKey).evaluate().isNotEmpty;
      final front = find.byKey(_ceremonyFrontKey).evaluate().isNotEmpty;
      expect(back != front, isTrue, reason: '同一時間只畫一面（$elapsed ms）');
      if (front) {
        sawFront = true;
      } else {
        expect(sawFront, isFalse, reason: '正面出現後又翻回卡背（$elapsed ms）');
      }
      if (elapsed < PracticeRevealTiming.flipPeakMs - 50) {
        expect(back, isTrue, reason: '翻牌峰值前只有卡背（$elapsed ms）');
      }
      await tester.pump(const Duration(milliseconds: 50));
      elapsed += 50;
    }
    expect(sawFront, isTrue);
    await finishCeremony(tester);
  });

  testWidgets('V3：蓄力段（0.6 s）仍是卡背，不立即翻面', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester,
        completer: completer, girl: practiceGirlProfiles[2]);

    await tester.pump(revealAt(PracticeRevealTiming.chargeEndMs));
    expect(find.byKey(_ceremonyBackKey), findsOneWidget);
    expect(find.byKey(_ceremonyFrontKey), findsNothing);

    await finishCeremony(tester);
  });

  testWidgets('V3：資訊欄等翻牌落定後才浮出（1.85 s 前透明）', (tester) async {
    final girl = practiceGirlProfiles[2];
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester, completer: completer, girl: girl);

    const infoKey = ValueKey('practice-draw-ceremony-info');
    await tester.pump(revealAt(PracticeRevealTiming.flipEndMs));
    expect(find.byKey(_ceremonyFrontKey), findsOneWidget);
    expect(opacityAbove(tester, find.byKey(infoKey)), 0);

    await tester.pump(revealAt(
        PracticeRevealTiming.infoEndMs - PracticeRevealTiming.flipEndMs + 20));
    expect(opacityAbove(tester, find.byKey(infoKey)), 1);
    // 資訊欄仍不得用 hero 的「名字，年齡」精確字串（仍只在 hero 一處）。
    expect(find.text('${girl.displayName}，${girl.age}'), findsOneWidget);

    await finishCeremony(tester);
  });

  testWidgets('V3：點擊提示 2.4 s 起淡入、同時從下方 6 px 浮上來，停住時定在原位', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester,
        completer: completer, girl: practiceGirlProfiles[2]);

    double hintDy() => tester
        .widget<Transform>(
          find
              .ancestor(
                of: find.byKey(_ceremonyHintKey),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .getTranslation()
        .y;

    await tester.pump(revealAt(PracticeRevealTiming.hintStartMs + 60));
    expect(hintDy(), inExclusiveRange(0, 6)); // 還在下方，正往上浮
    expect(
      opacityAbove(tester, find.byKey(_ceremonyHintKey)),
      inExclusiveRange(0, 0.72),
    );

    await tester.pumpAndSettle(); // 揭曉走完：停住
    expect(hintDy(), 0);
    expect(opacityAbove(tester, find.byKey(_ceremonyHintKey)), 0.72);

    await finishCeremony(tester);
  });

  testWidgets('V3：稀有度牌 2.0 s 才烙上（之前不存在），出現第一幀就是正確稀有度', (tester) async {
    final girl = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.sr);
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester, completer: completer, girl: girl);
    const badgeKey = ValueKey('practice-draw-ceremony-rarity-badge');

    // 翻開後到烙印前每 50 ms 取樣：正面在、牌不在（不先掛別的稀有度）。
    await tester.pump(revealAt(PracticeRevealTiming.flipEndMs));
    for (var ms = PracticeRevealTiming.flipEndMs;
        ms < PracticeRevealTiming.stampStartMs;
        ms += 50) {
      expect(find.byKey(_ceremonyFrontKey), findsOneWidget);
      expect(find.byKey(badgeKey), findsNothing, reason: '$ms ms');
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.descendant(
        of: find.byKey(badgeKey),
        matching: find.text(girl.rarity.label),
      ),
      findsOneWidget,
    );

    await finishCeremony(tester);
  });

  testWidgets('V3：光刃只在卡片側立那一刻（N／R 1.35–1.63 s）出現', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester,
        completer: completer, girl: practiceGirlProfiles[2]);
    const bladeKey = ValueKey('practice-draw-ceremony-light-blade');

    await tester.pump(revealAt(1000));
    expect(find.byKey(bladeKey), findsNothing);
    await tester.pump(revealAt(PracticeRevealTiming.flipPeakMs - 1000 + 40));
    expect(find.byKey(bladeKey), findsOneWidget);
    await tester.pump(revealAt(PracticeRevealTiming.bladeMs));
    expect(find.byKey(bladeKey), findsNothing);

    await finishCeremony(tester);
  });

  for (final rarity in PracticeGirlRarity.values) {
    testWidgets('V3：稀有度誠實（${rarity.label}）——卡背每 50 ms 取樣，只升到真實稀有度',
        (tester) async {
      final girl = practiceGirlProfiles.firstWhere((g) => g.rarity == rarity);
      final completer = Completer<PracticeDrawResult>();
      final api = _DrawApi(() => completer.future);
      await pumpLocked(tester, api: api);
      await drawToReveal(tester, completer: completer, girl: girl);

      var sawBlue = false;
      var sawGold = false;
      var sawLines = false;
      for (var ms = 0.0; ms < PracticeRevealTiming.flipPeakMs; ms += 50) {
        final back = tester.widget<PracticeRevealCardBack>(
          find.byType(PracticeRevealCardBack),
        );
        // 典藏材質 §6.3：R 的成品圖從徽記擴散出來、SR 再擴散成金；N 全程是銀。
        sawBlue |= back.dye.blue > 0.99;
        sawGold |= back.dye.gold > 0.99;
        // §6.6：N 的外框與線路不額外發光；R／SR 染色時一起亮。
        sawLines |= back.energy.lines > 0;
        if (rarity == PracticeGirlRarity.n) {
          expect(back.dye.blue, 0, reason: 'N 全程銀（$ms ms）');
          expect(back.energy.lines, 0, reason: 'N 線路不亮（$ms ms）');
          expect(back.energy.frame, 0, reason: 'N 外框不亮（$ms ms）');
        }
        if (rarity != PracticeGirlRarity.sr ||
            ms <= PracticeRevealTiming.dyeGoldMs) {
          expect(back.dye.gold, 0, reason: '${rarity.label} 不會出現金（$ms ms）');
        }
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(sawBlue, rarity != PracticeGirlRarity.n);
      expect(sawGold, rarity == PracticeGirlRarity.sr);
      expect(sawLines, rarity != PracticeGirlRarity.n);

      await finishCeremony(tester);
    });

    testWidgets('V3.1：揭曉中的光效依稀有度出現（${rarity.label}）——N 沒有衝擊波與升階光點',
        (tester) async {
      final girl = practiceGirlProfiles.firstWhere((g) => g.rarity == rarity);
      final completer = Completer<PracticeDrawResult>();
      final api = _DrawApi(() => completer.future);
      await pumpLocked(tester, api: api);
      await drawToReveal(tester, completer: completer, girl: girl);
      const riseKey = ValueKey('practice-draw-ceremony-rise-dots');
      const shockKey = ValueKey('practice-draw-ceremony-shockwave');
      const bloomBackKey = ValueKey('practice-draw-ceremony-bloom-back');
      const bloomFrontKey = ValueKey('practice-draw-ceremony-bloom-front');
      const whiteKey = ValueKey('practice-draw-ceremony-emblem-white');

      await tester.pump(revealAt(600)); // 徽記白光峰值：三種稀有度都一樣
      expect(find.byKey(whiteKey), findsOneWidget);
      expect(find.byKey(bloomBackKey), findsOneWidget);
      await tester.pump(revealAt(300)); // 900：藍色蓄力
      expect(find.byKey(whiteKey), findsNothing);
      expect(
        find.byKey(riseKey),
        rarity == PracticeGirlRarity.n ? findsNothing : findsOneWidget,
      );
      await tester.pump(revealAt(450)); // 1350：翻牌峰值
      expect(find.byKey(bloomFrontKey), findsOneWidget);
      expect(find.byKey(riseKey), findsNothing);
      await tester.pump(revealAt(150)); // 1500：衝擊波
      if (rarity == PracticeGirlRarity.n) {
        expect(find.byKey(shockKey), findsNothing);
      } else {
        final painter = tester
            .widget<CustomPaint>(find.byKey(shockKey))
            .painter! as PracticeRevealShockwavePainter;
        expect(
            painter.rings, hasLength(rarity == PracticeGirlRarity.sr ? 2 : 1));
        // 典藏材質 M9：R 的衝擊波跟環境光、光刃一起換成 #4FB0FF；SR 維持香檳金。
        expect(
          painter.tint,
          rarity == PracticeGirlRarity.r
              ? PracticeRevealPalette.rGlow
              : PracticeRevealPalette.srBackTint,
        );
      }

      await finishCeremony(tester);
    });
  }

  testWidgets('V3.1 §9：低檔只畫後層泛光，翻牌峰值也沒有前層', (tester) async {
    debugPracticeRevealEffectTierOverride = PracticeRevealEffectTier.low;
    addTearDown(() => debugPracticeRevealEffectTierOverride = null);
    final girl = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.sr);
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester, completer: completer, girl: girl);
    const bloomBackKey = ValueKey('practice-draw-ceremony-bloom-back');
    const bloomFrontKey = ValueKey('practice-draw-ceremony-bloom-front');

    await tester.pump(revealAt(PracticeRevealTiming.flipPeakMs));
    expect(find.byKey(bloomBackKey), findsOneWidget);
    expect(find.byKey(bloomFrontKey), findsNothing);
    await tester.pump(revealAt(100)); // 1450：前層原本還在退
    expect(find.byKey(bloomFrontKey), findsNothing);

    await finishCeremony(tester);
  });

  testWidgets(
      'V3.1：六角牌 1.94 s 才出現、第一幀就是正確稀有度，從畫面左上外面砸進來，2.06 s 落在卡片左上角內（§5.10、典藏材質 §7.3）',
      (tester) async {
    final girl = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.sr);
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester, completer: completer, girl: girl);
    const badgeKey = ValueKey('practice-draw-ceremony-rarity-badge');

    await tester.pump(revealAt(PracticeRevealTiming.stampStartMs - 10));
    expect(find.byKey(badgeKey), findsNothing, reason: '出現前牌根本不存在');
    await tester.pump(revealAt(15)); // 1945：剛出現
    final flying = tester.getRect(find.byKey(badgeKey));
    expect(flying.right, lessThan(0), reason: '從畫面左邊外面進來 $flying');
    expect(flying.bottom, lessThan(0), reason: '從畫面上面外面進來 $flying');
    expect(
      find.descendant(of: find.byKey(badgeKey), matching: find.text('SR')),
      findsOneWidget,
    );

    await tester.pump(
      revealAt(PracticeRevealTiming.stampLandMs + 1 - 1945),
    ); // 2061：剛落地
    final card = tester.getRect(find.byKey(_ceremonyFrontKey));
    final landed = tester.getRect(find.byKey(badgeKey));
    // 典藏材質規格 §7.3：落點收在卡片左上角內（左 12、上 16）。
    expect(landed.left - card.left, closeTo(kPracticeRevealBadgeInset.dx, 1),
        reason: '$landed');
    expect(landed.top - card.top, closeTo(kPracticeRevealBadgeInset.dy, 1),
        reason: '$landed');

    await finishCeremony(tester);
  });

  testWidgets('V3.1：停住時新光效全部結束、畫面靜止（前層泛光、衝擊波、升階光點、厚度邊、星光）', (tester) async {
    final girl = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.sr);
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester, completer: completer, girl: girl);
    await tester.pumpAndSettle(); // 收得了＝停住後沒有動畫幀

    for (final key in [
      'bloom-front',
      'shockwave',
      'rise-dots',
      'thickness',
      'light-blade',
      'emblem-white',
      for (var i = 0; i < 4; i++) 'star-sparkle-$i',
    ]) {
      expect(find.byKey(ValueKey('practice-draw-ceremony-$key')), findsNothing,
          reason: key);
    }
    // 後層泛光停在 0.3，不呼吸。
    final bloom = tester
        .widget<CustomPaint>(
            find.byKey(const ValueKey('practice-draw-ceremony-bloom-back')))
        .painter! as PracticeRevealBloomPainter;
    expect(bloom.alpha, closeTo(0.3, 1e-9));

    await finishCeremony(tester);
  });

  testWidgets('典藏材質：停住時六角牌收在卡片左上角內（左 12、上 16），資訊欄在卡片內、星星在資訊欄內、只畫亮星',
      (tester) async {
    final girl = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.sr);
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester, completer: completer, girl: girl);
    await tester.pumpAndSettle(); // 揭曉走完、停住

    bool inside(Rect outer, Rect inner) {
      final bounds = outer.inflate(0.5);
      return bounds.contains(inner.topLeft) &&
          bounds.contains(inner.bottomRight);
    }

    final card = tester.getRect(find.byKey(_ceremonyFrontKey));
    final badge = tester.getRect(
        find.byKey(const ValueKey('practice-draw-ceremony-rarity-badge')));
    final info = tester
        .getRect(find.byKey(const ValueKey('practice-draw-ceremony-info')));
    const starsKey = ValueKey('practice-draw-ceremony-rarity-stars');
    final stars = tester.getRect(find.byKey(starsKey));
    // 典藏材質規格 §7.3（M4 照示意圖）：牌整塊收在卡片左上角內，離左緣 12、上緣 16。
    final screen = tester
        .getRect(find.byKey(const ValueKey('practice-draw-ceremony-continue')));
    expect(badge.left - card.left, closeTo(kPracticeRevealBadgeInset.dx, 0.5),
        reason: '$badge');
    expect(badge.top - card.top, closeTo(kPracticeRevealBadgeInset.dy, 0.5),
        reason: '$badge');
    expect(inside(card, badge), isTrue, reason: '牌 $badge 超出卡片 $card');
    expect(inside(screen, badge), isTrue, reason: '牌 $badge 超出螢幕 $screen');
    expect(inside(card, info), isTrue, reason: '資訊欄 $info 超出卡片 $card');
    expect(inside(info, stars), isTrue, reason: '星星 $stars 超出資訊欄 $info');
    expect(badge.overlaps(info), isFalse);
    // 只畫亮星（V3 D6=A）：切面星每顆一個 key，第 stars 顆起不存在。
    for (var i = 0; i < girl.rarity.stars; i++) {
      expect(
        find.descendant(
          of: find.byKey(starsKey),
          matching: find.byKey(ValueKey('practice-draw-ceremony-star-$i')),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(ValueKey('practice-draw-ceremony-star-${girl.rarity.stars}')),
      findsNothing,
    );

    await finishCeremony(tester);
  });

  // ── V3.1 第四刀：角色第一句話（docs/plans/2026-10-17-card-draw-v3-1-polish-spec.md §5.13）──
  const introLineKey = ValueKey('practice-draw-ceremony-intro-line');
  const introTextKey = ValueKey('practice-draw-ceremony-intro-text');

  /// 對話框目前打出來的字（還沒打到、畫成透明的那段不算）。
  String introTyped(WidgetTester tester) {
    final span = tester.widget<Text>(find.byKey(introTextKey)).textSpan!;
    return ((span as TextSpan).children!.first as TextSpan).text!;
  }

  testWidgets('V3.1：資訊欄到位後卡片下方浮出第一句話，逐字打出、停住前打完', (tester) async {
    final girl = practiceGirlProfiles[2];
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester, completer: completer, girl: girl);

    await tester.pump(revealAt(PracticeRevealTiming.introLineStartMs - 20));
    expect(find.byKey(introLineKey), findsNothing);

    await tester.pump(revealAt(20 + 250)); // 打到一半
    final half = introTyped(tester);
    expect(half, isNotEmpty);
    expect(half.length, lessThan(girl.selfIntro.length));
    expect(girl.selfIntro.startsWith(half), isTrue);

    await tester.pumpAndSettle(); // 停住：整句打完、畫面靜止
    expect(introTyped(tester), girl.selfIntro);
    expect(opacityAbove(tester, find.byKey(introLineKey)), 1);

    // 收卡：跟資訊欄一起淡掉，不留在圖鑑上。
    await tester.tap(find.byKey(_ceremonyContinueKey));
    await tester.pumpAndSettle();
    expect(find.byKey(introLineKey), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
  });

  for (final (surface, padding) in const [
    (Size(375, 667), EdgeInsets.only(top: 20)), // iPhone SE：沒有底部安全區
    (Size(390, 844), EdgeInsets.only(top: 47, bottom: 34)), // iPhone 14／15
  ]) {
    testWidgets(
        'V3.1：${surface.width.toInt()}×${surface.height.toInt()} 上第一句話不蓋到卡片、'
        '也不蓋到提示字，最長的一句兩行放得下', (tester) async {
      final girl = practiceGirlProfiles.reduce(
        (a, b) => a.selfIntro.length >= b.selfIntro.length ? a : b,
      );
      final completer = Completer<PracticeDrawResult>();
      final api = _DrawApi(() => completer.future);
      await pumpLocked(tester, api: api, surface: surface, padding: padding);
      await drawToReveal(tester, completer: completer, girl: girl);
      await tester.pumpAndSettle(); // 停住

      final card = tester.getRect(find.byKey(_ceremonyFrontKey));
      final bubble = tester.getRect(find.byKey(introLineKey));
      final hint = tester.getRect(find.byKey(_ceremonyHintKey));
      expect(bubble.top, greaterThanOrEqualTo(card.bottom + 8 - 0.5),
          reason: '對話框 $bubble 太貼卡片 $card');
      expect(bubble.bottom, lessThanOrEqualTo(hint.top - 8 + 0.5),
          reason: '對話框 $bubble 蓋到提示字 $hint');
      expect(bubble.width, lessThanOrEqualTo(card.width + 0.5));

      final text = tester.widget<Text>(find.byKey(introTextKey));
      expect(text.maxLines, 2);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(introTextKey),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.didExceedMaxLines, isFalse, reason: '整句要放得下');
      expect(introTyped(tester), girl.selfIntro);

      await finishCeremony(tester);
    });
  }

  testWidgets('V3：翻牌落定前點擊無效；落定後點一下快轉到停住，再點一下才收卡', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester,
        completer: completer, girl: practiceGirlProfiles[2]);

    // 1.0 s（蓄力中）點擊：不理，仍是卡背。
    await tester.pump(revealAt(1000));
    await tester.tap(find.byKey(_ceremonyContinueKey));
    await tester.pump(revealAt(100));
    expect(find.byKey(_ceremonyBackKey), findsOneWidget);

    // 落定後（約 2.0 s）點擊：快轉到資訊全部落位＝停住（提示字全亮）。
    await tester.pump(revealAt(900));
    expect(find.byKey(_ceremonyHintKey), findsNothing); // 提示 2.4 s 才淡入
    await tester.tap(find.byKey(_ceremonyContinueKey));
    await tester.pump(); // animateTo 起跑
    await tester
        .pump(PracticeRevealTiming.skip + const Duration(milliseconds: 20));
    expect(find.byKey(_ceremonyFrontKey), findsOneWidget);
    expect(opacityAbove(tester, find.byKey(_ceremonyHintKey)), 0.72);
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-archive-orb')),
      findsNothing,
    );

    // 停住時再點一下：收卡。
    await tester.tap(find.byKey(_ceremonyContinueKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_ceremonyFrontKey), findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('V3：Android 返回鍵——揭曉中吞掉，停住時等於點擊收卡', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(tester,
        completer: completer, girl: practiceGirlProfiles[2]);

    await tester.pump(revealAt(800));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(_ceremonyBackKey), findsOneWidget); // 還在蓄力，沒被帶走

    await tester.pumpAndSettle(); // 停住
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-archive-orb')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_ceremonyFrontKey), findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('V3：停住時整層是可點的按鈕，讀得出抽到誰與她的第一句話（VoiceOver）', (tester) async {
    final handle = tester.ensureSemantics();
    final girl = practiceGirlProfiles[2];
    final api = _DrawApi(() async => _drawResultFor(girl));
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();

    // 這個 host 沒接圖鑑頁的新舊紀錄：不唸「新角色」也不唸「已收藏」。
    expect(
      tester.getSemantics(find.byKey(_ceremonyContinueKey)),
      isSemantics(
        label: '已抽到 ${girl.displayName}，${girl.rarity.label} 卡。'
            '${girl.selfIntro}',
        hint: '點兩下收進圖鑑',
        isButton: true,
        hasTapAction: true,
      ),
    );
    // 只有儀式這一層會主動唸（資訊欄不設 liveRegion），不會連唸兩次。
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsOne);

    await finishCeremony(tester);
    handle.dispose();
  });

  // ── 翻牌音效掛勾（Batch 4.7）：plumbing-only，spy 驗證呼叫時機 ──────────────
  Future<void> pumpLockedWithSfx(
    WidgetTester tester, {
    required PracticeChatApiService api,
    required PracticeDrawSfx sfx,
    bool reduceMotion = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
          practiceDrawDraftStoreProvider.overrideWithValue(draftStore),
          practiceChatApiServiceProvider.overrideWithValue(api),
          practiceDrawSfxProvider.overrideWithValue(sfx),
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
        child: MaterialApp(
          builder: reduceMotion
              ? (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: true),
                    child: child!,
                  )
              : null,
          home: const _CeremonyTestHost(),
        ),
      ),
    );
  }

  testWidgets('音效：抽牌啟動只播 whoosh，不啟動 waiting loop', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // 進入 drawing

    expect(spy.whoosh, 1);
    expect(spy.waitingStart, 0); // F3：等待期保持安靜，不再播細碎 shimmer。
    expect(spy.archive, 0); // 尚未收卡
    expect(spy.looping, isFalse);

    // 收尾：成功揭曉、收卡收掉 overlay（避免殘留 ticker）。
    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await finishCeremony(tester);
  });

  testWidgets('音效：入場保底——server 立即回來也等卡背入場走完才起播 bed', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await tester.pump(); // 抽成功，但卡背入場還沒走完
    expect(spy.bedStart, 0);

    await tester.pump(const Duration(milliseconds: 300));
    expect(spy.bedStart, 0);
    await tester.pump(const Duration(milliseconds: 250)); // 過 0.5 s：入場完成
    expect(spy.bedStart, 1);

    await finishCeremony(tester);
  });

  testWidgets('音效（v4）：抽牌啟動時預載揭曉音效一次，揭曉直接起播 bed、不停咻聲', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await drawToReveal(tester,
        completer: completer, girl: practiceGirlProfiles[2]);
    expect(spy.whoosh, 1);
    expect(spy.preload, 1); // 與咻聲同時預載，server 回來前就載好
    expect(spy.bedStart, 1);
    expect(spy.whooshStop, 0); // 揭曉起始不停咻聲：尾巴交棒給 bed

    await finishCeremony(tester);
    expect(spy.preload, 1); // 揭曉與收卡都不重複預載
  });

  testWidgets('音效：揭曉成功 → waiting loop 未啟動、playRevealBed', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final zoe = practiceGirlProfiles[2];
    final api = _DrawApi(() async => _drawResultFor(zoe));
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();

    expect(spy.whoosh, 1);
    expect(spy.waitingStart, 0);
    expect(spy.waitingStop, greaterThanOrEqualTo(1));
    expect(spy.bedStart, 1); // 主音軌接管揭曉音效
    expect(spy.archive, 0); // 停住時還沒收卡，收卡音不會先響
    expect(spy.looping, isFalse); // 等待 loop 已停、不殘留

    await finishCeremony(tester);
  });

  testWidgets('音效：抽牌 402 → waiting loop 未啟動、不播揭曉叮聲、停掉咻聲', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final api = _DrawApi(
      () async => throw PracticeDrawUpgradeRequiredException(
        extraCostMessages: 5,
        nextResetAt: '2026-06-27T04:00:00.000Z',
      ),
    );
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();

    expect(spy.waitingStart, 0); // F3：drawing 等待期固定靜音
    expect(spy.waitingStop, greaterThanOrEqualTo(1)); // 相容 stop 仍安全收斂
    expect(spy.bedStart, 0); // 402 不慶祝：沒有配樂（翻牌紙聲也在配樂裡）
    expect(spy.archive, 0); // 沒有揭曉就沒有收卡音
    expect(spy.whooshStop, 1); // 咻聲尾巴不帶到付費牆
    expect(spy.looping, isFalse);
  });

  testWidgets('音效：抽牌 429 → waiting loop 未啟動、不播揭曉叮聲、停掉咻聲', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final api = _DrawApi(
      () async => throw PracticeQuotaExceededException('本月額度已用完',
          monthlyRemaining: 0, dailyRemaining: 0),
    );
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();

    expect(spy.waitingStart, 0);
    expect(spy.waitingStop, greaterThanOrEqualTo(1));
    expect(spy.bedStart, 0); // 429 不慶祝：沒有配樂（翻牌紙聲也在配樂裡）
    expect(spy.archive, 0); // 沒有揭曉就沒有收卡音
    expect(spy.whooshStop, 1); // 咻聲尾巴不帶到錯誤提示
    expect(spy.looping, isFalse);
  });

  testWidgets('音效：收卡後同頁再抽 → 卡背照常出現，第二抽 402 停掉咻聲', (tester) async {
    // 回歸：成功揭曉把 intro 留在終點時，下一抽 forward(from: 0) 會發出 dismissed，
    // 收場 listener 把剛開始的第二抽收成 hidden → 卡背不見、失敗兜底被跳過。
    final spy = _SpyPracticeDrawSfx();
    final first = Completer<PracticeDrawResult>();
    final second = Completer<PracticeDrawResult>();
    var call = 0;
    final api = _DrawApi(() => ++call == 1 ? first.future : second.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy);
    final dim = find.byKey(const ValueKey('practice-draw-ceremony-dim'));

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // 第一抽 drawing
    expect(dim, findsOneWidget); // 對照：第一抽等待時卡背遮罩在
    first.complete(_drawResultFor(practiceGirlProfiles[2]));
    await finishCeremony(tester); // 成功揭曉、收卡收掉 overlay
    expect(spy.whooshStop, 1); // 收卡時咻聲尾巴淡出，不帶到圖鑑頁

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // 第二抽 drawing
    expect(spy.whoosh, 2);
    expect(dim, findsOneWidget); // 第二抽也要有卡背

    second.completeError(PracticeDrawUpgradeRequiredException(
      extraCostMessages: 5,
      nextResetAt: '2026-06-27T04:00:00.000Z',
    ));
    await tester.pumpAndSettle();

    expect(spy.whooshStop, 2); // 第二抽失敗也不把尾巴帶到付費牆
    expect(dim, findsNothing);
    expect(spy.looping, isFalse);
  });

  testWidgets('音效：reduce-motion → 不啟動 waiting loop（咻聲仍觸發）', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy, reduceMotion: true);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing（reduce-motion：卡背定住）

    expect(spy.whoosh, 1); // 一次性咻聲仍觸發
    expect(spy.waitingStart, 0); // reduce-motion：不啟動等待 loop
    expect(spy.looping, isFalse);

    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('音效：drawing 中卸載儀式 → waiting loop 從未啟動、停掉咻聲', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing：只保留視覺等待微動
    expect(spy.waitingStart, 0);
    expect(spy.looping, isFalse);

    // 整個 PracticeChatScreen 子樹卸載 → 儀式 dispose 必停 loop。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(spy.waitingStop, greaterThanOrEqualTo(1));
    expect(spy.looping, isFalse);
    expect(spy.whooshStop, 1); // 抽牌中離開畫面：咻聲尾巴不帶到下一頁

    // draw 在途永不完成 → .timeout 的 45s Timer 還掛著；推過它讓 timeout
    // 觸發（controller 已 dispose，mounted 守門 no-op），否則 !timersPending
    // 收尾斷言會炸。
    await tester.pump(kPracticeDrawRequestTimeout + const Duration(seconds: 1));
  });

  testWidgets('音效（V3）：揭曉期間只有一條 bed（翻牌紙聲在裡面），收卡音只在點擊收卡時播一次', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await drawToReveal(tester,
        completer: completer, girl: practiceGirlProfiles[2]);
    expect(spy.bedStart, 1);
    final atReveal = spy.calls.length;

    // 跨過翻牌峰值、走到停住：不另外起任何音效（紙聲已混在 bed 的 1.35 s）。
    await tester.pumpAndSettle();
    expect(find.byKey(_ceremonyHintKey), findsOneWidget); // 停住
    expect(spy.calls.length, atReveal);
    expect(spy.archive, 0);

    // 點擊收卡：先起收卡音，再淡出配樂與咻聲尾巴。
    await tester.tap(find.byKey(_ceremonyContinueKey));
    await tester.pump();
    expect(spy.calls.sublist(atReveal), ['archive', 'bedStop', 'whooshStop']);

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
    expect(spy.archive, 1); // 整條收完仍只有一次
  });

  testWidgets('音效（V3）：reduce-motion 沒有儀式畫面，也沒有收卡音', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final api = _DrawApi(() async => _drawResultFor(practiceGirlProfiles[2]));
    await pumpLockedWithSfx(tester, api: api, sfx: spy, reduceMotion: true);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();
    expect(spy.archive, 0);
    await tester.pump(const Duration(milliseconds: 250));
  });

  // ── 揭曉配樂 bed：揭曉起始播一次、每個離開出口收掉、失敗／reduce-motion 不起 ────
  testWidgets('音效（V3）：揭曉開始播一條 bed；停住時仍在，點擊收卡後收掉（不殘留）', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    await tester.pump(const Duration(milliseconds: 600)); // 等待微動
    expect(spy.bedStart, 0); // 抽牌等待期間：配樂尚未起

    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await tester.pump(); // revealing：_reveal.forward(from:0) → 配樂起播
    expect(spy.bedStart, 1); // 揭曉起始播一次配樂 bed
    expect(spy.bedPlaying, isTrue);

    await tester.pumpAndSettle(); // 停住：bed 不提早收
    expect(spy.bedPlaying, isTrue);

    await tester.tap(find.byKey(_ceremonyContinueKey));
    await tester.pump();
    expect(spy.bedPlaying, isFalse); // 點擊收卡當下就淡出
    await tester.pumpAndSettle();
    expect(spy.bedStop, greaterThanOrEqualTo(1));
    expect(spy.bedPlaying, isFalse); // 配樂不殘留
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('音效（E2）：再抽一次 → 配樂 bed 重起一次（每次揭曉各一條，不殘留）', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final api = _DrawApi(() async => _drawResultFor(practiceGirlProfiles[2]));
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await finishCeremony(tester);
    expect(spy.bedStart, 1);
    expect(spy.archive, 1);

    // 再抽一次（Task 5 後換人入口在圖鑑；host 測試鈕直呼 draw）。
    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await finishCeremony(tester);
    expect(spy.bedStart, 2); // 第二次揭曉重起一條
    expect(spy.archive, 2); // 每次收卡各一聲
    expect(spy.bedPlaying, isFalse);
  });

  testWidgets('音效（E2）：抽牌 402 → 不起配樂 bed（失敗不慶祝）', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final api = _DrawApi(
      () async => throw PracticeDrawUpgradeRequiredException(
        extraCostMessages: 5,
        nextResetAt: '2026-06-27T04:00:00.000Z',
      ),
    );
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();
    expect(spy.bedStart, 0); // 失敗（402）不放配樂
    expect(spy.bedPlaying, isFalse);
  });

  testWidgets('音效（E2）：揭曉中卸載儀式 → dispose 收掉配樂 bed（不殘留）', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await drawToReveal(tester,
        completer: completer, girl: practiceGirlProfiles[2]);
    expect(spy.bedPlaying, isTrue);

    // 整個 PracticeChatScreen 子樹卸載 → 儀式 dispose 必收掉配樂。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(spy.bedStop, greaterThanOrEqualTo(1));
    expect(spy.bedPlaying, isFalse);
  });

  testWidgets('音效（E2）：reduce-motion 跳整條時間軸 → 不起配樂 bed', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final api = _DrawApi(() async => _drawResultFor(practiceGirlProfiles[2]));
    await pumpLockedWithSfx(tester, api: api, sfx: spy, reduceMotion: true);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    await tester.pump(); // draw 完成 → reduce-motion 直接收掉 overlay
    expect(spy.bedStart, 0); // reduce-motion 無 _reveal 時間軸 → 不起配樂
    expect(spy.archive, 0); // 也沒有收卡音
    expect(spy.bedPlaying, isFalse);

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
  });

  // ── 對拍：觸覺跟著畫面撞擊格（翻牌紙聲已混在 bed 裡）────────────────────────
  // 觸覺從系統 channel 攔：tap＝lightImpact、light＝mediumImpact、medium＝heavyImpact，
  // celebrate＝light→medium→heavy（共 200 ms）、tick＝selectionClick。
  List<String> recordHaptics(WidgetTester tester) {
    final vibrates = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        vibrates.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return vibrates;
  }

  // 蓄力三下 tick 用真實時間節流（70 ms），widget test 次數不穩定：另外只驗上限。
  const tickHaptic = 'HapticFeedbackType.selectionClick';
  List<String> withoutTicks(List<String> vibrates) =>
      vibrates.where((v) => v != tickHaptic).toList();

  // 一次成功揭曉＋收卡的完整音效序列：SR／R／N 必須完全相同（規格 D3：同一條配樂）。
  const revealSfxSequence = [
    'whoosh',
    'preload',
    'waitingStop',
    'bedStart',
    'archive', // 點擊收卡：收卡音
    'bedStop', // 點擊收卡：bed 淡出
    'whooshStop', // 點擊收卡：咻聲尾巴淡出
    'waitingStop', // 收掉 overlay
    'bedStop',
  ];

  testWidgets('對拍（V3）：N 不變色不震，翻牌峰值重擊、烙印一下、落位一下', (tester) async {
    final vibrates = recordHaptics(tester);
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy);
    final n = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.n);

    await drawToReveal(tester, completer: completer, girl: n);
    expect(withoutTicks(vibrates), ['HapticFeedbackType.mediumImpact']); // 只有抽牌

    await tester.pump(revealAt(PracticeRevealTiming.flipPeakMs + 10));
    expect(withoutTicks(vibrates).last, 'HapticFeedbackType.heavyImpact');

    await finishCeremony(tester);
    expect(withoutTicks(vibrates), [
      'HapticFeedbackType.mediumImpact', // 抽牌
      'HapticFeedbackType.heavyImpact', // 1.35 s 翻牌峰值
      'HapticFeedbackType.lightImpact', // 2.06 s 稀有度牌落地
      'HapticFeedbackType.mediumImpact', // 收卡光球落位
    ]);
    // 蓄力 3 下＋亮星 2 下（真實時間節流，只驗上限）。
    expect(vibrates.where((v) => v == tickHaptic).length, lessThanOrEqualTo(5));
    expect(spy.calls, revealSfxSequence);
  });

  testWidgets('對拍（V3）：R 染藍一下，翻牌峰值重擊、牌落地一下、光球落位一下', (tester) async {
    final vibrates = recordHaptics(tester);
    final spy = _SpyPracticeDrawSfx();
    final r = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.r);
    final api = _DrawApi(() async => _drawResultFor(r));
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await finishCeremony(tester);
    expect(withoutTicks(vibrates), [
      'HapticFeedbackType.mediumImpact', // 抽牌
      'HapticFeedbackType.mediumImpact', // 0.6 s 染藍
      'HapticFeedbackType.heavyImpact', // 1.35 s 翻牌峰值
      'HapticFeedbackType.lightImpact', // 2.06 s 稀有度牌落地
      'HapticFeedbackType.mediumImpact', // 收卡光球落位
    ]);
    expect(spy.calls, revealSfxSequence);
  });

  testWidgets(
      '對拍（V3）：SR 染藍、染金各一下，1.15 s 起 celebrate、第三下落在翻牌峰值，牌落地改 light（V3.1 §8）；音效序列與 N 相同',
      (tester) async {
    final vibrates = recordHaptics(tester);
    final spy = _SpyPracticeDrawSfx();
    final sr = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.sr);
    final api = _DrawApi(() async => _drawResultFor(sr));
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await finishCeremony(tester);
    expect(withoutTicks(vibrates), [
      'HapticFeedbackType.mediumImpact', // 抽牌
      'HapticFeedbackType.lightImpact', // 0.6 s 染藍
      'HapticFeedbackType.mediumImpact', // 0.85 s 染金
      'HapticFeedbackType.lightImpact', // 1.15 s celebrate 第一下
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact', // 1.35 s 翻牌峰值
      'HapticFeedbackType.mediumImpact', // 2.06 s 稀有度牌落地（SR 有光環，手感加重）
      'HapticFeedbackType.mediumImpact', // 收卡光球落位
    ]);
    expect(spy.calls, revealSfxSequence); // 聲音和 N 完全一樣
  });

  testWidgets('V3.1 等待心跳：卡背入場走完才開始，每 900 ms 一組兩下、最多 6 組，畫面同一拍顫動（§5.15）',
      (tester) async {
    final vibrates = recordHaptics(tester);
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    const motionKey = ValueKey('practice-draw-ceremony-waiting-motion');

    // tick() 用真實時間節流（70 ms）：每一下之前先真的等 80 ms，次數才數得準。
    Future<void> realGap() => tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
    int ticks() => vibrates.where((v) => v == tickHaptic).length;
    double shiver() => tester
        .widget<Transform>(find.byKey(motionKey))
        .transform
        .getTranslation()
        .x;
    var now = 0.0;
    Future<void> pumpTo(double ms) async {
      await tester.pump(Duration(microseconds: ((ms - now) * 1000).round()));
      now = ms;
    }

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing：以按下翻牌為 0
    await realGap();
    await pumpTo(490);
    expect(ticks(), 0, reason: '卡背入場（500）走完前沒有心跳');
    expect(shiver(), 0);
    for (var beat = 0; beat < kPracticeHeartbeatBeats; beat++) {
      await realGap();
      await pumpTo(practiceHeartbeatBeatMs(beat) + 10);
      expect(ticks(), beat + 1, reason: '第 ${beat + 1} 下');
      expect(shiver().abs(), greaterThan(0.5), reason: '第 ${beat + 1} 下的顫動');
    }
    await realGap();
    await pumpTo(9000);
    expect(ticks(), kPracticeHeartbeatBeats, reason: '最多 6 組，之後只剩呼吸');
    expect(shiver(), 0);

    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await tester.pump();
    await finishCeremony(tester);
  });

  testWidgets('V3.1 等待心跳：reduce-motion 沒有心跳（觸覺和畫面都不做）', (tester) async {
    final vibrates = recordHaptics(tester);
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy, reduceMotion: true);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 900));
    }
    expect(vibrates.where((v) => v == tickHaptic), isEmpty);

    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('對拍（v4）：reduce-motion 沒有儀式，觸覺留在抽中當下、沒有配樂與收卡音', (tester) async {
    final vibrates = recordHaptics(tester);
    final spy = _SpyPracticeDrawSfx();
    final n = practiceGirlProfiles
        .firstWhere((g) => g.rarity == PracticeGirlRarity.n);
    final api = _DrawApi(() async => _drawResultFor(n));
    await pumpLockedWithSfx(tester, api: api, sfx: spy, reduceMotion: true);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();
    expect(vibrates, [
      'HapticFeedbackType.mediumImpact', // 抽牌
      'HapticFeedbackType.heavyImpact', // 抽中當下
    ]);
    expect(spy.bedStart, 0);
    expect(spy.archive, 0);
  });

  group('E1 卡尺寸 responsive', () {
    test('卡寬≈0.90×螢幕寬、維持直式 2:3，且比舊版固定 214 大', () {
      expect(kPracticeCardWidthFactor, greaterThanOrEqualTo(0.90));
      expect(kPracticeCardMaxWidth, greaterThanOrEqualTo(390));
      final s = practiceCeremonyCardSize(const Size(390, 844));
      expect(s.width, closeTo(390 * 0.90, 0.5));
      expect(s.height, closeTo(s.width * 1.5, 0.5));
      expect(s.width, greaterThan(214));
    });

    test('大螢幕（平板）卡寬封頂、不無限放大（仍維持 2:3）', () {
      final s = practiceCeremonyCardSize(const Size(1200, 1600));
      expect(s.width, lessThanOrEqualTo(kPracticeCardMaxWidth));
      expect(s.height, closeTo(s.width * 1.5, 0.5));
    });

    test('矮螢幕：卡高被可用高度夾住、不溢出（仍維持 2:3）', () {
      final s = practiceCeremonyCardSize(const Size(360, 480));
      expect(s.height, lessThanOrEqualTo(480 * 0.64 + 0.5));
      expect(s.width, closeTo(s.height / 1.5, 0.5));
    });
  });

  testWidgets('E1：揭曉卡片在手機上明顯放大（卡背寬度 > 舊版 214、維持 2:3）', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    await tester.pump(const Duration(milliseconds: 160)); // intro 入場

    final backSize = tester.getSize(find.byKey(_ceremonyBackKey));
    expect(backSize.width, greaterThan(214));
    // G2：卡比例改直式 2:3（高 = 寬 × 1.5，較舊 4/3 更高更主導，貼合參考片塔羅卡）。
    expect(backSize.height, closeTo(backSize.width * 1.5, 1.0));

    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await finishCeremony(tester);
  });

  testWidgets('卡背整體（debugCeremonyCardBack）建構不丟、含卡背 key', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: debugCeremonyCardBack(width: 240, height: 360),
        ),
      ),
    );
    expect(find.byKey(_ceremonyBackKey), findsOneWidget);
  });

  testWidgets(
      'startProfileId 進場 → post-frame 呼叫 startSessionWithProfile（圖鑑點卡縫）',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final seed = PracticeChatState(
      sessionId: 'practice-start-profile-test',
      createdAt: DateTime(2026, 7, 3, 12),
      girl: practiceGirlProfiles.first,
      personaId: 'slow_worker',
      personaLabel: '慢熱上班族',
      difficulty: 'normal',
      difficultyLabel: '一般',
    );
    final controller = _StartProfileSpyController(seed: seed, repository: repo);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(
          home: PracticeChatScreen(startProfileId: 'practice_girl_004'),
        ),
      ),
    );
    // post-frame 縫：首幀 build（watch 已掛 listener）後才發起開局。
    await tester.pump();

    expect(controller.startSessionCalls, ['practice_girl_004']);
  });

  // ── Phase 4.5c 刀 3：她先去忙了的提示 ────────────────────────────────────
  PracticeChatState checkedOutSeed({String? partnerStatus}) =>
      PracticeChatState(
        sessionId: 'checked-out-sess',
        createdAt: DateTime(2026, 9, 5, 21),
        drawStatus: PracticeDrawStatus.revealed,
        girl: practiceGirlProfiles.first,
        personaId: 'slow_worker',
        personaLabel: '慢熱上班族',
        difficulty: 'normal',
        difficultyLabel: '一般',
        visiblePracticeThreadId: 'checked-out-sess',
        aiReplyCount: 3,
        partnerStatus: partnerStatus,
        messages: const [
          PracticeMessage(role: 'user', text: '東東'),
          PracticeMessage(role: 'ai', text: '我先去忙一下'),
        ],
      );

  Future<void> pumpCheckedOut(
    WidgetTester tester, {
    String? partnerStatus,
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith(
            (ref) => _SeededPracticeChatController(
              seed: checkedOutSeed(partnerStatus: partnerStatus),
              repository: repo,
            ),
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
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const PracticeChatScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('拆解卡也過練習室同意閘：只有舊版 v2 同意時先跳框，拒絕不送、同意才送', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai_data_sharing_consent_practice_20260706_v2': true,
    });
    final controller = _EndPracticeSpyController(
      seed: checkedOutSeed(partnerStatus: 'checked_out'),
      repository: repo,
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );
    await tester.pump();
    final debriefBtn = find.byKey(
      const ValueKey('practice-partner-checked-out-debrief'),
    );

    await tester.tap(debriefBtn);
    await tester.pumpAndSettle();
    expect(find.text('資料使用說明'), findsOneWidget);
    await tester.tap(find.text('暫不同意'));
    await tester.pumpAndSettle();
    expect(controller.endPracticeCalls, 0);

    await tester.tap(debriefBtn);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('同意並繼續'));
    await tester.tap(find.text('同意並繼續'));
    await tester.pumpAndSettle();
    expect(controller.endPracticeCalls, 1);
  });

  testWidgets('Phase 4.5c：她先去忙了時輸入列上方多一行提示，輸入框仍可用', (tester) async {
    await pumpCheckedOut(tester, partnerStatus: 'checked_out');

    expect(
      find.byKey(const ValueKey('practice-partner-checked-out')),
      findsOneWidget,
    );
    expect(find.text('她先去忙了，這場可以結束練習看拆解'), findsOneWidget);
    // Phase 5 WP5：提示下面多一顆導向檢討的主鈕（aiReplyCount 3 → canDebrief）。
    final debriefBtn = find.byKey(
      const ValueKey('practice-partner-checked-out-debrief'),
    );
    expect(debriefBtn, findsOneWidget);
    final debriefOnPressed =
        tester.widget<BrandPrimaryButton>(debriefBtn).onPressed;
    expect(debriefOnPressed, isNotNull);
    // 導向檢討＝走既有「結束練習」同一條路（同一個回呼），不是另一個入口。
    final endPractice = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('結束練習'),
        matching: find.byType(TextButton),
      ),
    );
    expect(identical(debriefOnPressed, endPractice.onPressed), isTrue);
    // 不鎖：輸入框沒有被換成「20 則上限」那一格，也沒有被禁用。
    expect(find.text('這場練習已達 20 則回覆'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isNot(false));
  });

  testWidgets('WP4：她的「（已讀）」回覆畫成玩家泡泡下的小字已讀，不畫成她的泡泡', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith(
            (ref) => _SeededPracticeChatController(
              seed: checkedOutSeed(partnerStatus: 'read_only').copyWith(
                messages: const [
                  PracticeMessage(role: 'user', text: '東東'),
                  PracticeMessage(role: 'ai', text: '我先去忙一下'),
                  PracticeMessage(role: 'user', text: '在嗎'),
                  PracticeMessage(role: 'ai', text: '（已讀）'),
                ],
              ),
              repository: repo,
            ),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );
    await tester.pump();

    // LINE 語意：她回過的「東東」跟只被已讀的「在嗎」都亮已讀 → 兩個。
    expect(
        find.byKey(const ValueKey('practice-read-receipt')), findsNWidgets(2));
    expect(find.text('已讀'), findsNWidgets(2));
    expect(find.text('（已讀）'), findsNothing);
    // 她的真正回覆照樣是泡泡。
    expect(find.text('我先去忙一下'), findsOneWidget);
  });

  testWidgets('已讀＝她看過：輸入中最後一顆先亮、她回過的都亮、封鎖那則不算', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<void> pumpWith(PracticeChatState seed) async {
      await tester.pumpWidget(
        ProviderScope(
          // 同位置的 ProviderScope 會沿用第一次的 overrides；換 key 才是新 seed。
          key: UniqueKey(),
          overrides: [
            practiceChatControllerProvider.overrideWith(
              (ref) =>
                  _SeededPracticeChatController(seed: seed, repository: repo),
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
          child: const MaterialApp(home: PracticeChatScreen()),
        ),
      );
      await tester.pump();
    }

    // 她輸入中：我方最後一顆已經亮已讀（她看了才會打字）。
    await pumpWith(
      checkedOutSeed(partnerStatus: null).copyWith(
        isSending: true,
        messages: const [
          PracticeMessage(role: 'ai', text: '嗨'),
          PracticeMessage(role: 'user', text: '在嗎'),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('practice-read-receipt')), findsOneWidget);

    // 還沒送出、她也還沒回：不亮。
    await pumpWith(
      checkedOutSeed(partnerStatus: null).copyWith(
        messages: const [
          PracticeMessage(role: 'ai', text: '嗨'),
          PracticeMessage(role: 'user', text: '在嗎'),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('practice-read-receipt')), findsNothing);

    // 封鎖：她之前回過的那顆亮，觸發封鎖的最後一顆不亮。
    await pumpWith(
      checkedOutSeed(partnerStatus: 'blocked').copyWith(
        messages: const [
          PracticeMessage(role: 'user', text: '嗨'),
          PracticeMessage(role: 'ai', text: '嗨'),
          PracticeMessage(role: 'user', text: '（冒犯）'),
          PracticeMessage(role: 'ai', text: kPracticeBlockedReplyText),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('practice-read-receipt')), findsOneWidget);
  });

  testWidgets('WP4 時間戳：有 sentAt 的泡泡旁畫「上午/下午 h:mm」，舊資料（null）不畫', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith(
            (ref) => _SeededPracticeChatController(
              seed: checkedOutSeed(partnerStatus: 'read_only').copyWith(
                messages: [
                  const PracticeMessage(role: 'user', text: '舊資料沒時間'),
                  PracticeMessage(
                    role: 'ai',
                    text: '嗨',
                    sentAt: DateTime(2026, 9, 6, 9, 5),
                  ),
                  PracticeMessage(
                    role: 'user',
                    text: '在嗎',
                    sentAt: DateTime(2026, 9, 6, 15, 26),
                  ),
                  const PracticeMessage(role: 'ai', text: '（已讀）'),
                ],
              ),
              repository: repo,
            ),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const ValueKey('practice-message-time')), findsNWidgets(2));
    expect(find.text('上午 9:05'), findsOneWidget);
    expect(find.text('下午 3:26'), findsOneWidget);
    // 已讀疊在玩家泡泡的時間上方；兩顆玩家泡泡她都看過 → 兩個。
    expect(
        find.byKey(const ValueKey('practice-read-receipt')), findsNWidgets(2));
  });

  // ── Phase 5 WP6：她封鎖你 ──────────────────────────────────────────────
  Future<void> pumpBlocked(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith(
            (ref) => _SeededPracticeChatController(
              // partnerStatus 不進 Hive：只靠訊息也要推得出終局。
              seed: checkedOutSeed().copyWith(
                messages: const [
                  PracticeMessage(role: 'user', text: '東東'),
                  PracticeMessage(role: 'ai', text: '我先去忙一下'),
                  PracticeMessage(role: 'user', text: '性冒犯'),
                  PracticeMessage(role: 'ai', text: '（已封鎖）'),
                ],
              ),
              repository: repo,
            ),
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('WP6：封鎖畫成系統字＋輸入列換成終局，導向教練拆解', (tester) async {
    await pumpBlocked(tester);

    expect(find.byKey(const ValueKey('practice-blocked-line')), findsOneWidget);
    expect(find.text('她已封鎖你'), findsOneWidget);
    expect(find.text('（已封鎖）'), findsNothing);
    // 沒有輸入框。
    expect(find.byType(TextField), findsNothing);
    expect(find.text('她已封鎖你，這場結束了'), findsOneWidget);
    final btn = find.ancestor(
      of: find.text('看教練拆解'),
      matching: find.byType(BrandPrimaryButton),
    );
    expect(btn, findsOneWidget);
    expect(tester.widget<BrandPrimaryButton>(btn).onPressed, isNotNull);
    // 封鎖優先於已讀提示。
    expect(find.text('她先去忙了，這場可以結束練習看拆解'), findsNothing);
  });

  testWidgets('WP6（反例）：一般輪次沒有封鎖那格', (tester) async {
    await pumpCheckedOut(tester);

    expect(find.byKey(const ValueKey('practice-blocked-line')), findsNothing);
    expect(find.text('她已封鎖你，這場結束了'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Phase 4.5c（反例）：一般輪次不顯示那一行', (tester) async {
    await pumpCheckedOut(tester);

    expect(
      find.byKey(const ValueKey('practice-partner-checked-out')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('practice-partner-checked-out-debrief')),
      findsNothing,
    );
  });

  // U3：她只回已讀那一格用同一行提示；大字級與最小支援寬度都不得 overflow。
  testWidgets('Phase 4.5c：read_only 同一格但文案改成已讀沒回', (tester) async {
    await pumpCheckedOut(tester, partnerStatus: 'read_only');

    expect(
      find.byKey(const ValueKey('practice-partner-checked-out')),
      findsOneWidget,
    );
    expect(find.text('她已讀沒回，這場可以結束練習看拆解'), findsOneWidget);
    expect(find.text('她先去忙了，這場可以結束練習看拆解'), findsNothing);
  });

  for (final layout in [
    // 大字級（iOS 無障礙常見級距）與最小支援寬度（iPhone SE 第一代 320pt）。
    (label: '大字級 1.3', size: const Size(390, 844), scale: 1.3),
    (label: '最小寬度 320', size: const Size(320, 568), scale: 1.0),
    (label: '最小寬度 320 ＋大字級 1.3', size: const Size(320, 568), scale: 1.3),
  ]) {
    testWidgets('Phase 4.5c：提示行在${layout.label}下不 overflow', (tester) async {
      await pumpCheckedOut(
        tester,
        partnerStatus: 'checked_out',
        size: layout.size,
        textScale: layout.scale,
      );

      expect(
        find.byKey(const ValueKey('practice-partner-checked-out')),
        findsOneWidget,
      );
      // `tester.takeException()` 會把 RenderFlex overflow 這類 layout 例外
      // 取出來；沒有例外時回 null。**非恆真**：同一支測試在 120×400／
      // textScale 3.0 下實測會失敗（2026-09-05 手動反證過），所以「沒有例外」
      // 是有內容的斷言，不是這個 harness 根本抓不到 overflow。
      expect(tester.takeException(), isNull, reason: layout.label);
    });
  }
}
