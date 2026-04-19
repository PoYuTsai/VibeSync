import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';

void main() {
  group('GameStage', () {
    group('label', () {
      test('returns correct Chinese label for each stage', () {
        expect(GameStage.opening.label, '破冰階段');
        expect(GameStage.premise.label, '建立男女感');
        expect(GameStage.qualification.label, '讓她證明自己');
        expect(GameStage.narrative.label, '展現個人魅力');
        expect(GameStage.close.label, '準備邀約');
      });
    });

    group('description', () {
      test('returns correct description for each stage', () {
        expect(GameStage.opening.description, '你們還在破冰，先讓對話自然流動');
        expect(GameStage.premise.description, '開始有男女氛圍，可以加點張力');
        expect(GameStage.qualification.description, '她在向你證明自己，保持沉穩');
        expect(GameStage.narrative.description, '分享故事展現魅力，讓她更了解你');
        expect(GameStage.close.description, '時機對了，可以邀她出來見面');
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
