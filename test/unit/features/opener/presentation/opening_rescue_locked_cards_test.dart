import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';

void main() {
  const canonicalOrder = ['extend', 'resonate', 'tease', 'humor', 'coldRead'];

  group('visibleOpenerCards', () {
    test('free fresh generation fills 4 locked upsell cards after extend', () {
      final cards = OpeningRescueScreen.visibleOpenerCards(
        openers: const {'extend': '妳週末也會去爬山嗎？'},
        recommendedPick: 'extend',
        isFreeUser: true,
      );

      expect(cards.map((c) => c.type).toList(), canonicalOrder);

      final extend = cards.first;
      expect(extend.isLocked, isFalse);
      expect(extend.isRecommended, isTrue);
      expect(extend.content, '妳週末也會去爬山嗎？');

      for (final card in cards.skip(1)) {
        expect(card.isLocked, isTrue, reason: '${card.type} 應為鎖卡');
        expect(card.isRecommended, isFalse);
        expect(card.content, isEmpty);
      }
    });

    test('paid user with full payload gets 5 unlocked cards', () {
      final cards = OpeningRescueScreen.visibleOpenerCards(
        openers: const {
          'extend': 'a',
          'resonate': 'b',
          'tease': 'c',
          'humor': 'd',
          'coldRead': 'e',
        },
        recommendedPick: 'resonate',
        isFreeUser: false,
      );

      expect(cards.map((c) => c.type).toList(), canonicalOrder);
      expect(cards.any((c) => c.isLocked), isFalse);
      expect(
        cards.where((c) => c.isRecommended).map((c) => c.type),
        ['resonate'],
      );
    });

    test('paid user missing a sanitized-away style never sees locked cards',
        () {
      final cards = OpeningRescueScreen.visibleOpenerCards(
        openers: const {
          'extend': 'a',
          'resonate': 'b',
          'tease': 'c',
          'coldRead': 'e',
        },
        recommendedPick: 'extend',
        isFreeUser: false,
      );

      expect(
        cards.map((c) => c.type).toList(),
        ['extend', 'resonate', 'tease', 'coldRead'],
      );
      expect(cards.any((c) => c.isLocked), isFalse);
    });

    test('free replay of a paid-era draft keeps 5 cards with inline locks',
        () {
      final cards = OpeningRescueScreen.visibleOpenerCards(
        openers: const {
          'extend': 'a',
          'resonate': 'b',
          'tease': 'c',
          'humor': 'd',
          'coldRead': 'e',
        },
        recommendedPick: 'tease',
        isFreeUser: true,
      );

      expect(cards.map((c) => c.type).toList(), canonicalOrder);
      expect(cards.first.isLocked, isFalse);
      for (final card in cards.skip(1)) {
        expect(card.isLocked, isTrue);
      }
      // 鎖定風格不得掛 AI 推薦 badge（既有 !isLocked guard 行為）。
      expect(cards.any((c) => c.isRecommended), isFalse);
      // 降級回看的鎖卡內容仍在 spec 裡（顯示層鎖卡分支不 render content）。
      expect(cards[2].content, 'c');
    });

    test('free user with no usable opener gets no orphan locked cards', () {
      final cards = OpeningRescueScreen.visibleOpenerCards(
        openers: const {},
        recommendedPick: null,
        isFreeUser: true,
      );

      expect(cards, isEmpty);
    });

    test('blank content counts as missing, not an unlocked card', () {
      final cards = OpeningRescueScreen.visibleOpenerCards(
        openers: const {'extend': '妳好', 'resonate': '   '},
        recommendedPick: 'extend',
        isFreeUser: true,
      );

      final resonate = cards.firstWhere((c) => c.type == 'resonate');
      expect(resonate.isLocked, isTrue);
      expect(resonate.content, isEmpty);
    });
  });

  group('openerStylesHeaderSuffix', () {
    test('header count follows rendered card count', () {
      expect(
        OpeningRescueScreen.openerStylesHeaderSuffix(cardCount: 5),
        ' ・5 種風格',
      );
      expect(
        OpeningRescueScreen.openerStylesHeaderSuffix(cardCount: 4),
        ' ・4 種風格',
      );
    });
  });
}
