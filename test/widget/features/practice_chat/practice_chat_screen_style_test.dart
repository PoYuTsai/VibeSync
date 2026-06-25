import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';
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

  setUp(() {
    repo = _MemoryPracticeSessionRepository();
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

  testWidgets('empty room explains when quota is charged', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    expect(
      find.textContaining('首次 AI 回覆成功才扣 1 則'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('進來或送出失敗不扣'), findsOneWidget);
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

  testWidgets(
      'new room shows persona and difficulty controls before first message',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceSessionRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: PracticeChatScreen()),
      ),
    );

    // 開場前：首屏 hero 大卡 + 換一位 + 難度 chips（控制列在深色 scaffold 底）。
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
            subscriptionProvider
                .overrideWith((ref) => _SeededSubscriptionNotifier(subscription)),
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
      subscription: const SubscriptionState(tier: SubscriptionTierHelper.starter),
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

  testWidgets('點換一位 → 重置成開場前狀態（訊息清空、角色控制重現）', (tester) async {
    final controller = _SeededPracticeChatController(
      seed: debriefSeed(),
      repository: repo,
    );
    await pumpDebrief(tester, controller: controller);

    await tester.tap(find.text('換一位'));
    await tester.pump();

    final s = controller.currentState;
    expect(s.messages, isEmpty);
    expect(s.roundIndex, 1);
    expect(s.debrief, isNull);
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
    final controller = _SeededPracticeChatController(seed: seed, repository: repo);
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
    final controller = _SeededPracticeChatController(seed: seed, repository: repo);
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
}
