import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';

void main() {
  group('GameStage', () {
    group('label', () {
      test('returns correct Chinese label for each stage', () {
        expect(GameStage.opening.label, '打開');
        expect(GameStage.premise.label, '前提');
        expect(GameStage.qualification.label, '評估');
        expect(GameStage.narrative.label, '敘事');
        expect(GameStage.close.label, '收尾');
      });
    });

    group('description', () {
      test('returns correct description for each stage', () {
        expect(GameStage.opening.description, '破冰階段');
        expect(GameStage.premise.description, '進入男女框架');
        expect(GameStage.qualification.description, '她在證明自己');
        expect(GameStage.narrative.description, '說故事、個性樣本');
        expect(GameStage.close.description, '準備邀約');
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
        expect(GameStageStatus.normal.label, '正常進行');
        expect(GameStageStatus.stuckFriend.label, '卡在朋友框');
        expect(GameStageStatus.canAdvance.label, '可以推進');
        expect(GameStageStatus.shouldRetreat.label, '建議退回');
      });
    });
  });
}
