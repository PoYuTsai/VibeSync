import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibesync/features/coach_chat/data/providers/coach_chat_providers.dart';
import 'package:vibesync/features/user_profile/presentation/screens/about_me_screen.dart';
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

  testWidgets('selecting a stuck point flips primary button to 儲存',
      (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '聊一聊就冷掉，不知道怎麼接下去'));
    await tester.pumpAndSettle();
    expect(find.text('儲存'), findsOneWidget);
    expect(find.text('略過'), findsNothing);
  });

  testWidgets('文案誠實（About Me seam）：常聊話題不再宣稱幫 AI 發想', (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();

    // topic seeds 目前不進 AnalyzeChat（也不進教練），文案不得再宣稱
    // 「幫 AI 發想話題」；改成純紀錄語意。
    expect(find.textContaining('幫 AI 發想'), findsNothing);
    expect(find.text('最多 5 個，先記下你聊得來的話題。'), findsOneWidget);
  });

  testWidgets('A1（我現在卡在哪）與 A2（我想達成什麼）兩區塊都渲染，舊練習目標區塊已移除', (tester) async {
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
        practiceGoals: const [PracticeGoal.softInvite],
        topicSeeds: const [TopicSeed.coffee, TopicSeed.travel],
        customTopics: '日劇',
        notes: '慢熟',
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
    );
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();

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
        notes: '慢熟',
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
    );
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('about-me-notes')), '');
    await tester.pumpAndSettle();
    expect(find.text('清除設定'), findsOneWidget);
  });

  // 規格 PR-7：8/4 以前選過的互動風格看不到也改不到，不能擋住「清除設定」。
  testWidgets('只有舊互動風格的人：按鈕是「清除設定」，按了整筆清掉', (tester) async {
    final repo = FakeUserProfileRepo(
      initial: UserProfile.create(
        interactionStyle: InteractionStyle.steady,
        secondaryStyle: InteractionStyle.gentle,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
    );
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    final clearBtn = find.widgetWithText(ElevatedButton, '清除設定');
    expect(clearBtn, findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '儲存'), findsNothing);
    await tester.ensureVisible(clearBtn);
    await tester.pumpAndSettle();
    await tester.tap(clearBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(repo.byOwner[FakeUserProfileRepo.testUid], isNull);
  });

  testWidgets('有舊互動風格的人存檔：風格寫成 null，看得到的欄位照存、預覽不提風格', (tester) async {
    final repo = FakeUserProfileRepo(
      initial: UserProfile.create(
        interactionStyle: InteractionStyle.direct,
        secondaryStyle: InteractionStyle.humorous,
        notes: '慢熟',
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
    );
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '想約得出來'));
    await tester.pumpAndSettle();
    final saveBtn = find.widgetWithText(ElevatedButton, '儲存');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final saved = repo.byOwner[FakeUserProfileRepo.testUid]!;
    expect(saved.interactionStyle, isNull);
    expect(saved.secondaryStyle, isNull);
    expect(saved.notes, '慢熟');
    expect(saved.practiceGoals, [PracticeGoal.softInvite]);
    expect(find.textContaining('你想約得出來'), findsOneWidget);
    expect(find.textContaining('教練知道你平常偏'), findsNothing);
  });

  testWidgets('只填常聊話題存檔：不跳成長框架預覽（話題不會送給 AI）', (tester) async {
    final repo = FakeUserProfileRepo();
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '咖啡'));
    await tester.tap(find.widgetWithText(ChoiceChip, '咖啡'));
    await tester.pumpAndSettle();
    final saveBtn = find.widgetWithText(ElevatedButton, '儲存');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('已更新關於我'), findsOneWidget);
    expect(find.text('好，我知道了'), findsNothing);
    expect(find.textContaining('說話習慣'), findsNothing);
  });

  testWidgets('successful save pops back and shows snackbar 已更新關於我',
      (tester) async {
    final repo = FakeUserProfileRepo();
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '咖啡'));
    await tester.tap(find.widgetWithText(ChoiceChip, '咖啡'));
    await tester.pumpAndSettle();
    final saveBtn = find.widgetWithText(ElevatedButton, '儲存');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('已更新關於我'), findsOneWidget);
    expect(repo.byOwner[FakeUserProfileRepo.testUid]?.topicSeeds,
        contains(TopicSeed.coffee));
  });

  testWidgets('successful clear pops back and shows snackbar 已清除關於我設定',
      (tester) async {
    final repo = FakeUserProfileRepo(
      initial: UserProfile.create(
        notes: '慢熟',
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
    );
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('about-me-notes')), '');
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

  testWidgets('successful save with non-empty draft shows growth preview sheet',
      (tester) async {
    final repo = FakeUserProfileRepo();
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '想約得出來'));
    await tester.pumpAndSettle();
    final saveBtn = find.widgetWithText(ElevatedButton, '儲存');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('你想約得出來'), findsOneWidget);
  });

  testWidgets('清除設定不觸發成長框架預覽 sheet', (tester) async {
    final repo = FakeUserProfileRepo(
      initial: UserProfile.create(
        notes: '慢熟',
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
    );
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('about-me-notes')), '');
    await tester.pumpAndSettle();
    final clearBtn = find.widgetWithText(ElevatedButton, '清除設定');
    await tester.ensureVisible(clearBtn);
    await tester.pumpAndSettle();
    await tester.tap(clearBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('好，我知道了'), findsNothing);
  });

  testWidgets('略過不觸發成長框架預覽 sheet', (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    final skipBtn = find.widgetWithText(ElevatedButton, '略過');
    await tester.ensureVisible(skipBtn);
    await tester.pumpAndSettle();
    await tester.tap(skipBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('好，我知道了'), findsNothing);
  });

  testWidgets('save failure shows 儲存失敗，請再試一次 (no raw exception)',
      (tester) async {
    final repo = FakeUserProfileRepo()..throwOnSave = true;
    await tester.pumpWidget(aboutMeHarness(repo: repo));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '咖啡'));
    await tester.tap(find.widgetWithText(ChoiceChip, '咖啡'));
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

  // 規格 PR-5：說明文字講實話——只有教練 1:1 會把這些內容跟問題一起送給 AI；
  // 分析頁的本地行動卡還會讀卡點與目標（D4），所以只能說那些功能的 AI 不讀。
  testWidgets('上方說明：教練 1:1 會用，開場救星、對話分析和新話題的 AI 都不讀', (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '教練 1:1 會用這些設定了解你的處境，幫你往前推一步；開場救星、對話分析和新話題的 AI 都不讀這裡，也不會照你現在的樣子模仿你。',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('對話分析不讀這裡'), findsNothing);
  });

  testWidgets('底部隱私說明：只在用教練 1:1 時跟問題一起送給 AI', (tester) async {
    await tester.pumpWidget(aboutMeHarness(repo: FakeUserProfileRepo()));
    await tester.pumpAndSettle();
    const note =
        '這些內容只會在你使用教練 1:1 時，跟你的問題一起送給 AI 產生建議；不會給任何對象看到，開場救星、對話分析和新話題的 AI 也不會讀到。你可以隨時修改或清除。';
    await tester.scrollUntilVisible(
      find.text(note),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(note), findsOneWidget);
    expect(find.textContaining('貼近你的語氣'), findsNothing);
  });

  // 規格 PR-10「看看教練會讀到什麼」：顯示的就是教練實際會讀到的那段。
  group('看看教練會讀到什麼', () {
    Future<void> openPreview(WidgetTester tester) async {
      final link = find.byKey(const Key('about-me-coach-context-preview'));
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();
    }

    testWidgets('已儲存的內容：原文跟教練實際讀到的一字不差', (tester) async {
      final repo = FakeUserProfileRepo(
        initial: UserProfile.create(
          stuckPoints: const [StuckPoint.anxiousWontSend],
          practiceGoals: const [PracticeGoal.softInvite],
          notes: '不要太快邀約',
          updatedAt: DateTime.utc(2026, 10, 21),
        ),
      );
      await tester.pumpWidget(aboutMeHarness(repo: repo));
      await tester.pumpAndSettle();
      await openPreview(tester);

      final coachReads = await ProviderScope.containerOf(
        tester.element(find.byType(AboutMeScreen)),
      ).read(coachChatStyleContextProvider.future);
      final shown = tester
          .widget<SelectableText>(
            find.byKey(const Key('coach-context-preview-text')),
          )
          .data;
      expect(coachReads, isNotNull);
      expect(shown, coachReads);
      expect(find.text('這是你問教練 1:1 時，會跟問題一起送給 AI 的內容。'), findsOneWidget);
      expect(
          find.byKey(const Key('coach-context-preview-unsaved')), findsNothing);
    });

    testWidgets('還有修改沒儲存：提醒教練讀的是上次儲存的內容', (tester) async {
      final repo = FakeUserProfileRepo(
        initial: UserProfile.create(
          notes: '不要太快邀約',
          updatedAt: DateTime.utc(2026, 10, 21),
        ),
      );
      await tester.pumpWidget(aboutMeHarness(repo: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '想約得出來'));
      await tester.pumpAndSettle();
      await openPreview(tester);

      expect(
        find.text('你還有修改沒儲存；存檔之後，教練才會讀到新的內容。'),
        findsOneWidget,
      );
      final shown = tester
          .widget<SelectableText>(
            find.byKey(const Key('coach-context-preview-text')),
          )
          .data!;
      expect(shown, contains('不要太快邀約'));
      expect(shown, isNot(contains('想約得出來')), reason: '還沒存檔的不會送');
    });

    testWidgets('教練什麼都不會讀（沒填，或只填常聊話題）：不顯示入口', (tester) async {
      for (final initial in [
        null,
        UserProfile.create(
          topicSeeds: const [TopicSeed.coffee],
          updatedAt: DateTime.utc(2026, 10, 21),
        ),
      ]) {
        await tester.pumpWidget(
          aboutMeHarness(repo: FakeUserProfileRepo(initial: initial)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('about-me-coach-context-preview')),
          findsNothing,
        );
      }
    });
  });
}
