import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/shared/widgets/game_stage_indicator.dart';

void main() {
  group('GameStageIndicator', () {
    testWidgets('displays current stage', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameStageIndicator(
              currentStage: GameStage.opening,
            ),
          ),
        ),
      );

      expect(find.text('破冰'), findsOneWidget);
    });

    testWidgets('displays premise stage correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameStageIndicator(
              currentStage: GameStage.premise,
            ),
          ),
        ),
      );

      expect(find.text('升溫'), findsOneWidget);
      expect(find.text('目前・升溫'), findsOneWidget);
    });

    testWidgets('keeps qualification stage copy neutral', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameStageIndicator(
              currentStage: GameStage.qualification,
              status: GameStageStatus.stuckFriend,
            ),
          ),
        ),
      );

      expect(find.text('深入'), findsOneWidget);
      expect(find.text('目前・深入'), findsOneWidget);
    });

    testWidgets('displays next step when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameStageIndicator(
              currentStage: GameStage.narrative,
              nextStep: '試著分享一個小故事',
            ),
          ),
        ),
      );

      expect(find.text('試著分享一個小故事'), findsOneWidget);
    });

    testWidgets('displays close stage correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameStageIndicator(
              currentStage: GameStage.close,
              status: GameStageStatus.canAdvance,
            ),
          ),
        ),
      );

      expect(find.text('邀約'), findsOneWidget);
      expect(find.text('目前・邀約'), findsOneWidget);
      expect(find.text('收尾'), findsNothing);
    });

    testWidgets('標題是目前互動重點，節奏狀態文案可見（互動重點 seam）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameStageIndicator(
              currentStage: GameStage.qualification,
              status: GameStageStatus.stuckFriend,
            ),
          ),
        ),
      );

      expect(find.text('目前互動重點'), findsOneWidget);
      expect(find.text('對話進度'), findsNothing);
      // stuckFriend 對使用者顯示「互動偏平」，不得出現「朋友」字樣。
      expect(find.textContaining('互動偏平'), findsOneWidget);
      expect(find.textContaining('朋友'), findsNothing);
    });

    testWidgets('只凸顯本次 stage：較早的點不畫成已完成成就', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameStageIndicator(
              currentStage: GameStage.close,
            ),
          ),
        ),
      );

      // 五個圓點中只有目前 stage 一顆是實心（closed-loop：五個點只凸顯
      // 本次焦點，不是完成式進度條）。
      final filledCircles = tester
          .widgetList<Container>(find.byType(Container))
          .where((container) {
        final decoration = container.decoration;
        return decoration is BoxDecoration &&
            decoration.shape == BoxShape.circle &&
            decoration.color != null &&
            decoration.color != Colors.transparent;
      }).length;
      expect(filledCircles, 1);
    });

    testWidgets('伴侶 reconnect：opening 顯示「重新連線」而不是破冰', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameStageIndicator(
              currentStage: GameStage.opening,
              reconnectWording: true,
            ),
          ),
        ),
      );

      expect(find.text('目前・重新連線'), findsOneWidget);
      expect(find.text('重新連線'), findsOneWidget);
      expect(find.text('破冰'), findsNothing);
    });
  });
}
