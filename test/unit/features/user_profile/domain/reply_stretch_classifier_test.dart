import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/domain/services/reply_stretch_classifier.dart';

void main() {
  const classifier = ReplyStretchClassifier();

  ReplyStretchLevel classify(InteractionStyle comfort, ReplyStyleKey reply) =>
      classifier.classify(comfortStyle: comfort, replyStyle: reply);

  group('穩重 steady', () {
    test('extend/coldRead 在舒適區內', () {
      expect(
        classify(InteractionStyle.steady, ReplyStyleKey.extend),
        ReplyStretchLevel.within,
      );
      expect(
        classify(InteractionStyle.steady, ReplyStyleKey.coldRead),
        ReplyStretchLevel.within,
      );
    });

    test('resonate/humor/tease 是延伸', () {
      expect(
        classify(InteractionStyle.steady, ReplyStyleKey.resonate),
        ReplyStretchLevel.stretch,
      );
      expect(
        classify(InteractionStyle.steady, ReplyStyleKey.humor),
        ReplyStretchLevel.stretch,
      );
      expect(
        classify(InteractionStyle.steady, ReplyStyleKey.tease),
        ReplyStretchLevel.stretch,
      );
    });
  });

  group('直接 direct', () {
    test('extend/coldRead 在舒適區內', () {
      expect(
        classify(InteractionStyle.direct, ReplyStyleKey.extend),
        ReplyStretchLevel.within,
      );
      expect(
        classify(InteractionStyle.direct, ReplyStyleKey.coldRead),
        ReplyStretchLevel.within,
      );
    });

    test('resonate/humor/tease 是延伸', () {
      expect(
        classify(InteractionStyle.direct, ReplyStyleKey.resonate),
        ReplyStretchLevel.stretch,
      );
      expect(
        classify(InteractionStyle.direct, ReplyStyleKey.humor),
        ReplyStretchLevel.stretch,
      );
      expect(
        classify(InteractionStyle.direct, ReplyStyleKey.tease),
        ReplyStretchLevel.stretch,
      );
    });
  });

  group('幽默 humorous', () {
    test('extend/coldRead/humor 在舒適區內', () {
      expect(
        classify(InteractionStyle.humorous, ReplyStyleKey.extend),
        ReplyStretchLevel.within,
      );
      expect(
        classify(InteractionStyle.humorous, ReplyStyleKey.coldRead),
        ReplyStretchLevel.within,
      );
      expect(
        classify(InteractionStyle.humorous, ReplyStyleKey.humor),
        ReplyStretchLevel.within,
      );
    });

    test('resonate/tease 是延伸', () {
      expect(
        classify(InteractionStyle.humorous, ReplyStyleKey.resonate),
        ReplyStretchLevel.stretch,
      );
      expect(
        classify(InteractionStyle.humorous, ReplyStyleKey.tease),
        ReplyStretchLevel.stretch,
      );
    });
  });

  group('溫柔 gentle', () {
    test('extend/resonate 在舒適區內', () {
      expect(
        classify(InteractionStyle.gentle, ReplyStyleKey.extend),
        ReplyStretchLevel.within,
      );
      expect(
        classify(InteractionStyle.gentle, ReplyStyleKey.resonate),
        ReplyStretchLevel.within,
      );
    });

    test('coldRead 是延伸', () {
      expect(
        classify(InteractionStyle.gentle, ReplyStyleKey.coldRead),
        ReplyStretchLevel.stretch,
      );
    });

    test('humor/tease 違反低壓不催促核心特質，跳太遠', () {
      expect(
        classify(InteractionStyle.gentle, ReplyStyleKey.humor),
        ReplyStretchLevel.far,
      );
      expect(
        classify(InteractionStyle.gentle, ReplyStyleKey.tease),
        ReplyStretchLevel.far,
      );
    });
  });

  group('有玩心 playful', () {
    test('extend/coldRead/humor/tease 在舒適區內', () {
      expect(
        classify(InteractionStyle.playful, ReplyStyleKey.extend),
        ReplyStretchLevel.within,
      );
      expect(
        classify(InteractionStyle.playful, ReplyStyleKey.coldRead),
        ReplyStretchLevel.within,
      );
      expect(
        classify(InteractionStyle.playful, ReplyStyleKey.humor),
        ReplyStretchLevel.within,
      );
      expect(
        classify(InteractionStyle.playful, ReplyStyleKey.tease),
        ReplyStretchLevel.within,
      );
    });

    test('resonate 是延伸', () {
      expect(
        classify(InteractionStyle.playful, ReplyStyleKey.resonate),
        ReplyStretchLevel.stretch,
      );
    });
  });

  test('每種舒適區風格至少有一則延伸建議（鎖住產品規則）', () {
    for (final style in InteractionStyle.values) {
      final hasStretch = ReplyStyleKey.values
          .any((k) => classify(style, k) == ReplyStretchLevel.stretch);
      expect(hasStretch, isTrue, reason: '$style 缺少 stretch 建議');
    }
  });

  group('classifyByTypeString（給 analyze-chat 字串 key 用的入口）', () {
    test('沒填舒適區風格 → null，不下任何判斷', () {
      expect(
        classifier.classifyByTypeString(comfortStyle: null, type: 'tease'),
        isNull,
      );
    });

    test('type 字串對照回 ReplyStyleKey 後結果與 classify 一致', () {
      for (final entry in const {
        'extend': ReplyStyleKey.extend,
        'resonate': ReplyStyleKey.resonate,
        'tease': ReplyStyleKey.tease,
        'humor': ReplyStyleKey.humor,
        'coldRead': ReplyStyleKey.coldRead,
      }.entries) {
        expect(
          classifier.classifyByTypeString(
            comfortStyle: InteractionStyle.gentle,
            type: entry.key,
          ),
          classifier.classify(
            comfortStyle: InteractionStyle.gentle,
            replyStyle: entry.value,
          ),
        );
      }
    });

    test('無法辨識的 type 字串 → null', () {
      expect(
        classifier.classifyByTypeString(
          comfortStyle: InteractionStyle.gentle,
          type: 'unknown',
        ),
        isNull,
      );
    });
  });
}
