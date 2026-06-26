import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_draw_draft_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_profile.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_sfx.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PracticeDrawResult> drawProfile({
    required String requestId,
    String? currentProfileId,
    String? visiblePracticeThreadId,
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
  }) =>
      throw UnimplementedError();

  @override
  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
  }) =>
      throw UnimplementedError();
}

/// 翻牌音效 spy：記錄各呼叫點次數，`looping` 由 start/stop 差推導，用來斷言
/// 「等待 loop 不殘留」。預設 no-op 行為（不真的播放）。
class _SpyPracticeDrawSfx implements PracticeDrawSfx {
  int whoosh = 0;
  int waitingStart = 0;
  int waitingStop = 0;
  int chime = 0;

  /// start 次數多於 stop ⇒ loop 仍在播（用來驗證離開 drawing 後必為 false）。
  bool get looping => waitingStart > waitingStop;

  @override
  void playWhoosh() => whoosh++;

  @override
  void playWaitingLoop() => waitingStart++;

  @override
  void stopWaitingLoop() => waitingStop++;

  @override
  void playRevealChime() => chime++;
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

void main() {
  // 兩段升階揭曉時間軸：測試的 pump 時間點全由 widget 公開的 beat 常數推導，
  // 與 _PracticeDrawCeremonyState 共用單一真相（重新調 beat 不會讓測試落點失準）。
  Duration atFraction(double f) => Duration(
      milliseconds: (f * kPracticeRevealDuration.inMilliseconds).round());
  // 白卡預覽段中點
  final previewAt =
      atFraction((kPracticeRevealFlip1End + kPracticeRevealPreviewEnd) / 2);
  // 高潮蓄力段中點（卡背朝前、front 已收）
  final backAt =
      atFraction((kPracticeRevealRechargeEnd + kPracticeRevealHaloClimax) / 2);
  // 典藏卡停留段中點
  final grandHoldAt =
      atFraction((kPracticeRevealGrandFlipEnd + kPracticeRevealHoldEnd) / 2);

  late PracticeSessionRepository repo;
  late InMemoryPracticeDrawDraftStore draftStore;

  setUp(() {
    repo = _MemoryPracticeSessionRepository();
    draftStore = InMemoryPracticeDrawDraftStore();
  });

  testWidgets('renders practice bubbles on the light conversation workspace',
      (tester) async {
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
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    final workspace = tester.widget<Container>(
      find.byKey(const ValueKey('practice-chat-workspace')),
    );
    final decoration = workspace.decoration! as BoxDecoration;

    expect(decoration.color, Colors.white.withValues(alpha: 0.96));
    expect(find.text('我說'), findsOneWidget);
    expect(find.text('她說'), findsOneWidget);
    expect(find.text('今天好無聊'), findsOneWidget);
    expect(find.textContaining('認真的嗎'), findsOneWidget);

    final userText = tester.widget<Text>(find.text('今天好無聊'));
    expect(userText.style?.color, AppColors.glassTextPrimary);
  });

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

    // 翻牌入口：標題＋CTA。
    expect(find.text('每日登入就送新女孩'), findsOneWidget);
    expect(find.byKey(const ValueKey('practice-draw-cta')), findsOneWidget);
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

  testWidgets('翻牌後（revealed、未送出）顯示 hero + 換一位 + 難度 chips', (tester) async {
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
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    // 揭曉後（開場前）：首屏 hero 大卡 + 換一位 + 難度 chips。
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    expect(find.text('換一位'), findsOneWidget);
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
      debrief: const PracticeDebrief(
        summary: '整體不錯',
        strengths: ['開場好'],
        watchouts: [],
        suggestedLine: '約她',
        vibe: '暖',
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

  testWidgets('拆解後：續玩當主鈕、附扣費說明、加換一位與完成', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: debriefSeed(),
      repository: repo,
    );
    await pumpDebrief(tester, controller: controller);

    expect(find.text('續聊同一位'), findsOneWidget);
    expect(find.textContaining('再扣 1 則'), findsOneWidget);
    expect(find.text('換一位'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('第 3 輪拆解後：隱藏續玩，只留換一位與完成', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: debriefSeed(roundIndex: 3),
      repository: repo,
    );
    await pumpDebrief(tester, controller: controller);

    expect(find.text('續聊同一位'), findsNothing);
    expect(find.textContaining('再扣 1 則'), findsNothing);
    expect(find.text('換一位'), findsOneWidget);
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

  testWidgets('點換一位 → 走 draw、重置成開場前狀態（訊息清空、角色控制重現）', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: debriefSeed(),
      repository: repo,
    );
    await pumpDebrief(tester, controller: controller);

    await tester.tap(find.text('換一位'));
    await tester.pump(); // drawing（locked 入口、spinner）
    await tester.pump(); // draw 完成 → revealed 新對象

    final s = controller.currentState;
    expect(s.messages, isEmpty);
    expect(s.roundIndex, 1);
    expect(s.debrief, isNull);
    expect(s.drawStatus, PracticeDrawStatus.revealed);
    // 開場前控制重現：難度 chips 與換一位鈕回來。
    expect(find.text('輕鬆'), findsOneWidget);
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
  Future<void> pumpLocked(
    WidgetTester tester, {
    required PracticeChatApiService api,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    expect(find.byKey(const ValueKey('practice-draw-cta')), findsNothing);
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
    expect(find.byKey(const ValueKey('practice-draw-cta')), findsNothing);
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

  testWidgets('revealed 換一位 draw 402 → 保留原對象＋error banner 顯升級 CTA',
      (tester) async {
    final api = _DrawApi(
      () async => throw PracticeDrawUpgradeRequiredException(
        extraCostMessages: 5,
        nextResetAt: '2026-06-27T04:00:00.000Z',
      ),
    );
    final seed = revealedPreMsgSeed();
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo, api: api);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.text('換一位'));
    await tester.pump(); // drawing
    await tester.pump(); // 402 回來

    // 保留原對象（仍 revealed、girl 不漂移）。
    expect(controller.currentState.drawStatus, PracticeDrawStatus.revealed);
    expect(controller.currentState.girl!.profileId, seed.girl!.profileId);
    expect(controller.currentState.drawUpgradeRequired, true);
    // revealed banner 有升級入口。
    expect(find.text('升級'), findsOneWidget);
  });

  testWidgets('revealed 換一位 draw 429 → 保留原對象＋error banner 顯升級 CTA',
      (tester) async {
    final api = _DrawApi(
      () async => throw PracticeQuotaExceededException('本月額度已用完',
          monthlyRemaining: 0, dailyRemaining: 0),
    );
    final seed = revealedPreMsgSeed();
    final controller =
        _SeededPracticeChatController(seed: seed, repository: repo, api: api);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceChatControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    await tester.tap(find.text('換一位'));
    await tester.pump();
    await tester.pump();

    expect(controller.currentState.drawStatus, PracticeDrawStatus.revealed);
    expect(controller.currentState.girl!.profileId, seed.girl!.profileId);
    expect(controller.currentState.drawQuotaExceeded, true);
    expect(find.text('升級'), findsOneWidget);
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
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    // 進房就是 revealed（草稿還原情境）：儀式不得誤觸發。
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );
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
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);

    await tester.tap(find.byType(TextButton).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(controller.currentState.drawStatus, PracticeDrawStatus.drawing);
    expect(find.byKey(const ValueKey('practice-locked-entry')), findsNothing);
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsOneWidget,
    );

    completer.complete(_drawResultFor(nextGirl));
    await tester.pumpAndSettle();
    expect(controller.currentState.girl!.profileId, nextGirl.profileId);
  });

  testWidgets('儀式：抽牌中浮現神秘卡背（不洩漏身份、無正面）', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    await tester.pump(const Duration(milliseconds: 60)); // intro 入場推進

    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );

    // 收尾：完成抽牌、settle 收掉 overlay，避免殘留 ticker。
    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await tester.pumpAndSettle();
  });

  testWidgets('儀式：reveal 動畫走完 → overlay 收掉、露出 hero（名字不重複）', (tester) async {
    final zoe = practiceGirlProfiles[2];
    final api = _DrawApi(() async => _drawResultFor(zoe));
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
    // 名字只在 hero 出現一處（儀式正面不得用「名字，年齡」精確字串撞測試）。
    expect(find.text('${zoe.displayName}，${zoe.age}'), findsOneWidget);
  });

  testWidgets('儀式：reveal 成功後正面卡會暫留，讓使用者看清楚特效', (tester) async {
    final zoe = practiceGirlProfiles[2];
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    completer.complete(_drawResultFor(zoe));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));

    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsOneWidget,
    );

    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );
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
          home: const PracticeChatScreen(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();

    // 跳過翻面：正面卡不出現，直接露出 hero。
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
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
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );

