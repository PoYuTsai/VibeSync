import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

import '_harness.dart';

void main() {
  testWidgets('empty new profile primary button = 先跳過', (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    expect(find.text('先跳過'), findsOneWidget);
    expect(find.text('儲存'), findsNothing);
    expect(find.text('清除設定'), findsNothing);
  });

  testWidgets('selecting interaction style flips primary button to 儲存',
      (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.pumpAndSettle();
    expect(find.text('儲存'), findsOneWidget);
    expect(find.text('先跳過'), findsNothing);
  });

  testWidgets('cannot select 4th practice goal — shows 最多選 3 個 toast',
      (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '自然邀約'));
    await tester.tap(find.widgetWithText(ChoiceChip, '降低焦慮'));
    await tester.tap(find.widgetWithText(ChoiceChip, '幽默回覆'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '培養親近'));
    await tester.pump();
    expect(find.text('最多選 3 個'), findsOneWidget);
  });

  testWidgets('cannot select 6th topic seed — shows 最多選 5 個 toast',
      (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    final seeds = ['咖啡', '旅行', '健身', '音樂', '電影'];
    for (final s in seeds) {
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, s));
      await tester.tap(find.widgetWithText(ChoiceChip, s));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '攝影'));
    await tester.tap(find.widgetWithText(ChoiceChip, '攝影'));
    await tester.pump();
    expect(find.text('最多選 5 個'), findsOneWidget);
  });

  testWidgets('customTopics enforces 60-char limit', (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('about-me-custom-topics'));
    expect(field, findsOneWidget);
    final tf = tester.widget<TextField>(field);
    expect(tf.maxLength, 60);
  });

  testWidgets('notes enforces 100-char limit', (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('about-me-notes'));
    expect(field, findsOneWidget);
    final tf = tester.widget<TextField>(field);
    expect(tf.maxLength, 100);
  });

  testWidgets('existing profile pre-fills all fields', (tester) async {
    final repo = FakeUserProfileRepo(
      initial: UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        practiceGoals: const [PracticeGoal.softInvite],
        topicSeeds: const [TopicSeed.coffee, TopicSeed.travel],
        customTopics: '日劇',
        notes: '慢熟',
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
    );
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();

    final styleChip =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '溫柔'));
    expect(styleChip.selected, isTrue);
    final goalChip =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '自然邀約'));
    expect(goalChip.selected, isTrue);
    expect(find.text('日劇'), findsOneWidget);
    expect(find.text('慢熟'), findsOneWidget);
    expect(find.text('儲存'), findsOneWidget);
  });

  testWidgets('clearing all fields on existing profile shows 清除設定',
      (tester) async {
    final repo = FakeUserProfileRepo(
      initial: UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
    );
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    // Tap the same chip again to deselect
    await tester.tap(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.pumpAndSettle();
    expect(find.text('清除設定'), findsOneWidget);
  });

  testWidgets('successful save pops back and shows snackbar 已更新關於我',
      (tester) async {
    final repo = FakeUserProfileRepo();
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '直接'));
    await tester.pumpAndSettle();
    final saveBtn = find.widgetWithText(ElevatedButton, '儲存');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('已更新關於我'), findsOneWidget);
    expect(repo.byOwner[FakeUserProfileRepo.testUid]?.interactionStyle,
        InteractionStyle.direct);
  });

  testWidgets('successful clear pops back and shows snackbar 已清除關於我設定',
      (tester) async {
    final repo = FakeUserProfileRepo(
      initial: UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
    );
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.pumpAndSettle();
    final clearBtn = find.widgetWithText(ElevatedButton, '清除設定');
    await tester.ensureVisible(clearBtn);
    await tester.pumpAndSettle();
    await tester.tap(clearBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('已清除關於我設定'), findsOneWidget);
    expect(repo.byOwner[FakeUserProfileRepo.testUid], isNull);
  });

  testWidgets('save failure shows 儲存失敗，請再試一次 (no raw exception)',
      (tester) async {
    final repo = FakeUserProfileRepo()..throwOnSave = true;
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '直接'));
    await tester.pumpAndSettle();
    final saveBtn = find.widgetWithText(ElevatedButton, '儲存');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('儲存失敗，請再試一次'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('bottom privacy note 這些設定只用來讓建議更貼近你的語氣 renders',
      (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('這些設定只用來'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('這些設定只用來'), findsOneWidget);
  });
}
