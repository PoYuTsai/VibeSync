// test/widget/features/onboarding/onboarding_handoff_applier_test.dart
//
// 登入後落地 MainShell 的交接收尾（OnboardingHandoffApplier）：
// - onboarding 轉換第 4 步：每次進首頁都補送登入前排隊的漏斗事件，
//   有沒有交接暫存都一樣，而且不擋導頁。
// - onboarding 轉換第 12 步：暫存改成有版本號的 JSON，「讀取 → 套用 → 確認成功
//   才清除」；舊鍵（onboarding_pending_goals／route）照樣套用。種目標只在
//   profile 全空時種、失敗靜默、絕不擋導頁。
// 讀取／清除／過期／同時只套用一次的細節在 onboarding_service_handoff_test。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/services/funnel_tracker.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/onboarding/domain/onboarding_intent.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_handoff_applier.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

const _uid = 'user-a';

class _FlushSpyTracker extends FunnelTracker {
  _FlushSpyTracker()
      : super(
          invoker: (fn, {required body}) async => 200,
          currentUserId: () => _uid,
        );

  var flushCalls = 0;

  @override
  Future<void> flushPending() async {
    flushCalls++;
  }
}

class _FakeRepo implements UserProfileRepository {
  final Map<String, UserProfile> byOwner = {};
  int saveCount = 0;
  bool throwOnSave = false;

  @override
  Future<UserProfile?> load(String ownerUserId) async => byOwner[ownerUserId];

  @override
  Future<void> save(UserProfile profile, String ownerUserId) async {
    if (throwOnSave) throw Exception('boom');
    byOwner[ownerUserId] = profile;
    saveCount++;
  }

  @override
  Future<void> clear(String ownerUserId) async {
    byOwner.remove(ownerUserId);
  }
}

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: Stack(
              children: [
                OnboardingHandoffApplier(),
                Text('home-screen'),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/partner/new',
          builder: (_, state) => Scaffold(
            body: Text(
              'partner-new-screen next=${state.uri.queryParameters['next']}',
            ),
          ),
        ),
        GoRoute(
          path: '/opener',
          builder: (_, __) => const Scaffold(body: Text('opener-screen')),
        ),
        GoRoute(
          path: '/practice-collection',
          builder: (_, state) => Scaffold(
            body: Text(
              'practice-collection-screen '
              'guide=${state.uri.queryParameters['guide']}',
            ),
          ),
        ),
      ],
    );

