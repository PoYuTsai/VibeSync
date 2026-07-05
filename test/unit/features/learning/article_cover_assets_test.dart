import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/data/articles_data.dart';

void main() {
  group('learning article cover assets', () {
    test('use one existing cover image per article', () {
      final seen = <String, String>{};

      for (final article in articles) {
        final file = File(article.imagePath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Article ${article.id} references a missing cover image.',
        );
        expect(
          seen[article.imagePath],
          isNull,
          reason:
              'Articles ${seen[article.imagePath]} and ${article.id} share ${article.imagePath}.',
        );
        seen[article.imagePath] = article.id;
      }
    });
  });
}
