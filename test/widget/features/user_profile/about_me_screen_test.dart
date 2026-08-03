import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

import '_harness.dart';

void main() {
  testWidgets('empty new profile primary button = 先跳過', (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    expect(find.text('略過'), findsOneWidget);
    expect(find.text('儲存'), findsNothing);
    expect(find.text('清除設定'), findsNothing);
  });

  testWidgets('selecting interaction style flips primary button to 儲存',
      (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.tap(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.pumpAndSettle();
    expect(find.text('儲存'), findsOneWidget);
    expect(find.text('略過'), findsNothing);
  });

  testWidgets('A1（我現在卡在哪）與 A2（我想達成什麼）兩區塊都渲染，舊練習目標區塊已移除',
      (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    expect(find.text('我現在卡在哪'), findsOneWidget);
    expect(find.text('我想達成什麼'), findsOneWidget);
    expect(find.text('練習目標'), findsNothing);
  });

  testWidgets('cannot select 3rd stuck point — shows 最多選 2 個 toast',
      (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '聊一聊就冷掉，不知道怎麼接下去'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '不知道怎麼開口約'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '會緊張、怕講錯話不敢傳'));
    await tester.pump();
    expect(find.text('最多選 2 個'), findsOneWidget);
  });

  testWidgets('cannot select 4th practice goal — shows 最多選 3 個 toast',
      (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '想約得出來'));
    await tester.tap(find.widgetWithText(ChoiceChip, '想先能自在聊天，不要那麼緊繃'));
    await tester.tap(find.widgetWithText(ChoiceChip, '想讓對話更幽默、有來有往'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '想培養穩定的親近感'));
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
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '想約得出來'));
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
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.tap(find.widgetWithText(ChoiceChip, '溫柔'));
    await tester.pumpAndSettle();
    expect(find.text('清除設定'), findsOneWidget);
  });

  testWidgets('successful save pops back and shows snackbar 已更新關於我',
      (tester) async {
    final repo = FakeUserProfileRepo();
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '直接'));
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
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '溫柔'));
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
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '直接'));
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

  testWidgets('新用戶（沒有 profile）不顯示最後更新時間', (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    expect(find.textContaining('最後更新'), findsNothing);
  });

  testWidgets('已有 profile → 顯示最後更新時間', (tester) async {
    final updatedAt = DateTime.utc(2026, 4, 30, 8);
    final repo = FakeUserProfileRepo(
      initial: UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        updatedAt: updatedAt,
      ),
    );
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();

    final expected = DateFormat('yyyy/M/d HH:mm').format(updatedAt.toLocal());
    expect(find.text('最後更新：$expected'), findsOneWidget);
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