Future<GoRouter> _pumpHome(
  WidgetTester tester,
  FunnelTracker tracker, {
  _FakeRepo? repo,
}) async {
  final router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        funnelTrackerProvider.overrideWithValue(tracker),
        authUserProfileScopeProvider
            .overrideWith((ref) => Stream<String?>.value(_uid)),
        userProfileRepositoryProvider.overrideWithValue(repo ?? _FakeRepo()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // initState 排的 post-frame callback 跑完。
  await tester.pump();
  await tester.pumpAndSettle();
  return router;
}

Future<bool> _hasAnyStash() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.containsKey(OnboardingService.pendingHandoffKey) ||
      prefs.containsKey(OnboardingService.legacyPendingRouteKey) ||
      prefs.containsKey(OnboardingService.legacyPendingGoalsKey);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('登入後進首頁：沒有交接暫存也會補送一次', (tester) async {
    final tracker = _FlushSpyTracker();

    await _pumpHome(tester, tracker);

    expect(tracker.flushCalls, 1);
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('新格式暫存：照樣補送、導到第 1 頁選的地方，套用完才清掉', (tester) async {
    await OnboardingService.stashPendingHandoff(
      intent: OnboardingIntent.analyze,
      route: '/partner/new?next=screenshot',
      goalNames: const [],
      quizCorrect: true,
    );
    final tracker = _FlushSpyTracker();

    final router = await _pumpHome(tester, tracker);

    expect(tracker.flushCalls, 1);
    expect(find.text('partner-new-screen next=screenshot'), findsOneWidget);
    expect(await _hasAnyStash(), isFalse);
    expect(await OnboardingService.readPendingHandoff(), isNull);

    // push 在首頁之上：返回回到首頁。
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('新格式暫存的目標：profile 全空就照選的順序種進去', (tester) async {
    await OnboardingService.stashPendingHandoff(
      intent: OnboardingIntent.practice,
      route: '/practice-collection?guide=1',
      goalNames: const ['humorousReply', 'softInvite'],
      quizCorrect: false,
    );
    final repo = _FakeRepo();

    await _pumpHome(tester, _FlushSpyTracker(), repo: repo);

    expect(find.text('practice-collection-screen guide=1'), findsOneWidget);
    expect(repo.saveCount, 1);
    expect(
      repo.byOwner[_uid]!.practiceGoals,
      [PracticeGoal.humorousReply, PracticeGoal.softInvite],
    );
    expect(await _hasAnyStash(), isFalse);
  });

  testWidgets('舊版暫存（兩個舊鍵）：照舊種目標、導頁，套用完一起清掉', (tester) async {
    SharedPreferences.setMockInitialValues({
      OnboardingService.legacyPendingRouteKey: '/partner/new',
      OnboardingService.legacyPendingGoalsKey: <String>['softInvite'],
    });
    final repo = _FakeRepo();

    await _pumpHome(tester, _FlushSpyTracker(), repo: repo);

    expect(find.text('partner-new-screen next=null'), findsOneWidget);
    expect(repo.byOwner[_uid]!.practiceGoals, [PracticeGoal.softInvite]);
    expect(await _hasAnyStash(), isFalse);
  });

  testWidgets('已有非空 profile：絕不覆蓋，照樣導頁', (tester) async {
    await OnboardingService.stashPendingHandoff(
      intent: OnboardingIntent.opener,
      route: '/opener',
      goalNames: const ['softInvite'],
      quizCorrect: null,
    );
    final repo = _FakeRepo()
      ..byOwner[_uid] = UserProfile.create(
        notes: '使用者自己寫的',
        updatedAt: DateTime.utc(2026, 7, 1),
      );

    await _pumpHome(tester, _FlushSpyTracker(), repo: repo);

    expect(find.text('opener-screen'), findsOneWidget);
    expect(repo.saveCount, 0);
    expect(repo.byOwner[_uid]!.notes, '使用者自己寫的');
    expect(await _hasAnyStash(), isFalse);
  });

  testWidgets('種目標失敗：靜默放過，照樣導頁，暫存清掉（不會下次再導一次）', (tester) async {
    await OnboardingService.stashPendingHandoff(
      intent: OnboardingIntent.opener,
      route: '/opener',
      goalNames: const ['softInvite'],
      quizCorrect: true,
    );
    final repo = _FakeRepo()..throwOnSave = true;

    await _pumpHome(tester, _FlushSpyTracker(), repo: repo);

    expect(find.text('opener-screen'), findsOneWidget);
    expect(await _hasAnyStash(), isFalse);
  });

  testWidgets('認不得的目標名（舊版 enum 名）略過，其他照種', (tester) async {
    await OnboardingService.stashPendingHandoff(
      intent: OnboardingIntent.analyze,
      route: '/partner/new?next=screenshot',
      goalNames: const ['retiredGoal', 'buildCloseness'],
      quizCorrect: true,
    );
    final repo = _FakeRepo();

    await _pumpHome(tester, _FlushSpyTracker(), repo: repo);

    expect(repo.byOwner[_uid]!.practiceGoals, [PracticeGoal.buildCloseness]);
  });

  testWidgets('過期的暫存（超過 7 天）不套用：留在首頁、暫存清掉', (tester) async {
    await OnboardingService.stashPendingHandoff(
      intent: OnboardingIntent.analyze,
      route: '/partner/new?next=screenshot',
      goalNames: const ['softInvite'],
      quizCorrect: true,
      now: DateTime.now().subtract(const Duration(days: 8)),
    );
    final repo = _FakeRepo();

    await _pumpHome(tester, _FlushSpyTracker(), repo: repo);

    expect(find.text('home-screen'), findsOneWidget);
    expect(find.textContaining('partner-new-screen'), findsNothing);
    expect(repo.saveCount, 0);
    expect(await _hasAnyStash(), isFalse);
  });

  testWidgets('真的補送：登入前排隊的 onboarding 事件，進首頁後照原本的時間送出', (tester) async {
    String? uid;
    final sent = <Map<String, dynamic>>[];
    final queuedAt = DateTime.utc(2026, 10, 27, 1);
    var now = queuedAt;
    final tracker = FunnelTracker(
      invoker: (fn, {required body}) async {
        sent.add(body['event'] as Map<String, dynamic>);
        return 200;
      },
      currentUserId: () => uid,
      clock: () => now,
    );
    // onboarding 走在登入前：先排隊、不送。
    await tracker.track('onboarding_page_view', properties: {'page_index': 0});
    await tracker.track(
      'onboarding_intent',
      properties: {'intent': 'practice'},
    );
    await tracker.track(
      'onboarding_quiz_answer',
      properties: {'correct': true},
    );
    expect(sent, isEmpty);

    uid = _uid;
    now = queuedAt.add(const Duration(minutes: 3));
    await _pumpHome(tester, tracker);

    expect([
      for (final e in sent) e['event']
    ], [
      'onboarding_page_view',
      'onboarding_intent',
      'onboarding_quiz_answer',
    ]);
    expect(
      [for (final e in sent) e['clientTs']],
      everyElement(queuedAt.toIso8601String()),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(FunnelTracker.pendingQueueKey), isFalse);
  });
}
