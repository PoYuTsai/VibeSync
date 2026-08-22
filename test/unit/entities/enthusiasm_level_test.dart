import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
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

      test('returns veryHot for visible score 81-90（legacy 超界亦同段）', () {
        expect(EnthusiasmLevel.fromScore(81), EnthusiasmLevel.veryHot);
        expect(EnthusiasmLevel.fromScore(90), EnthusiasmLevel.veryHot);
        expect(EnthusiasmLevel.fromScore(100), EnthusiasmLevel.veryHot);
      });

      test('顯示值四分段邊界（可見滿分 90，對象卡互動階段閉環驗收 15）', () {
        // 0–30／31–60／61–80／81–90 四段；90 是可見滿分。
        expect(EnthusiasmLevel.fromScore(0), EnthusiasmLevel.cold);
        expect(EnthusiasmLevel.fromScore(30), EnthusiasmLevel.cold);
        expect(EnthusiasmLevel.fromScore(31), EnthusiasmLevel.warm);
        expect(EnthusiasmLevel.fromScore(60), EnthusiasmLevel.warm);
        expect(EnthusiasmLevel.fromScore(61), EnthusiasmLevel.hot);
        expect(EnthusiasmLevel.fromScore(80), EnthusiasmLevel.hot);
        expect(EnthusiasmLevel.fromScore(81), EnthusiasmLevel.veryHot);
        expect(EnthusiasmLevel.fromScore(90), EnthusiasmLevel.veryHot);
      });
    });

    group('calibrateVisibleInvestment', () {
      test('鏡像 server finalize：ceil(clamp(raw,0,100) × 0.9)', () {
        expect(calibrateVisibleInvestment(100), 90); // raw 100 → 顯示 90
        expect(calibrateVisibleInvestment(120), 90); // 超界 clamp
        expect(calibrateVisibleInvestment(82), 74);
        expect(calibrateVisibleInvestment(0), 0);
        expect(calibrateVisibleInvestment(-5), 0);
      });
    });

    group('clampVisibleInvestmentScore', () {
      test('只 clamp 已 finalize 的顯示值，不重複打九折', () {
        expect(clampVisibleInvestmentScore(-1), 0);
        expect(clampVisibleInvestmentScore(61), 61);
        expect(clampVisibleInvestmentScore(90), 90);
        expect(clampVisibleInvestmentScore(100), 90);
      });
    });

    group('label', () {
      test('returns correct Chinese label for each level', () {
        expect(EnthusiasmLevel.cold.label, '投入偏低');
        expect(EnthusiasmLevel.warm.label, '有在回應');
        expect(EnthusiasmLevel.hot.label, '投入明顯');
        expect(EnthusiasmLevel.veryHot.label, '高度投入');
      });
    });

    group('icon', () {
      test('returns correct icon for each level', () {
        expect(EnthusiasmLevel.cold.icon, TablerIcons.snowflake);
        expect(EnthusiasmLevel.warm.icon, TablerIcons.sun_low);
        expect(EnthusiasmLevel.hot.icon, TablerIcons.flame);
        expect(EnthusiasmLevel.veryHot.icon, TablerIcons.hearts);
      });
    });
  });
}
