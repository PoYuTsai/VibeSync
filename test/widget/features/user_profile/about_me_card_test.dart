import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/core/theme/app_colors.dart';
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
            builder: (_, __) => const Scaffold(body: Text('edit-page-stub')),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('文案誠實（About Me seam）：只宣稱教練 1:1 參考，不宣稱影響對話分析', (tester) async {
    await tester.pumpWidget(_harness(initial: null));
    await tester.pumpAndSettle();

    // 實際接線：buildForAnalysis 恆為 null，關於我只進 Coach 1:1。
    expect(find.text('教練 1:1 參考'), findsOneWidget);
    expect(find.text('影響 AI 建議'), findsNothing);
    expect(find.textContaining('教練 1:1 會參考'), findsWidgets);
  });

  testWidgets('empty profile shows prominent CTA', (tester) async {
    await tester.pumpWidget(_harness(initial: null));
    await tester.pumpAndSettle();
    expect(find.text('關於我'), findsOneWidget);
    expect(find.text('讓教練真的懂你'), findsOneWidget);
    expect(find.textContaining('填一下你卡在哪'), findsOneWidget);
    expect(find.text('開始設定'), findsOneWidget);

    final title = tester.widget<Text>(find.text('關於我'));
    final subtitle = tester.widget<Text>(find.text('讓教練真的懂你'));
    final body = tester.widget<Text>(find.textContaining('填一下你卡在哪'));
    expect(title.style?.color, AppColors.glassTextPrimary);
    expect(subtitle.style?.color, AppColors.glassTextPrimary);
    expect(body.style?.color, AppColors.glassTextSecondary);
  });

  testWidgets('filled profile shows summary lines for filled fields only',
      (tester) async {
    final profile = UserProfile.create(
      practiceGoals: const [
        PracticeGoal.softInvite,
        PracticeGoal.comfortableChat,
      ],
      topicSeeds: const [TopicSeed.coffee, TopicSeed.travel, TopicSeed.movies],
      updatedAt: DateTime.utc(2026, 4, 30),
    );
    await tester.pumpWidget(_harness(initial: profile));
    await tester.pumpAndSettle();
    expect(find.textContaining('想約得出來'), findsOneWidget);
    expect(find.textContaining('想先能自在聊天，不要那麼緊繃'), findsOneWidget);
    expect(find.textContaining('咖啡'), findsOneWidget);
    expect(find.text('編輯'), findsOneWidget);
    expect(find.text('開始設定'), findsNothing);
  });

  testWidgets('partial profile only renders filled fields', (tester) async {
    final profile = UserProfile.create(
      notes: '喜歡直接一點的講法',
      updatedAt: DateTime.utc(2026, 4, 30),
    );
    await tester.pumpWidget(_harness(initial: profile));
    await tester.pumpAndSettle();
    expect(find.textContaining('喜歡直接一點的講法'), findsOneWidget);
    expect(find.textContaining('卡在哪'), findsNothing);
    expect(find.textContaining('想達成什麼'), findsNothing);
    expect(find.textContaining('常聊話題'), findsNothing);
  });

  testWidgets('stuckPoints filled renders 卡在哪 summary line', (tester) async {
    final profile = UserProfile.create(
      stuckPoints: const [StuckPoint.fadesOut, StuckPoint.leftOnRead],
      updatedAt: DateTime.utc(2026, 8, 4),
    );
    await tester.pumpWidget(_harness(initial: profile));
    await tester.pumpAndSettle();
    expect(find.textContaining('卡在哪'), findsOneWidget);
    expect(find.textContaining('聊一聊就冷掉，不知道怎麼接下去、一直被已讀不回'), findsOneWidget);
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
