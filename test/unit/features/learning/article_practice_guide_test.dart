import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/articles_data.dart';

Article _article(String id) => articles.firstWhere((a) => a.id == id);

void main() {
  group('buildArticlePracticeGuide', () {
    test('maps opener articles to low-pressure topic practice', () {
      final guide = buildArticlePracticeGuide(_article('1'));

      expect(guide.category, '開話題');
      expect(guide.practiceTitle, contains('低壓開場'));
      expect(guide.carryBackHint, contains('開場救星'));
    });

    test('maps listening articles to resonance practice', () {
      final guide = buildArticlePracticeGuide(_article('11'));

      expect(guide.category, '延伸與共鳴');
      expect(guide.practicePrompt, contains('她可能的感受'));
      expect(guide.goodExample, contains('聽起來'));
    });

    test('maps invite articles to invitation practice', () {
      final guide = buildArticlePracticeGuide(_article('21'));

      expect(guide.category, '推進與邀約');
      expect(guide.practicePrompt, contains('可拒絕空間'));
      expect(guide.mistakeExample, contains('到底要不要'));
    });

    test('maps boundary articles to judgment practice', () {
      final guide = buildArticlePracticeGuide(_article('22'));

      expect(guide.category, '判斷與邊界');
      expect(guide.practiceTitle, contains('有界線'));
      expect(guide.carryBackHint, contains('問教練'));
    });

    test('uses article subtitle as one-line takeaway', () {
      final article = _article('14');
      final guide = buildArticlePracticeGuide(article);

      expect(guide.oneLineTakeaway, article.subtitle);
      expect(guide.category, '延伸與共鳴');
    });

    test('maps sexual tension article to flirtation practice', () {
      final guide = buildArticlePracticeGuide(_article('23'));

      expect(guide.category, '性張力與曖昧');
      expect(guide.practiceTitle, contains('曖昧回球'));
      expect(guide.carryBackHint, contains('測溫'));
    });
  });
}