    // 收尾：成功揭曉、settle 收掉 overlay（等待微動須已停，pumpAndSettle 才收斂）。
    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsNothing,
    );
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

    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );
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
          home: const PracticeChatScreen(),
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
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );

    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await tester.pumpAndSettle();
  });

  // ── 兩段升階儀式骨架（Batch A）──────────────────────────────────────────
  Future<void> drawToReveal(
    WidgetTester tester, {
    required Completer<PracticeDrawResult> completer,
    required PracticeGirlProfile girl,
  }) async {
    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    await tester.pump(const Duration(milliseconds: 600)); // 等待微動
    completer.complete(_drawResultFor(girl));
    await tester.pump(); // 進入 revealing：_reveal.forward(from:0)
  }

  testWidgets('兩段升階：第一段翻出白卡預覽（~1.5s 顯正面卡、不顯卡背）',
      (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(
        tester, completer: completer, girl: practiceGirlProfiles[2]);

    await tester.pump(previewAt); // 白卡預覽段
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsNothing,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('兩段升階：高潮蓄力段顯卡背（不顯正面）', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(
        tester, completer: completer, girl: practiceGirlProfiles[2]);

    await tester.pump(backAt); // 高潮蓄力段
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('兩段升階：高潮後典藏卡停留（~5.6s 顯正面卡）', (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(
        tester, completer: completer, girl: practiceGirlProfiles[2]);

    await tester.pump(grandHoldAt); // 典藏卡停留段
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('兩段升階：整條 7.5s 時間軸 pumpAndSettle 收斂、最終露 hero',
      (tester) async {
    final zoe = practiceGirlProfiles[2];
    final api = _DrawApi(() async => _drawResultFor(zoe));
    await pumpLocked(tester, api: api);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle(); // 整條走完必收斂

    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-front')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('practice-draw-ceremony-back')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('practice-profile-hero')), findsOneWidget);
  });

  testWidgets('兩段升階：軌道彗星 halo 只在蓄力→高潮段亮（preview／hold 不亮）',
      (tester) async {
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLocked(tester, api: api);
    await drawToReveal(
        tester, completer: completer, girl: practiceGirlProfiles[2]);

    // 白卡預覽段：halo 尚未啟動。
    await tester.pump(previewAt);
    expect(find.byKey(const ValueKey('practice-draw-ceremony-halo-back')),
        findsNothing);
    expect(find.byKey(const ValueKey('practice-draw-ceremony-halo-front')),
        findsNothing);

    // 高潮蓄力段：前後兩夾層 halo 都亮。
    await tester.pump(backAt - previewAt);
    expect(find.byKey(const ValueKey('practice-draw-ceremony-halo-back')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('practice-draw-ceremony-halo-front')),
        findsOneWidget);

    // 典藏卡停留段：halo settle 收掉。
    await tester.pump(grandHoldAt - backAt);
    expect(find.byKey(const ValueKey('practice-draw-ceremony-halo-back')),
        findsNothing);
    expect(find.byKey(const ValueKey('practice-draw-ceremony-halo-front')),
        findsNothing);

    await tester.pumpAndSettle();
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
        ],
        child: MaterialApp(
          builder: reduceMotion
              ? (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: true),
                    child: child!,
                  )
              : null,
          home: const PracticeChatScreen(),
        ),
      ),
    );
  }

  testWidgets('音效：抽牌啟動 → playWhoosh ＋ playWaitingLoop', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // 進入 drawing

    expect(spy.whoosh, 1);
    expect(spy.waitingStart, 1); // 等待 loop 啟動
    expect(spy.chime, 0); // 尚未揭曉
    expect(spy.looping, isTrue);

    // 收尾：成功揭曉、settle 收掉 overlay（避免殘留 ticker）。
    completer.complete(_drawResultFor(practiceGirlProfiles[2]));
    await tester.pumpAndSettle();
  });

  testWidgets('音效：揭曉成功 → stopWaitingLoop ＋ playRevealChime（loop 不殘留）',
      (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final zoe = practiceGirlProfiles[2];
    final api = _DrawApi(() async => _drawResultFor(zoe));
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();

    expect(spy.whoosh, 1);
    expect(spy.waitingStart, 1);
    expect(spy.waitingStop, greaterThanOrEqualTo(1));
    expect(spy.chime, 1); // 揭曉叮聲
    expect(spy.looping, isFalse); // 等待 loop 已停、不殘留
  });

  testWidgets('音效：抽牌 402 → stopWaitingLoop、不播揭曉叮聲', (tester) async {
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

    expect(spy.waitingStart, 1); // 曾進 drawing 啟動 loop
    expect(spy.waitingStop, greaterThanOrEqualTo(1)); // 失敗兜底停 loop
    expect(spy.chime, 0); // 402 不慶祝
    expect(spy.looping, isFalse);
  });

  testWidgets('音效：抽牌 429 → stopWaitingLoop、不播揭曉叮聲', (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final api = _DrawApi(
      () async => throw PracticeQuotaExceededException('本月額度已用完',
          monthlyRemaining: 0, dailyRemaining: 0),
    );
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pumpAndSettle();

    expect(spy.waitingStart, 1);
    expect(spy.waitingStop, greaterThanOrEqualTo(1));
    expect(spy.chime, 0); // 429 不慶祝
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
  });

  testWidgets('音效：drawing 中卸載儀式 → dispose stopWaitingLoop，loop 不殘留',
      (tester) async {
    final spy = _SpyPracticeDrawSfx();
    final completer = Completer<PracticeDrawResult>();
    final api = _DrawApi(() => completer.future);
    await pumpLockedWithSfx(tester, api: api, sfx: spy);

    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing：等待 loop 啟動
    expect(spy.looping, isTrue);

    // 整個 PracticeChatScreen 子樹卸載 → 儀式 dispose 必停 loop。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(spy.waitingStop, greaterThanOrEqualTo(1));
    expect(spy.looping, isFalse);
  });

  // ── 軌道彗星 halo painter（Batch B）：純 painter smoke，免 widget harness ──
  void paintHaloOnce(CustomPainter painter) {
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), const Size(360, 480));
    recorder.endRecording().dispose();
  }

  group('軌道彗星 halo painter（Batch B）', () {
    test('建構＋paint：front/back 兩夾層都不丟例外', () {
      for (final half in PracticeHaloHalf.values) {
        final painter = debugOrbitalHaloPainter(
          progress: 0.4,
          intensity: 0.85,
          half: half,
        );
        expect(() => paintHaloOnce(painter), returnsNormally);
      }
    });

    test('intensity<=0 早退、paint 不丟', () {
      final painter = debugOrbitalHaloPainter(
        progress: 0.4,
        intensity: 0,
        half: PracticeHaloHalf.back,
      );
      expect(() => paintHaloOnce(painter), returnsNormally);
    });

    test('shouldRepaint 對 progress／intensity 敏感、同值不重畫', () {
      final base = debugOrbitalHaloPainter(
          progress: 0.3, intensity: 0.8, half: PracticeHaloHalf.back);
      final same = debugOrbitalHaloPainter(
          progress: 0.3, intensity: 0.8, half: PracticeHaloHalf.back);
      final diffProgress = debugOrbitalHaloPainter(
          progress: 0.55, intensity: 0.8, half: PracticeHaloHalf.back);
      final diffIntensity = debugOrbitalHaloPainter(
          progress: 0.3, intensity: 0.4, half: PracticeHaloHalf.back);

      expect(base.shouldRepaint(same), isFalse);
      expect(base.shouldRepaint(diffProgress), isTrue);
      expect(base.shouldRepaint(diffIntensity), isTrue);
    });
  });
}
