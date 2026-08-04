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

    await tester.tap(find.text('想讓對話更幽默、有來有往'));
    expect(changed, isNull);

    await tester.tap(find.text('想約得出來'));
    expect(changed, [PracticeGoal.comfortableChat]);
  });
}
