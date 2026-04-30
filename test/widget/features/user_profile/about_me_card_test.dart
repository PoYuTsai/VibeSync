import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/widgets/about_me_card.dart';

class _FakeRepo implements UserProfileRepository {
  _FakeRepo(UserProfile? initial) {
    if (initial != null) byOwner[_testUid] = initial;
  }
  static const _testUid = 'test-user';
  final Map<String, UserProfile> byOwner = {};

  @override
  Future<UserProfile?> load(String uid) async => byOwner[uid];
  @override
  Future<void> save(UserProfile p, String uid) async => byOwner[uid] = p;
  @override
  Future<void> clear(String uid) async => byOwner.remove(uid);
}

Widget _harness({UserProfile? initial}) {
  return ProviderScope(
    overrides: [
      userProfileRepositoryProvider.overrideWithValue(_FakeRepo(initial)),
      authUserProfileScopeProvider
          .overrideWith((ref) => Stream.value(_FakeRepo._testUid)),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: AboutMeCard()),
          ),
          GoRoute(
            path: '/profile/about-me',
            builder: (_, __) =>
                const Scaffold(body: Text('edit-page-stub')),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('empty profile shows prominent CTA', (tester) async {
    await tester.pumpWidget(_harness(initial: null));
    await tester.pumpAndSettle();
    expect(find.text('關於我'), findsOneWidget);
    expect(find.text('讓 VibeSync 更像你的教練'), findsOneWidget);
    expect(find.text('開始設定'), findsOneWidget);
  });

  testWidgets('filled profile shows summary lines for filled fields only',
      (tester) async {
    final profile = UserProfile.create(
      interactionStyle: InteractionStyle.gentle,
      practiceGoals: const [
        PracticeGoal.softInvite,
        PracticeGoal.reduceAnxiety,
      ],
      topicSeeds: const [TopicSeed.coffee, TopicSeed.travel, TopicSeed.movies],
      updatedAt: DateTime.utc(2026, 4, 30),
    );
    await tester.pumpWidget(_harness(initial: profile));
    await tester.pumpAndSettle();
    expect(find.textContaining('溫柔'), findsOneWidget);
    expect(find.textContaining('自然邀約'), findsOneWidget);
    expect(find.textContaining('降低焦慮'), findsOneWidget);
    expect(find.textContaining('咖啡'), findsOneWidget);
    expect(find.text('編輯'), findsOneWidget);
    expect(find.text('開始設定'), findsNothing);
  });

  testWidgets('partial profile only renders filled fields', (tester) async {
    final profile = UserProfile.create(
      interactionStyle: InteractionStyle.direct,
      updatedAt: DateTime.utc(2026, 4, 30),
    );
    await tester.pumpWidget(_harness(initial: profile));
    await tester.pumpAndSettle();
    expect(find.textContaining('直接'), findsOneWidget);
    expect(find.textContaining('練習目標'), findsNothing);
    expect(find.textContaining('常聊話題'), findsNothing);
  });

  testWidgets('tap 開始設定 navigates to /profile/about-me', (tester) async {
    await tester.pumpWidget(_harness(initial: null));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始設定'));
    await tester.pumpAndSettle();
    expect(find.text('edit-page-stub'), findsOneWidget);
  });

  testWidgets('tap 編輯 navigates to /profile/about-me', (tester) async {
    final profile = UserProfile.create(
      interactionStyle: InteractionStyle.steady,
      updatedAt: DateTime.utc(2026, 4, 30),
    );
    await tester.pumpWidget(_harness(initial: profile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('編輯'));
    await tester.pumpAndSettle();
    expect(find.text('edit-page-stub'), findsOneWidget);
  });
}
