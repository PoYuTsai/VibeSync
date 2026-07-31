// test/widget/features/onboarding/onboarding_profile_seed_test.dart
//
// 轉化診斷 Tier 1-3：分流頁答案是 onboarding 全流程唯一的個人化訊號，
// 過去只拿來導頁就丟掉。現在轉寫進「關於我」notes（誠實轉寫、關於我頁
// 看得到改得掉），餵 effective style prompt，讓第一次 AI 呼叫不再 generic。
// 鐵則：只在 profile 全空時種、失敗靜默放過、絕不擋導頁。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

const _uid = 'test-uid';

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

GoRouter _stubRouter() => GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('main-shell')),
        ),
        GoRoute(
          path: '/partner/new',
          builder: (_, __) => const Scaffold(body: Text('partner-new-screen')),
        ),
        GoRoute(
          path: '/practice-collection',
          builder: (_, __) =>
              const Scaffold(body: Text('practice-collection-screen')),
        ),
      ],
    );

Future<void> _pumpToBranchingPage(
  WidgetTester tester, {
  required _FakeRepo repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileRepositoryProvider.overrideWithValue(repo),
        authUserProfileScopeProvider.overrideWith((ref) => Stream.value(_uid)),
      ],
      child: MaterialApp.router(routerConfig: _stubRouter()),
    ),
  );
  await tester.pumpAndSettle();
  for (var i = 0; i < 5; i++) {
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('答「有」→ notes 種下有對象轉寫並照常導頁', (tester) async {
    final repo = _FakeRepo();
    await _pumpToBranchingPage(tester, repo: repo);

    await tester.tap(find.text('有，幫我分析對話'));
    await tester.pumpAndSettle();

    expect(find.text('partner-new-screen'), findsOneWidget);
    expect(repo.byOwner[_uid]?.notes, '目前有正在聊的對象');
  });

  testWidgets('答「還沒」→ notes 種下練習轉寫並照常導頁', (tester) async {
    final repo = _FakeRepo();
    await _pumpToBranchingPage(tester, repo: repo);

    await tester.tap(find.text('還沒，先去練習'));
    await tester.pumpAndSettle();

    expect(find.text('practice-collection-screen'), findsOneWidget);
    expect(repo.byOwner[_uid]?.notes, '還沒有固定聊天對象，想先透過練習提升');
  });

  testWidgets('已有非空 profile → 絕不覆蓋', (tester) async {
    final repo = _FakeRepo();
    final existing = UserProfile.create(
      interactionStyle: InteractionStyle.humorous,
      notes: '使用者自己寫的',
      updatedAt: DateTime.utc(2026, 7, 1),
    );
    repo.byOwner[_uid] = existing;
    await _pumpToBranchingPage(tester, repo: repo);

    await tester.tap(find.text('有，幫我分析對話'));
    await tester.pumpAndSettle();

    expect(find.text('partner-new-screen'), findsOneWidget);
    expect(repo.saveCount, 0);
    expect(repo.byOwner[_uid]?.notes, '使用者自己寫的');
  });

  testWidgets('種子寫入失敗 → 靜默放過，onboarding 照常完成', (tester) async {
    final repo = _FakeRepo()..throwOnSave = true;
    await _pumpToBranchingPage(tester, repo: repo);

    await tester.tap(find.text('還沒，先去練習'));
    await tester.pumpAndSettle();

    expect(find.text('practice-collection-screen'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isTrue);
  });

  testWidgets('問卷有選＋答「有」→ 一筆合併種子帶 style/goals/notes（批 2）', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileRepositoryProvider.overrideWithValue(repo),
          authUserProfileScopeProvider
              .overrideWith((ref) => Stream.value(_uid)),
        ],
        child: MaterialApp.router(routerConfig: _stubRouter()),
      ),
    );
    await tester.pumpAndSettle();

    // 滑 3 次到問卷頁（index 3），選風格＋一個目標。
    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
    }
    expect(find.text('30 秒，讓建議更像你'), findsOneWidget);
    await tester.tap(find.text('幽默'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自然邀約'));
    await tester.pumpAndSettle();

    // 再滑 2 次到分流頁，答「有」。
    for (var i = 0; i < 2; i++) {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('有，幫我分析對話'));
    await tester.pumpAndSettle();

    expect(repo.saveCount, 1);
    final saved = repo.byOwner[_uid]!;
    expect(saved.interactionStyle, InteractionStyle.humorous);
    expect(saved.practiceGoals, [PracticeGoal.softInvite]);
    expect(saved.notes, '目前有正在聊的對象');
  });

  testWidgets('「略過」→ 不種任何種子', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileRepositoryProvider.overrideWithValue(repo),
          authUserProfileScopeProvider
              .overrideWith((ref) => Stream.value(_uid)),
        ],
        child: MaterialApp.router(routerConfig: _stubRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('略過'));
    await tester.pumpAndSettle();

    expect(find.text('main-shell'), findsOneWidget);
    expect(repo.saveCount, 0);
  });
}
