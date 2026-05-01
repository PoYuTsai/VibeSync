import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/user_profile/domain/services/name_candidate_extractor.dart';

/// Test helper — Message has multiple required fields (id/timestamp); this
/// trims the boilerplate so each test reads as `_msg('hi', fromMe: false)`.
Message _msg(String content, {required bool fromMe, int seq = 0}) => Message(
  id: 'm$seq',
  content: content,
  isFromMe: fromMe,
  timestamp: DateTime(2026, 5, 1).add(Duration(minutes: seq)),
);

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

  group('NameCandidateExtractor.fromMessages', () {
    test('only scans 前 5 + 後 5 incoming messages', () {
      // Construct 12 incoming + 2 outgoing. Place the only self-intro in
      // message index 6 (middle of incoming list — should be SKIPPED because
      // 12 > 2*5, so only first 5 + last 5 incoming are scanned).
      // Indices scanned: 0,1,2,3,4 + 7,8,9,10,11. Index 5 and 6 are skipped.
      final messages = <Message>[
        for (int i = 0; i < 6; i++)
          _msg('普通訊息 $i', fromMe: false, seq: i),
        // Index 6 — middle, should NOT be scanned.
        _msg("Hi I'm Hidden", fromMe: false, seq: 6),
        for (int i = 7; i < 12; i++)
          _msg('其他訊息 $i', fromMe: false, seq: i),
        _msg('我自己說話 a', fromMe: true, seq: 12),
        _msg('我自己說話 b', fromMe: true, seq: 13),
      ];
      expect(
        extractor.fromMessages(messages),
        isNull,
        reason:
            'name was only in middle-of-list incoming msg; 前5+後5 window must skip it',
      );

      // Sanity: if the same name appears in the FIRST 5, it IS picked up.
      final messagesWithEarlyName = <Message>[
        _msg('hello', fromMe: false, seq: 0),
        _msg('how are u', fromMe: false, seq: 1),
        _msg("Hi I'm Anna", fromMe: false, seq: 2),
        for (int i = 3; i < 12; i++)
          _msg('filler $i', fromMe: false, seq: i),
      ];
      expect(extractor.fromMessages(messagesWithEarlyName), 'anna');
    });

    test('ignores outgoing (isFromMe) messages', () {
      // Outgoing has self-intro, incoming does NOT — must return null.
      final messages = <Message>[
        _msg("Hi I'm Bob", fromMe: true, seq: 0), // SELF, must be ignored
        _msg('我叫小明', fromMe: true, seq: 1), // SELF, must be ignored
        _msg('Call me Charlie', fromMe: true, seq: 2), // SELF, must be ignored
        _msg('hello there', fromMe: false, seq: 3),
        _msg('how are you', fromMe: false, seq: 4),
      ];
      expect(
        extractor.fromMessages(messages),
        isNull,
        reason:
            'outgoing self-intros must be filtered; partner never introduced themselves',
      );

      // Sanity: flipping ONE outgoing → incoming proves the regex itself works.
      // If THIS returned null, the test's null assertion above would be a false-positive.
      expect(
        extractor.fromMessages([_msg("Hi I'm Bob", fromMe: false)]),
        'bob',
        reason: 'sanity: same self-intro string with fromMe:false DOES match',
      );
    });

    test('matches "我叫 X" / "Hi I\'m X" / "Call me X"', () {
      // Chinese 我叫.
      expect(
        extractor.fromMessages([_msg('我叫小明', fromMe: false)]),
        '小明',
      );
      expect(
        extractor.fromMessages([_msg('我叫 小華', fromMe: false)]),
        '小華',
      );
      // English I'm (with optional Hi prefix, case-insensitive).
      expect(
        extractor.fromMessages([_msg("Hi I'm Anna", fromMe: false)]),
        'anna',
      );
      expect(
        extractor.fromMessages([_msg("hi, i'm bob", fromMe: false)]),
        'bob',
      );
      expect(
        extractor.fromMessages([_msg("I'm Charlie nice to meet u", fromMe: false)]),
        'charlie',
      );
      // Curly apostrophe variant (’).
      expect(
        extractor.fromMessages([_msg("I’m Diana", fromMe: false)]),
        'diana',
      );
      // Call me.
      expect(
        extractor.fromMessages([_msg('Call me Eve', fromMe: false)]),
        'eve',
      );
      expect(
        extractor.fromMessages([_msg('call me Frank!', fromMe: false)]),
        'frank',
      );
    });

    test('does NOT do full-text NER (e.g. "她是 May" 不抽 May)', () {
      // 確保極窄 regex，不全文掃 — these strings contain capitalized names but
      // NOT the self-intro markers (我叫 / I'm / Call me), so must return null.
      final messages = <Message>[
        _msg('她是 May', fromMe: false, seq: 0),
        _msg('我跟 May 聊天很久了', fromMe: false, seq: 1),
        _msg('May 人很好', fromMe: false, seq: 2),
        _msg('I met John yesterday', fromMe: false, seq: 3),
        _msg('John is nice', fromMe: false, seq: 4),
      ];
      expect(
        extractor.fromMessages(messages),
        isNull,
        reason:
            'narrow regex requires self-intro marker; speaking ABOUT a third person must NOT match',
      );
    });

    test('returns null when no incoming match', () {
      // No self-intro markers anywhere.
      expect(
        extractor.fromMessages([
          _msg('hello', fromMe: false),
          _msg('how are u', fromMe: false),
          _msg('what u doing', fromMe: false),
        ]),
        isNull,
      );
      // Empty list.
      expect(extractor.fromMessages(<Message>[]), isNull);
      // All outgoing.
      expect(
        extractor.fromMessages([
          _msg("Hi I'm Eric", fromMe: true),
          _msg('我叫 Eric', fromMe: true),
        ]),
        isNull,
      );
    });
  });
}
