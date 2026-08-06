// test/widget/features/onboarding/onboarding_questionnaire_test.dart
//
// Tier 2 批 2：onboarding 一頁輕量問卷（練習目標最多 2）。
// 選擇存在 parent state（controlled widget），本頁不寫 Hive；
// 不選任何東西也能往下走（略過語意由 parent 的「下一步」承擔）。
// 2026-08-04 拍板：互動風格題整條移除（那條線已從關於我頁與 prompt 拿掉），
// 問卷只留練習目標。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_questionnaire_page.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

Future<void> _pump(
  WidgetTester tester, {
  List<PracticeGoal> goals = const [],
  ValueChanged<List<PracticeGoal>>? onGoalsChanged,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: OnboardingQuestionnairePage(
          selectedGoals: goals,
          onGoalsChanged: onGoalsChanged ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('渲染標題與 5 個目標 chips，不再有互動風格題', (tester) async {
    await _pump(tester);

    expect(find.text('30 秒，讓建議更像你'), findsOneWidget);
    expect(find.text('你平常聊天的風格是？'), findsNothing);
    for (final label in ['穩重', '直接', '幽默', '溫柔', '俏皮']) {
      expect(find.text(label), findsNothing);
    }
    for (final label in ['想約得出來', '想先能自在聊天，不要那麼緊繃', '想讓對話更幽默、有來有往', '想培養穩定的親近感', '想找到聊得來的對象、不設限交往']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('目標最多 2：已選 2 顆時點第 3 顆不觸發變更', (tester) async {
    List<PracticeGoal>? changed;
    await _pump(
      tester,
      goals: const [PracticeGoal.softInvite, PracticeGoal.comfortableChat],
      onGoalsChanged: (g) => changed = g,
    );

    // 鏡像卡會複誦 chip 同字樣，點擊一律走 chip key 不走文字。
    await tester.tap(find.byKey(const ValueKey('onboarding-goal-humorousReply')));
    expect(changed, isNull);

    await tester.tap(find.byKey(const ValueKey('onboarding-goal-softInvite')));
    expect(changed, [PracticeGoal.comfortableChat]);
  });

  group('鏡像卡（選目標即時回饋）', () {
    const cardKey = ValueKey('onboarding-mirror-card');
    const softInvitePromise = '教練會幫你盯時機——聊到什麼熱度、出現哪些訊號，就是開口約的時候。';
    const comfortableChatPromise = '教練會先帶你把節奏放慢，不用急著接好每一句，聊起來自然不緊繃。';

    testWidgets('沒選目標：不出卡，也沒有 fallback 空話', (tester) async {
      await _pump(tester);

      expect(find.byKey(cardKey), findsNothing);
      expect(find.textContaining('教練會'), findsNothing);
    });

    testWidgets('選 1 個：卡片出現，chip 標籤＋承諾句逐字正確', (tester) async {
      await _pump(tester, goals: const [PracticeGoal.softInvite]);

      expect(find.byKey(cardKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(cardKey),
          matching: find.text('想約得出來'),
        ),
        findsOneWidget,
      );
      expect(find.text(softInvitePromise), findsOneWidget);
    });

    testWidgets('選 2 個：一目標一組，兩句承諾各自成句', (tester) async {
      await _pump(
        tester,
        goals: const [PracticeGoal.softInvite, PracticeGoal.comfortableChat],
      );

      expect(find.byKey(cardKey), findsOneWidget);
      expect(find.text(softInvitePromise), findsOneWidget);
      expect(find.text(comfortableChatPromise), findsOneWidget);
    });

    testWidgets('點選→出卡；再點取消回 0→卡片消失', (tester) async {
      var goals = <PracticeGoal>[];
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => OnboardingQuestionnairePage(
                selectedGoals: goals,
                onGoalsChanged: (g) => setState(() => goals = g),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const chip = ValueKey('onboarding-goal-softInvite');
      await tester.tap(find.byKey(chip));
      await tester.pumpAndSettle();
      expect(find.byKey(cardKey), findsOneWidget);
      expect(find.text(softInvitePromise), findsOneWidget);

      await tester.tap(find.byKey(chip));
      await tester.pumpAndSettle();
      expect(find.byKey(cardKey), findsNothing);
    });
  });
}
