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

      expect(find.text('打開'), findsOneWidget);
      expect(find.text('👋'), findsWidgets);
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

      expect(find.text('前提'), findsOneWidget);
      expect(find.text('進入男女框架'), findsOneWidget);
    });

    testWidgets('displays status badge', (tester) async {
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

      expect(find.text('卡在朋友框'), findsOneWidget);
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

      expect(find.text('收尾'), findsOneWidget);
      expect(find.text('準備邀約'), findsOneWidget);
      expect(find.text('可以推進'), findsOneWidget);
    });
  });
}
