import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/coach_follow_up/domain/entities/coach_follow_up_phase.dart';
import 'package:vibesync/features/coach_follow_up/domain/services/coach_follow_up_hint_resolver.dart';

void main() {
  group('CoachFollowUpHintResolver — prepareInvite', () {
    test('gameStage close + heatScore 70 resolves prepareInvite', () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          gameStage: GameStage.close,
          heatScore: 70,
        ),
      );

      expect(phase, CoachFollowUpPhase.prepareInvite);
    });

    test('gameStage close + heatScore 60 is not enough', () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          gameStage: GameStage.close,
          heatScore: 60,
        ),
      );

      expect(phase, isNull);
    });

    test('heatScore without close stage does not resolve prepareInvite', () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          gameStage: GameStage.narrative,
          heatScore: 90,
        ),
      );

      expect(phase, isNull);
    });
  });

  group('CoachFollowUpHintResolver — preDateReminder', () {
    test('recent message containing 明天 resolves preDateReminder', () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          recentMessageBodies: ['那我們明天晚上見'],
        ),
      );

      expect(phase, CoachFollowUpPhase.preDateReminder);
    });

    test('recent message containing 見面 resolves preDateReminder', () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          recentMessageBodies: ['這週末可以找個時間見面'],
        ),
      );

      expect(phase, CoachFollowUpPhase.preDateReminder);
    });

    test('meeting keyword beats generic invite readiness', () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          gameStage: GameStage.close,
          heatScore: 88,
          recentMessageBodies: ['好啊，那我們今晚碰面'],
        ),
      );

      expect(phase, CoachFollowUpPhase.preDateReminder);
    });
  });

  group('CoachFollowUpHintResolver — postDateReflection', () {
    test('long quiet + recent met keyword resolves postDateReflection', () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          recentMessageBodies: ['昨天見完覺得氣氛還不錯'],
          timeSinceLastMessage: Duration(hours: 18),
          averageMessageInterval: Duration(hours: 6),
        ),
      );

      expect(phase, CoachFollowUpPhase.postDateReflection);
    });

    test('met keyword without long quiet does not resolve postDateReflection',
        () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          recentMessageBodies: ['昨天見完覺得氣氛還不錯'],
          timeSinceLastMessage: Duration(hours: 7),
          averageMessageInterval: Duration(hours: 6),
        ),
      );

      expect(phase, isNull);
    });

    test('long quiet without met keyword does not resolve postDateReflection',
        () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          recentMessageBodies: ['最近工作比較忙'],
          timeSinceLastMessage: Duration(hours: 18),
          averageMessageInterval: Duration(hours: 6),
        ),
      );

      expect(phase, isNull);
    });
  });

  group('CoachFollowUpHintResolver — no signal and stable key guards', () {
    test('no signal resolves null', () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          gameStage: GameStage.opening,
          heatScore: 30,
          recentMessageBodies: ['你好'],
        ),
      );

      expect(phase, isNull);
    });

    test('does not treat 繁中 stage label as any phase signal', () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          gameStage: null,
          heatScore: 70,
          recentMessageBodies: ['準備邀約'],
        ),
      );

      expect(phase, isNull);
    });

    test('empty average interval does not divide by zero', () {
      final phase = CoachFollowUpHintResolver.resolve(
        const CoachFollowUpHintInput(
          recentMessageBodies: ['昨天見完'],
          timeSinceLastMessage: Duration(hours: 18),
          averageMessageInterval: Duration.zero,
        ),
      );

      expect(phase, isNull);
    });
  });
}
