import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/domain/opener_access.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';

void main() {
  const canonicalOrder = ['extend', 'resonate', 'tease', 'humor', 'coldRead'];
  // Contract v2 Free 展示序：三實卡在前（extend/humor/tease）、兩鎖卡在後。
  const freeV2Order = ['extend', 'humor', 'tease', 'resonate', 'coldRead'];

  group('visibleOpenerCards', () {
    test('free v2 fresh generation: three unlocked cards then two locked', () {
      final cards = OpeningRescueScreen.visibleOpenerCards(
        openers: const {
          'extend': '延展句',
          'humor': '幽默句',
          'tease': '調情句',
        },
        recommendedPick: 'humor',
        isFreeUser: true,
      );

      expect(cards.map((c) => c.type).toList(), freeV2Order);

      for (final card in cards.take(3)) {
        expect(card.isLocked, isFalse, reason: '${card.type} 應為實卡');
        expect(card.content, isNotEmpty);
      }
      for (final card in cards.skip(3)) {
        expect(card.isLocked, isTrue, reason: '${card.type} 應為鎖卡');
        expect(card.isRecommended, isFalse);
        expect(card.content, isEmpty);
      }

      // 推薦 badge 可落在解鎖三型任一（不再 extend 專屬）。
      expect(
        cards.where((c) => c.isRecommended).map((c) => c.type),
        ['humor'],
      );
    });

    test('free legacy v1 cache with extend only still reads (no synthesized '
        'humor/tease)', () {
      final cards = OpeningRescueScreen.visibleOpenerCards(
        openers: const {'extend': '妳週末也會去爬山嗎？'},
        recommendedPick: 'extend',
        isFreeUser: true,
      );

      expect(
        cards.map((c) => c.type).toList(),
        ['extend', 'resonate', 'coldRead'],
      );
      expect(cards.first.isLocked, isFalse);
      expect(cards.first.isRecommended, isTrue);
      for (final card in cards.skip(1)) {
        expect(card.isLocked, isTrue);
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

    test('free replay of a paid-era draft: three unlocked, locked content '
        'never enters the spec', () {
      final cards = OpeningRescueScreen.visibleOpenerCards(
        openers: const {
          'extend': 'a',
          'resonate': 'b',
          'tease': 'c',
          'humor': 'd',
          'coldRead': 'e',
        },
        recommendedPick: 'coldRead',
        isFreeUser: true,
      );

      expect(cards.map((c) => c.type).toList(), freeV2Order);
      for (final card in cards.take(3)) {
        expect(card.isLocked, isFalse);
      }
      for (final card in cards.skip(3)) {
        expect(card.isLocked, isTrue);
        // 降級回看時 resonate/coldRead 內容連 spec 都不得進（leak-safe）。
        expect(card.content, isEmpty);
      }
      // 被鎖的推薦不得掛 badge。
      expect(cards.any((c) => c.isRecommended), isFalse);
    });

    test('free user with no usable opener gets no orphan locked cards', () {
      expect(
        OpeningRescueScreen.visibleOpenerCards(
          openers: const {},
          recommendedPick: null,
          isFreeUser: true,
        ),
        isEmpty,
      );
      // 只有 paid-only 內容（異常快取）也不得渲染孤兒鎖卡。
      expect(
        OpeningRescueScreen.visibleOpenerCards(
          openers: const {'coldRead': 'e'},
          recommendedPick: 'coldRead',
          isFreeUser: true,
        ),
        isEmpty,
      );
    });

    test('blank content counts as missing, not an unlocked card', () {
      final cards = OpeningRescueScreen.visibleOpenerCards(
        openers: const {'extend': '妳好', 'humor': '   '},
        recommendedPick: 'extend',
        isFreeUser: true,
      );

      expect(
        cards.map((c) => c.type).toList(),
        ['extend', 'resonate', 'coldRead'],
      );
    });
  });

  group('resultHasPaidStyles（legacy fallback only）', () {
    test('contract v2 free payload (extend/humor/tease) must NOT read as paid',
        () {
      expect(
        OpeningRescueScreen.resultHasPaidStyles(
          const {'extend': 'a', 'humor': 'b', 'tease': 'c'},
        ),
        isFalse,
      );
    });

    test('paid-only style with content is the authoritative legacy signal',
        () {
      expect(
        OpeningRescueScreen.resultHasPaidStyles(
          const {'extend': 'a', 'resonate': 'b'},
        ),
        isTrue,
      );
      expect(
        OpeningRescueScreen.resultHasPaidStyles(
          const {'extend': 'a', 'coldRead': 'e'},
        ),
        isTrue,
      );
      expect(
        OpeningRescueScreen.resultHasPaidStyles(const {'coldRead': '   '}),
        isFalse,
      );
      expect(OpeningRescueScreen.resultHasPaidStyles(const {}), isFalse);
    });

    test('paid-shaped fresh result renders unlocked even on a stale free '
        'subscription snapshot', () {
      const openers = {
        'extend': 'a',
        'resonate': 'b',
        'tease': 'c',
        'humor': 'd',
        'coldRead': 'e',
      };
      const staleSnapshotSaysFree = true;
      final isFreeForRender = staleSnapshotSaysFree &&
          !OpeningRescueScreen.resultHasPaidStyles(openers);

      final cards = OpeningRescueScreen.visibleOpenerCards(
        openers: openers,
        recommendedPick: 'tease',
        isFreeUser: isFreeForRender,
      );

      expect(cards.any((c) => c.isLocked), isFalse);
      expect(
        cards.where((c) => c.isRecommended).map((c) => c.type),
        ['tease'],
      );
    });
  });

  group('OpenerAccessContract（單點集合，不得漂移）', () {
    test('mirrors server OPENER_TYPES / OPENER_FREE_V2_TYPES', () {
      expect(OpenerAccessContract.contractVersion, 2);
      expect(OpenerAccessContract.canonicalPaidOrder, canonicalOrder);
      expect(
        OpenerAccessContract.freeUnlockedOrder,
        ['extend', 'humor', 'tease'],
      );
      expect(
        OpenerAccessContract.freeUnlockedTypes,
        {'extend', 'humor', 'tease'},
      );
      expect(OpenerAccessContract.paidOnlyOrder, ['resonate', 'coldRead']);
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
