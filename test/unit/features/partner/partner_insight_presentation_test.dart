import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/domain/mindmap/partner_insight_presentation.dart';

void main() {
  group('PartnerInsightPresentation.derive', () {
    test('tacticalHook = 主特質 + 主興趣', () {
      final p = PartnerInsightPresentation.derive(
        interests: ['爬山', '咖啡'],
        traits: ['幽默', '溫柔'],
        nextStep: '約她週末喝咖啡',
      );
      expect(p.tacticalHook, '幽默 + 爬山');
      expect(p.fullNextStep, '約她週末喝咖啡');
    });

    test('topicsLine = 興趣前兩項用 / 串', () {
      final p = PartnerInsightPresentation.derive(
        interests: ['茶碗蒸', '蛋白質', '健身'],
      );
      expect(p.topicsLine, '茶碗蒸 / 蛋白質');
    });

    test('只有興趣沒有特質 → hook 用興趣首項', () {
      final p = PartnerInsightPresentation.derive(interests: ['爬山']);
      expect(p.tacticalHook, '爬山');
    });

    test('只有特質沒有興趣 → hook 用特質首項、topicsLine null', () {
      final p = PartnerInsightPresentation.derive(traits: ['幽默']);
      expect(p.tacticalHook, '幽默');
      expect(p.topicsLine, isNull);
    });

    test('特質與興趣首項相同 → hook 不重複', () {
      final p = PartnerInsightPresentation.derive(
        interests: ['爬山'],
        traits: ['爬山'],
      );
      expect(p.tacticalHook, '爬山');
    });

    test('全空 → 三者皆 null', () {
      final p = PartnerInsightPresentation.derive();
      expect(p.tacticalHook, isNull);
      expect(p.topicsLine, isNull);
      expect(p.fullNextStep, isNull);
    });

    test('fullNextStep 去前後空白；空字串 → null', () {
      expect(
        PartnerInsightPresentation.derive(nextStep: '  做點什麼  ').fullNextStep,
        '做點什麼',
      );
      expect(
        PartnerInsightPresentation.derive(nextStep: '   ').fullNextStep,
        isNull,
      );
    });

    test('興趣/特質含空白項 → 過濾後再衍生', () {
      final p = PartnerInsightPresentation.derive(
        interests: ['  ', '咖啡'],
        traits: ['  '],
      );
      expect(p.tacticalHook, '咖啡');
      expect(p.topicsLine, '咖啡');
    });
  });
}
