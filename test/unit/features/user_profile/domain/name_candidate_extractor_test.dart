import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/services/name_candidate_extractor.dart';

void main() {
  final extractor = NameCandidateExtractor();

  group('NameCandidateExtractor.fromConversationName', () {
    test('rejects 新對話 / 新的對話 / 互動紀錄 / 第 X 段 / 空字串', () {
      for (final placeholder in [
        '新對話',
        '新的對話',
        '互動紀錄',
        '第 1 段',
        '第3段',
        '',
        '   ',
      ]) {
        expect(
          extractor.fromConversationName(placeholder),
          isNull,
          reason: 'should reject "$placeholder"',
        );
      }
    });

    test('rejects pure date-like titles', () {
      for (final s in ['2026/05/01', '5月1日', '2026-05-01']) {
        expect(extractor.fromConversationName(s), isNull, reason: s);
      }
    });

    test('accepts looks-like-person-name', () {
      expect(extractor.fromConversationName('Anna'), 'anna');
      expect(extractor.fromConversationName('小明'), '小明');
      expect(extractor.fromConversationName('Anna Smith'), 'anna smith');
    });

    test('rejects long sentences (not name-like)', () {
      expect(extractor.fromConversationName('我跟她聊天'), isNull);
    });

    // Edge case: returns null for null input (pure-function contract).
    test('returns null for null input', () {
      expect(extractor.fromConversationName(null), isNull);
    });

    // Edge case: trims whitespace before evaluating + canonicalising.
    test('trims surrounding whitespace before accepting', () {
      expect(extractor.fromConversationName('  Anna  '), 'anna');
    });
  });
}
