// test/widget/features/onboarding/onboarding_profile_seed_test.dart
//
// 已登入時走完 onboarding（少見：這支手機沒看過 onboarding）直接種「關於我」：
// 「關於我」重新定位（2026-08-03 report）後只種問卷目標；路徑（第 1 頁）有
// onboarding_intent 漏斗事件記，不寫進 profile。目標全略過就不建任何資料。
// 鐵則：只在 profile 全空時種、失敗靜默放過、絕不擋導頁。
// onboarding 轉換第 12 步：4 頁版，種子在最後一頁按「繼續」時寫。
// 未登入的情況走暫存交接，見 onboarding_handoff_applier_test。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/onboarding/data/onboarding_quiz.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';
import 'package:vibesync/features/onboarding/domain/onboarding_intent.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_intent_page.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

import '../../../helpers/chat_quiz_test_content.dart';
import '../../../helpers/onboarding_test_harness.dart';

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

late ChatQuizCatalog _catalog;

/// 已登入：選路徑 → 作答 → 目標頁（選 [goals]）→ 最後一頁。
Future<void> _walkToFinish(
  WidgetTester tester, {
  required _FakeRepo repo,
  OnboardingIntent intent = OnboardingIntent.analyze,
  List<PracticeGoal> goals = const [],
}) async {
  await pumpOnboardingApp(
    tester,
    catalog: _catalog,
    signedInUid: _uid,
    profileRepository: repo,
  );
  await chooseIntent(tester, intent);
  final question = _catalog.findQuestion(kOnboardingQuizQuestionId)!;
  await tester.tap(
    find.byKey(ValueKey('onboarding-quiz-choice-${question.choices.first.id}')),
  );
  await tester.pumpAndSettle();
  await tapLabel(tester, OnboardingScreen.nextLabel);
  for (final goal in goals) {
    await tester.tap(find.byKey(ValueKey('onboarding-goal-${goal.name}')));
    await tester.pumpAndSettle();
  }
  await tapLabel(tester, OnboardingScreen.nextLabel);
  expect(find.text(OnboardingScreen.finishLabel), findsOneWidget);
}

void main() {
  setUpAll(() async {
    _catalog = await loadProductionChatQuizCatalog();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OnboardingService.reset();
  });

  testWidgets('目標全略過＋繼續 → 不建任何 profile，照常導頁', (tester) async {
    final repo = _FakeRepo();
    await _walkToFinish(tester, repo: repo);

    await tapLabel(tester, OnboardingScreen.finishLabel);

    expect(find.text('partner-new-screen next=screenshot'), findsOneWidget);
    expect(repo.saveCount, 0);
    expect(repo.byOwner[_uid], isNull);
  });

  testWidgets('有選目標＋繼續 → 一筆種子只帶 goals（照選的順序），notes 不寫', (tester) async {
    final repo = _FakeRepo();
    await _walkToFinish(
      tester,
      repo: repo,
      intent: OnboardingIntent.practice,
      goals: const [PracticeGoal.humorousReply, PracticeGoal.softInvite],
    );

    await tapLabel(tester, OnboardingScreen.finishLabel);

    expect(find.text('practice-collection-screen guide=1'), findsOneWidget);
    expect(repo.saveCount, 1);
    final saved = repo.byOwner[_uid]!;
    expect(
      saved.practiceGoals,
      [PracticeGoal.humorousReply, PracticeGoal.softInvite],
    );
    expect(saved.interactionStyle, isNull);
    expect(saved.notes, isNull);
  });

  testWidgets('已有非空 profile → 絕不覆蓋（即使選了目標）', (tester) async {
    final repo = _FakeRepo();
    repo.byOwner[_uid] = UserProfile.create(
      interactionStyle: InteractionStyle.humorous,
      notes: '使用者自己寫的',
      updatedAt: DateTime.utc(2026, 7, 1),
    );
    await _walkToFinish(
      tester,
      repo: repo,
      goals: const [PracticeGoal.softInvite],
    );

    await tapLabel(tester, OnboardingScreen.finishLabel);

    expect(find.text('partner-new-screen next=screenshot'), findsOneWidget);
    expect(repo.saveCount, 0);
    expect(repo.byOwner[_uid]?.notes, '使用者自己寫的');
  });

  testWidgets('種子寫入失敗 → 靜默放過，onboarding 照常完成並導頁', (tester) async {
    final repo = _FakeRepo()..throwOnSave = true;
    await _walkToFinish(
      tester,
      repo: repo,
      intent: OnboardingIntent.opener,
      goals: const [PracticeGoal.softInvite],
    );

    await tapLabel(tester, OnboardingScreen.finishLabel);

    expect(find.text(openerStubText), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isTrue);
  });

  testWidgets('「先逛逛」→ 不種任何種子，落在首頁', (tester) async {
    final repo = _FakeRepo();
    await pumpOnboardingApp(
      tester,
      catalog: _catalog,
      signedInUid: _uid,
      profileRepository: repo,
    );

    await tapLabel(tester, OnboardingIntentPage.browseLabel);

    expect(find.text(mainShellStubText), findsOneWidget);
    expect(repo.saveCount, 0);
  });
}
