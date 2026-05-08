import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/coach/coach_action_card_data.dart';
import 'package:vibesync/shared/widgets/coach_action_card.dart';

void main() {
  group('CoachActionCard', () {
    testWidgets('should render all 6 field rows when learningLink is non-null',
        (tester) async {
      String? tappedId;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoachActionCard(
              data: const CoachActionCardData(
                actionLabel: '故事框架',
                whyNow: '熱度 50，可以用故事框架往下展開',
                task: '用「場景 + 觀點/情緒 + 開放式提問」',
                suggestedLine: '聽起來最近壓力大，是哪一塊？',
                avoid: '別只丟一個開放式問句',
                learningLink: '14',
              ),
              onLearningLinkTap: (id) => tappedId = id,
            ),
          ),
        ),
      );

      expect(find.text('本回合怎麼接'), findsOneWidget);
      expect(find.textContaining('· 故事框架'), findsOneWidget);
      expect(find.textContaining('熱度 50'), findsOneWidget);
      expect(find.textContaining('場景 + 觀點'), findsOneWidget);
      expect(find.textContaining('別只丟一個開放式問句'), findsOneWidget);
      expect(find.text('試試這樣回'), findsOneWidget);
      expect(find.textContaining('聽起來最近壓力大'), findsOneWidget);
      expect(find.text('看 3 分鐘教學'), findsOneWidget);
      expect(tappedId, isNull);
    });

    testWidgets('should hide suggestedLine row when suggestedLine is null',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoachActionCard(
              data: const CoachActionCardData(
                actionLabel: '互動品質觀察',
                whyNow: '熱度 50，先別下定論',
                task: '觀察這次的節奏',
                suggestedLine: null,
                avoid: '不要急著貼標籤',
                learningLink: '18',
              ),
            ),
          ),
        ),
      );

      expect(find.text('試試這樣回'), findsNothing);
      expect(find.text('本回合怎麼接'), findsOneWidget);
      expect(find.text('看 3 分鐘教學'), findsOneWidget);
    });

    testWidgets('should hide CTA row when learningLink is null',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoachActionCard(
              data: const CoachActionCardData(
                actionLabel: '模糊邀約',
                whyNow: '熱度 88，可以給具體選項',
                task: '拋一個低門檻邀約',
                suggestedLine: '週六下午有空嗎？',
                avoid: '別要對方立刻決定',
                learningLink: null,
              ),
            ),
          ),
        ),
      );

      expect(find.text('看 3 分鐘教學'), findsNothing);
      expect(find.byKey(const Key('coach_action_learning_cta')), findsNothing);
      expect(find.text('本回合怎麼接'), findsOneWidget);
    });

    testWidgets(
        'should fire onLearningLinkTap with articleId when CTA is tapped',
        (tester) async {
      String? tappedId;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoachActionCard(
              data: const CoachActionCardData(
                actionLabel: '故事框架',
                whyNow: '熱度 50',
                task: '用故事框架展開',
                suggestedLine: null,
                avoid: '別只丟問句',
                learningLink: '14',
              ),
              onLearningLinkTap: (id) => tappedId = id,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('coach_action_learning_cta')));
      await tester.pump();

      expect(tappedId, '14');
    });
  });
}
