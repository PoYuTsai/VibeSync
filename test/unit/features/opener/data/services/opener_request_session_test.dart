import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/data/services/opener_request_session.dart';

// opener 扣費 idempotency 的 client 側 requestId 生命週期
// （docs/plans/2026-07-03-opener-idempotency-design.md，Codex P2 修訂版）：
//   - 首按產生新 id；同一組輸入失敗重試沿用同 id（server 靠它去重雙扣）
//   - 成功 parse 結果後 rotate（下一次生成是新的一次計費）
//   - 輸入變更也 rotate：server ledger 綁 input_hash，同 id 換 payload 會被
//     擋（防改造 client 付一次無限重生成），所以 client 必須換新 id
void main() {
  group('OpenerRequestIdSession', () {
    test('first attempt mints a canonical UUID', () {
      final session = OpenerRequestIdSession();

      final id = session.beginAttempt(fingerprint: 'fp-1');

      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
        reason: 'server 只認 canonical UUID，其他形狀會退回無去重舊路',
      );
    });

    test('retry with same inputs reuses the same id (server dedups the charge)',
        () {
      final session = OpenerRequestIdSession();

      final first = session.beginAttempt(fingerprint: 'fp-1');
      // 沒有 markSuccess＝上一輪失敗（或回應丟失），同輸入重試必須同 id。
      final retry = session.beginAttempt(fingerprint: 'fp-1');

      expect(retry, first);
    });

    test('changed inputs mint a fresh id (server binds id to payload hash)',
        () {
      final session = OpenerRequestIdSession();

      final first = session.beginAttempt(fingerprint: 'fp-1');
      final afterEdit = session.beginAttempt(fingerprint: 'fp-2');

      expect(afterEdit, isNot(first));
    });

    test('markSuccess rotates: next attempt is a fresh id (new billable run)',
        () {
      final session = OpenerRequestIdSession();

      final first = session.beginAttempt(fingerprint: 'fp-1');
      session.markSuccess();
      final second = session.beginAttempt(fingerprint: 'fp-1');

      expect(second, isNot(first));
    });

    test('markSuccess before any attempt is a safe no-op', () {
      final session = OpenerRequestIdSession();

      session.markSuccess();

      expect(session.beginAttempt(fingerprint: 'fp-1'), isNotEmpty);
    });

    test('fingerprintFor is stable for equal inputs and differs on any change',
        () {
      final imageA = Uint8List.fromList([1, 2, 3]);
      final imageASame = Uint8List.fromList([1, 2, 3]);
      final imageB = Uint8List.fromList([9, 9, 9]);

      final base = OpenerRequestIdSession.fingerprintFor(
        images: [imageA],
        name: 'Candy',
        bio: '喜歡旅行',
        interests: '咖啡',
        meetingContext: 'IG',
      );
      final same = OpenerRequestIdSession.fingerprintFor(
        images: [imageASame],
        name: 'Candy',
        bio: '喜歡旅行',
        interests: '咖啡',
        meetingContext: 'IG',
      );
      final editedBio = OpenerRequestIdSession.fingerprintFor(
        images: [imageA],
        name: 'Candy',
        bio: '喜歡爬山',
        interests: '咖啡',
        meetingContext: 'IG',
      );
      final swappedImage = OpenerRequestIdSession.fingerprintFor(
        images: [imageB],
        name: 'Candy',
        bio: '喜歡旅行',
        interests: '咖啡',
        meetingContext: 'IG',
      );

      expect(same, base);
      expect(editedBio, isNot(base));
      expect(swappedImage, isNot(base));
    });

    test('fingerprintFor covers effectiveStyleContext (F3-1: style is input)',
        () {
      // 風格設定會進 server input hash；client 指紋不跟上會讓「改風格後
      // 重生成」誤沿用舊 requestId，被 server 判 payload mismatch 400。
      final base = OpenerRequestIdSession.fingerprintFor(
        name: 'Candy',
        effectiveStyleContext: '- Preferred voice: 幽默',
      );
      final sameStyle = OpenerRequestIdSession.fingerprintFor(
        name: 'Candy',
        effectiveStyleContext: '- Preferred voice: 幽默',
      );
      final changedStyle = OpenerRequestIdSession.fingerprintFor(
        name: 'Candy',
        effectiveStyleContext: '- Preferred voice: 穩重',
      );
      final noStyle = OpenerRequestIdSession.fingerprintFor(name: 'Candy');

      expect(sameStyle, base);
      expect(changedStyle, isNot(base));
      expect(noStyle, isNot(base));
    });
  });
}
