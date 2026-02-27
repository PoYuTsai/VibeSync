import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';
import 'package:vibesync/features/analysis/domain/services/game_stage_service.dart';

void main() {
  late GameStageService service;

  setUp(() {
    service = GameStageService();
  });

  group('GameStageService.getStageName', () {
    test('returns correct name for each stage', () {
      expect(service.getStageName(GameStage.opening), contains('Opening'));
      expect(service.getStageName(GameStage.premise), contains('Premise'));
      expect(service.getStageName(GameStage.qualification), contains('Qualification'));
      expect(service.getStageName(GameStage.narrative), contains('Narrative'));
      expect(service.getStageName(GameStage.close), contains('Close'));
    });

    test('includes Chinese name', () {
      expect(service.getStageName(GameStage.opening), contains('打開'));
      expect(service.getStageName(GameStage.premise), contains('前提'));
    });
  });

  group('GameStageService.getStageDescription', () {
    test('returns detailed description for each stage', () {
      expect(service.getStageDescription(GameStage.opening), contains('破冰'));
      expect(service.getStageDescription(GameStage.premise), contains('張力'));
      expect(service.getStageDescription(GameStage.qualification), contains('證明'));
      expect(service.getStageDescription(GameStage.narrative), contains('故事'));
      expect(service.getStageDescription(GameStage.close), contains('邀約'));
    });
  });

  group('GameStageService.getStageProgress', () {
    test('returns increasing progress for each stage', () {
      expect(service.getStageProgress(GameStage.opening), 0.2);
      expect(service.getStageProgress(GameStage.premise), 0.4);
      expect(service.getStageProgress(GameStage.qualification), 0.6);
      expect(service.getStageProgress(GameStage.narrative), 0.8);
      expect(service.getStageProgress(GameStage.close), 1.0);
    });

    test('progress increases monotonically', () {
      double lastProgress = 0;
      for (final stage in GameStage.values) {
        final progress = service.getStageProgress(stage);
        expect(progress, greaterThan(lastProgress));
        lastProgress = progress;
      }
    });
  });

  group('GameStageService.getStageColor', () {
    test('returns different colors for each stage', () {
      final colors = <Color>{};
      for (final stage in GameStage.values) {
        colors.add(service.getStageColor(stage));
      }
      expect(colors.length, GameStage.values.length);
    });

    test('getStageColorHex returns valid hex strings', () {
      for (final stage in GameStage.values) {
        final hex = service.getStageColorHex(stage);
        expect(hex, startsWith('#'));
        expect(hex.length, 7);
      }
    });
  });

  group('GameStageService.getStatusAdvice', () {
    test('returns advice for each status', () {
      expect(service.getStatusAdvice(GameStageStatus.normal), contains('繼續'));
      expect(service.getStatusAdvice(GameStageStatus.stuckFriend), contains('朋友框架'));
      expect(service.getStatusAdvice(GameStageStatus.canAdvance), contains('推進'));
      expect(service.getStatusAdvice(GameStageStatus.shouldRetreat), contains('放慢'));
    });
  });

  group('GameStageService.getStatusIcon', () {
    test('returns different icons for each status', () {
      expect(service.getStatusIcon(GameStageStatus.normal), Icons.check_circle_outline);
      expect(service.getStatusIcon(GameStageStatus.stuckFriend), Icons.warning_amber_outlined);
      expect(service.getStatusIcon(GameStageStatus.canAdvance), Icons.arrow_forward);
      expect(service.getStatusIcon(GameStageStatus.shouldRetreat), Icons.arrow_back);
    });
  });

  group('GameStageService.shouldSuggestNoReply', () {
    test('returns true when cold and in opening stage', () {
      expect(service.shouldSuggestNoReply(25, GameStage.opening), isTrue);
      expect(service.shouldSuggestNoReply(10, GameStage.opening), isTrue);
    });

    test('returns false when warm', () {
      expect(service.shouldSuggestNoReply(35, GameStage.opening), isFalse);
      expect(service.shouldSuggestNoReply(60, GameStage.opening), isFalse);
    });

    test('returns false when past opening stage', () {
      expect(service.shouldSuggestNoReply(25, GameStage.premise), isFalse);
      expect(service.shouldSuggestNoReply(25, GameStage.qualification), isFalse);
    });
  });

  group('GameStageService.shouldSuggestGiveUp', () {
    test('returns true when very cold and many rounds', () {
      expect(service.shouldSuggestGiveUp(15, GameStage.opening, 15), isTrue);
      expect(service.shouldSuggestGiveUp(10, GameStage.premise, 12), isTrue);
    });

    test('returns false when enthusiasm is higher', () {
      expect(service.shouldSuggestGiveUp(25, GameStage.opening, 15), isFalse);
    });

    test('returns false when round count is low', () {
      expect(service.shouldSuggestGiveUp(15, GameStage.opening, 5), isFalse);
    });
  });

  group('GameStageService.getNextStage', () {
    test('returns next stage when available', () {
      expect(service.getNextStage(GameStage.opening), GameStage.premise);
      expect(service.getNextStage(GameStage.premise), GameStage.qualification);
      expect(service.getNextStage(GameStage.qualification), GameStage.narrative);
      expect(service.getNextStage(GameStage.narrative), GameStage.close);
    });

    test('returns null for last stage', () {
      expect(service.getNextStage(GameStage.close), isNull);
    });
  });

  group('GameStageService.getPreviousStage', () {
    test('returns previous stage when available', () {
      expect(service.getPreviousStage(GameStage.close), GameStage.narrative);
      expect(service.getPreviousStage(GameStage.narrative), GameStage.qualification);
      expect(service.getPreviousStage(GameStage.qualification), GameStage.premise);
      expect(service.getPreviousStage(GameStage.premise), GameStage.opening);
    });

    test('returns null for first stage', () {
      expect(service.getPreviousStage(GameStage.opening), isNull);
    });
  });

  group('GameStageService.getShortName', () {
    test('returns single letter for each stage', () {
      expect(service.getShortName(GameStage.opening), 'O');
      expect(service.getShortName(GameStage.premise), 'P');
      expect(service.getShortName(GameStage.qualification), 'Q');
      expect(service.getShortName(GameStage.narrative), 'N');
      expect(service.getShortName(GameStage.close), 'C');
    });
  });
}
