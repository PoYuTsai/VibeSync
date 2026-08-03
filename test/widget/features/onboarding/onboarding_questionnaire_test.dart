// test/widget/features/onboarding/onboarding_questionnaire_test.dart
//
// Tier 2 批 2：onboarding 一頁輕量問卷（互動風格單選＋練習目標最多 2）。
// 選擇存在 parent state（controlled widget），本頁不寫 Hive；
// 不選任何東西也能往下走（略過語意由 parent 的「下一步」承擔）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_questionnaire_page.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

Future<void> _pump(
  WidgetTester tester, {
  InteractionStyle? style,
  List<PracticeGoal> goals = const [],
  ValueChanged<InteractionStyle?>? onStyleChanged,
  ValueChanged<List<PracticeGoal>>? onGoalsChanged,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: OnboardingQuestionnairePage(
          selectedStyle: style,
          selectedGoals: goals,
          onStyleChanged: onStyleChanged ?? (_) {},
          onGoalsChanged: onGoalsChanged ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('渲染標題與 5+5 chips', (tester) async {
    await _pump(tester);

    expect(find.text('30 秒，讓建議更像你'), findsOneWidget);
    for (final label in ['穩重', '直接', '幽默', '溫柔', '俏皮']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in ['想約得出來', '想先能自在聊天，不要那麼緊繃', '想讓對話更幽默、有來有往', '想培養穩定的親近感', '想找到聊得來的對象、不設限交往']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('風格單選：點選回傳該 enum，再點同顆回傳 null', (tester) async {
    InteractionStyle? changed;
    await _pump(
      tester,
      onStyleChanged: (s) => changed = s,
    );

    await tester.tap(find.text('幽默'));
    expect(changed, InteractionStyle.humorous);

    await _pump(
      tester,
      style: InteractionStyle.humorous,
      onStyleChanged: (s) => changed = s,
    );
    await tester.tap(find.text('幽默'));
    expect(changed, isNull);
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
