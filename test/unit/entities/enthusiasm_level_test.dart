import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/enthusiasm_level.dart';

void main() {
  group('EnthusiasmLevel', () {
    group('fromScore', () {
      test('returns cold for score 0-30', () {
        expect(EnthusiasmLevel.fromScore(0), EnthusiasmLevel.cold);
        expect(EnthusiasmLevel.fromScore(15), EnthusiasmLevel.cold);
        expect(EnthusiasmLevel.fromScore(30), EnthusiasmLevel.cold);
      });

      test('returns warm for score 31-60', () {
        expect(EnthusiasmLevel.fromScore(31), EnthusiasmLevel.warm);
        expect(EnthusiasmLevel.fromScore(45), EnthusiasmLevel.warm);
        expect(EnthusiasmLevel.fromScore(60), EnthusiasmLevel.warm);
      });

      test('returns hot for score 61-80', () {
        expect(EnthusiasmLevel.fromScore(61), EnthusiasmLevel.hot);
        expect(EnthusiasmLevel.fromScore(70), EnthusiasmLevel.hot);
        expect(EnthusiasmLevel.fromScore(80), EnthusiasmLevel.hot);
      });

      test('returns veryHot for score 81-100', () {
        expect(EnthusiasmLevel.fromScore(81), EnthusiasmLevel.veryHot);
        expect(EnthusiasmLevel.fromScore(90), EnthusiasmLevel.veryHot);
        expect(EnthusiasmLevel.fromScore(100), EnthusiasmLevel.veryHot);
      });
    });

    group('label', () {
      test('returns correct Chinese label for each level', () {
        expect(EnthusiasmLevel.cold.label, '冰點');
        expect(EnthusiasmLevel.warm.label, '溫和');
        expect(EnthusiasmLevel.hot.label, '熱情');
        expect(EnthusiasmLevel.veryHot.label, '高熱');
      });
    });

    group('emoji', () {
      test('returns correct emoji for each level', () {
        expect(EnthusiasmLevel.cold.emoji, '❄️');
        expect(EnthusiasmLevel.warm.emoji, '🌤️');
        expect(EnthusiasmLevel.hot.emoji, '🔥');
        expect(EnthusiasmLevel.veryHot.emoji, '💖');
      });
    });
  });
}
