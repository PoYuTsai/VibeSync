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

    test('accepts Japanese-surname-style names containing 和 (e.g. 和田)', () {
      expect(
        extractor.fromConversationName('和田'),
        '和田',
        reason:
            '和 is a common Japanese surname character; must NOT be rejected as sentence particle',
      );
      expect(extractor.fromConversationName('和泉'), '和泉');
      expect(extractor.fromConversationName('和久'), '和久');
    });

    test('rejects number-only / emoji-only / punctuation-only inputs', () {
      for (final s in ['12345', '🐶', '!!!', '...', '???']) {
        expect(
          extractor.fromConversationName(s),
          isNull,
          reason: '"$s" has no letter/CJK char; not a candidate name',
        );
      }
    });

    test('accepts mixed alphanumeric like Bob123', () {
      expect(
        extractor.fromConversationName('Bob123'),
        'bob123',
        reason: 'has letter content even with digits — accept',
      );
    });
  });
}
