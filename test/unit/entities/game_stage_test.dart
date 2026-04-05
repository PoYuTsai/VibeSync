import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';

void main() {
  group('GameStage', () {
    group('label', () {
      test('returns correct Chinese label for each stage', () {
        expect(GameStage.opening.label, '初識');
        expect(GameStage.premise.label, '熟悉中');
        expect(GameStage.qualification.label, '深入了解');
        expect(GameStage.narrative.label, '分享故事');
        expect(GameStage.close.label, '見面邀約');
      });
    });

    group('description', () {
      test('returns correct description for each stage', () {
        expect(GameStage.opening.description, '剛開始聊天');
        expect(GameStage.premise.description, '慢慢熟悉對方');
        expect(GameStage.qualification.description, '彼此更了解中');
        expect(GameStage.narrative.description, '交換故事和想法');
        expect(GameStage.close.description, '可以約出來了');
      });
    });

    group('emoji', () {
      test('returns correct emoji for each stage', () {
        expect(GameStage.opening.emoji, '👋');
        expect(GameStage.premise.emoji, '💫');
        expect(GameStage.qualification.emoji, '✨');
        expect(GameStage.narrative.emoji, '📖');
        expect(GameStage.close.emoji, '🎯');
      });
    });
  });

  group('GameStageStatus', () {
    group('label', () {
      test('returns correct label for each status', () {
        expect(GameStageStatus.normal.label, '進展順利');
        expect(GameStageStatus.stuckFriend.label, '偏向朋友');
        expect(GameStageStatus.canAdvance.label, '可以更進一步');
        expect(GameStageStatus.shouldRetreat.label, '放慢節奏');
      });
    });
  });
}
