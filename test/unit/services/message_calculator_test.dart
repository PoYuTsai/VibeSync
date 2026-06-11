// ADR #19 r3 計費鏡像測試（Dart 端）。
//
// 與 server 端 supabase/functions/analyze-chat/billing_test.ts 共用
// test/fixtures/adr19_billing_mirror_vectors.json（規格 #4 mirror tests：
// 同字串集兩端結果必須一致）。逐則 200 字制舊測試已隨舊公式退役。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/message_calculator.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Message _msg(String content) => Message(
      id: 'm-${content.hashCode}',
      content: content,
      isFromMe: false,
      timestamp: DateTime(2026, 1, 1),
    );

List<Message> _ofChars(int n) => [_msg('a' * n)];

void main() {
  group('billing constants (ADR #19 r3 frozen spec)', () {
    test('mirror server billing.ts constants', () {
      expect(MessageCalculator.charsPerMessageUnit, 40);
      expect(MessageCalculator.softCapUnits, 10);
      expect(MessageCalculator.softCapBandMaxChars, 2000);
      expect(MessageCalculator.overchargeUnits, 20);
      expect(MessageCalculator.maxBillableChars, 4000);
      expect(MessageCalculator.billingProtocolVersion, 3);
    });
  });

  group('bandForBillableChars (整數閉區間)', () {
    test('1~40 = 1 unit', () {
      expect(MessageCalculator.bandForBillableChars(1).units, 1);
      expect(MessageCalculator.bandForBillableChars(40).units, 1);
    });

    test('41~400 = ceil(chars/40)', () {
      expect(MessageCalculator.bandForBillableChars(41).units, 2);
      expect(MessageCalculator.bandForBillableChars(81).units, 3);
      expect(MessageCalculator.bandForBillableChars(400).units, 10);
    });

    test('401~2000 = 緩衝帶一律 10', () {
      expect(MessageCalculator.bandForBillableChars(401).units, 10);
      expect(MessageCalculator.bandForBillableChars(2000).units, 10);
    });

    test('2001~4000 = overcharge 固定 20', () {
      final low = MessageCalculator.bandForBillableChars(2001);
      final high = MessageCalculator.bandForBillableChars(4000);
      expect(low.kind, BillingBandKind.overcharge);
      expect(low.units, 20);
      expect(high.kind, BillingBandKind.overcharge);
      expect(high.units, 20);
    });

    test('4001+ = reject', () {
      expect(
        MessageCalculator.bandForBillableChars(4001).kind,
        BillingBandKind.reject,
      );
      expect(MessageCalculator.bandForBillableChars(4001).units, isNull);
    });

    test('0 chars = floor 1（再分析最少扣 1 則）', () {
      expect(MessageCalculator.bandForBillableChars(0).units, 1);
    });
  });

  group('countPayloadChars', () {
    test('trims each message, sums UTF-16 lengths, ignores quoted preview',
        () {
      final messages = [
        Message(
          id: 'q',
          content: ' ab ',
          isFromMe: false,
          timestamp: DateTime(2026, 1, 1),
          quotedReplyPreview: '這段引用不計費',
        ),
        _msg('c'),
      ];
      expect(MessageCalculator.countPayloadChars(messages), 3);
    });
  });

  group('previewConversation（增量 = 字數差）', () {
    test('first analysis bills full chars', () {
      final preview = MessageCalculator.previewConversation(_ofChars(100));
      expect(preview.billableChars, 100);
      expect(preview.band.units, 3);
      expect(preview.band.kind, BillingBandKind.standard);
    });

    test('incremental bills only the delta beyond char baseline', () {
      final preview = MessageCalculator.previewConversation(
        _ofChars(2100),
        previousAnalyzedCharCount: 2000,
      );
      expect(preview.billableChars, 100);
      expect(preview.band.units, 3);
    });

    test('baseline >= payload clamps to floor 1 (user-safe)', () {
      final preview = MessageCalculator.previewConversation(
        _ofChars(500),
        previousAnalyzedCharCount: 3000,
      );
      expect(preview.billableChars, 0);
      expect(preview.band.units, 1);
    });

    test('diff in 2001~4000 → overcharge band（需確認框）', () {
      final preview = MessageCalculator.previewConversation(
        _ofChars(5000),
        previousAnalyzedCharCount: 2000,
      );
      expect(preview.billableChars, 3000);
      expect(preview.band.kind, BillingBandKind.overcharge);
      expect(preview.band.units, 20);
    });

    test('diff 4001+ → reject band（請分批，不送出）', () {
      final preview = MessageCalculator.previewConversation(_ofChars(4001));
      expect(preview.band.kind, BillingBandKind.reject);
    });

    test('payloadChars covers the FULL request payload (hash binding base)',
        () {
      final preview = MessageCalculator.previewConversation(
        _ofChars(2100),
        previousAnalyzedCharCount: 2000,
      );
      // billable 是差額，但 payloadChars / hash 綁定對象是整包 requestMessages
      expect(preview.payloadChars, 2100);
    });
  });

  group('computeBillingPayloadHash', () {
    test('separator never collides with in-content whitespace', () {
      final joined = MessageCalculator.computeBillingPayloadHash(['a b']);
      final split = MessageCalculator.computeBillingPayloadHash(['a', 'b']);
      expect(joined, isNot(split));
    });

    test('trims content before hashing', () {
      expect(
        MessageCalculator.computeBillingPayloadHash([' ab ', 'c']),
        MessageCalculator.computeBillingPayloadHash(['ab', 'c']),
      );
    });
  });

  group('JS/Dart mirror fixture（規格 #4）', () {
    test('Dart side matches every shared vector', () {
      final fixtureFile =
          File('test/fixtures/adr19_billing_mirror_vectors.json');
      expect(fixtureFile.existsSync(), isTrue,
          reason: 'mirror fixture 不存在 — JS/Dart 對拍樣本是規格 #4 硬要求');
      final fixture =
          jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
      final vectors = fixture['vectors'] as List<dynamic>;
      expect(vectors.length, greaterThan(10));

      for (final raw in vectors) {
        final vector = raw as Map<String, dynamic>;
        final name = vector['name'] as String;
        final contents = (vector['contents'] as List<dynamic>).map((c) {
          if (c is String) return c;
          final spec = c as Map<String, dynamic>;
          return (spec['repeat'] as String) * (spec['times'] as int);
        }).toList();

        final messages = contents.map(_msg).toList();
        expect(
          MessageCalculator.countPayloadChars(messages),
          vector['charCount'],
          reason: '$name: charCount',
        );

        final band = MessageCalculator.bandForBillableChars(
          vector['charCount'] as int,
        );
        expect(band.kind.name, vector['band'], reason: '$name: band');
        expect(band.units, vector['units'], reason: '$name: units');

        expect(
          MessageCalculator.computeBillingPayloadHash(contents),
          vector['sha256'],
          reason: '$name: hash（兩端綁定 hash 必須 byte-for-byte 一致）',
        );
      }
    });
  });
}
