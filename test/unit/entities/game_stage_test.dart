import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/game_stage.dart';

void main() {
  group('GameStage', () {
    group('label', () {
      test('returns correct Chinese label for each stage', () {
        expect(GameStage.opening.label, '破冰階段');
        expect(GameStage.premise.label, '建立男女感');
        expect(GameStage.qualification.label, '互相評估');
        expect(GameStage.narrative.label, '展現個人魅力');
        expect(GameStage.close.label, '準備邀約');
      });
    });

    group('description', () {
      test('returns correct description for each stage', () {
        expect(GameStage.opening.description, '你們還在破冰，先讓對話自然流動');
        expect(GameStage.premise.description, '開始有男女氛圍，可以加點張力');
        expect(GameStage.qualification.description, '她在觀察你，你也判斷是否同頻');
        expect(GameStage.narrative.description, '分享故事展現魅力，讓她更了解你');
        expect(GameStage.close.description, '時機對了，可以邀她出來見面');
      });
    });

    group('emoji', () {
      test('no longer exposes emoji (titles use Tabler icons)', () {});
    });
  });

  group('GameStage.tryFromString', () {
    test('accepts exactly the five legal stage names (trimmed)', () {
      expect(GameStage.tryFromString('opening'), GameStage.opening);
      expect(GameStage.tryFromString('premise'), GameStage.premise);
      expect(GameStage.tryFromString('qualification'), GameStage.qualification);
      expect(GameStage.tryFromString('narrative'), GameStage.narrative);
      expect(GameStage.tryFromString(' close '), GameStage.close);
    });

    test('missing or unknown values never default to opening', () {
      expect(GameStage.tryFromString(null), isNull);
      expect(GameStage.tryFromString(''), isNull);
      expect(GameStage.tryFromString('   '), isNull);
      expect(GameStage.tryFromString('vibing hard'), isNull);
      expect(GameStage.tryFromString('Opening'), isNull); // 大小寫敏感
      expect(GameStage.tryFromString('破冰階段'), isNull);
    });
  });

  group('GameStageStatus', () {
    group('label', () {
      test('節奏狀態可見文案（閉環拍板）：不得出現「朋友區／偏朋友」字樣', () {
        expect(GameStageStatus.normal.label, '維持節奏');
        expect(GameStageStatus.stuckFriend.label, '互動偏平');
        expect(GameStageStatus.canAdvance.label, '可以推進');
        expect(GameStageStatus.shouldRetreat.label, '放慢一點');
        for (final status in GameStageStatus.values) {
          expect(status.label.contains('朋友'), isFalse);
        }
      });
    });
  });
}
