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

      final attempt = session.beginAttempt(fingerprint: 'fp-1');

      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(attempt.requestId),
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

      expect(retry.requestId, first.requestId);
    });

    test('changed inputs mint a fresh id (server binds id to payload hash)',
        () {
      final session = OpenerRequestIdSession();

      final first = session.beginAttempt(fingerprint: 'fp-1');
      final afterEdit = session.beginAttempt(fingerprint: 'fp-2');

      expect(afterEdit.requestId, isNot(first.requestId));
    });

    test('markSuccess rotates: next attempt is a fresh id (new billable run)',
        () {
      final session = OpenerRequestIdSession();

      final first = session.beginAttempt(fingerprint: 'fp-1');
      session.markSuccess();
      final second = session.beginAttempt(fingerprint: 'fp-1');

      expect(second.requestId, isNot(first.requestId));
    });

    test('markSuccess before any attempt is a safe no-op', () {
      final session = OpenerRequestIdSession();

      session.markSuccess();

      expect(session.beginAttempt(fingerprint: 'fp-1').requestId, isNotEmpty);
    });

    // Codex R2 P2：風格快照凍結在 pending attempt 上。同可見輸入的重試必須
    // 原封重送（含首發 resolver 失敗時的 null）——否則 resolver 恢復後風格
    // 突然出現，payload 換形、requestId 換新，server 對已扣費 run 去重失效。
    test('retry with same inputs freezes the pending style snapshot', () {
      final session = OpenerRequestIdSession();

      final first = session.beginAttempt(
        fingerprint: 'fp-1',
        styleContext: null, // 首發 resolver 失敗
      );
      final retry = session.beginAttempt(
        fingerprint: 'fp-1',
        styleContext: '- Preferred voice: 幽默', // resolver 恢復
      );

      expect(retry.requestId, first.requestId);
      expect(retry.styleContext, isNull, reason: '重試必須原封重送凍結快照');
    });

    test('changed inputs adopt the freshly resolved style snapshot', () {
      final session = OpenerRequestIdSession();

      session.beginAttempt(fingerprint: 'fp-1', styleContext: '舊風格');
      final fresh = session.beginAttempt(
        fingerprint: 'fp-2',
        styleContext: '新風格',
      );

      expect(fresh.styleContext, '新風格');
    });

    test('markSuccess unfreezes: next attempt adopts the new style', () {
      final session = OpenerRequestIdSession();

      session.beginAttempt(fingerprint: 'fp-1', styleContext: null);
      session.markSuccess();
      final next = session.beginAttempt(
        fingerprint: 'fp-1',
        styleContext: '- Preferred voice: 穩重',
      );

      expect(next.styleContext, '- Preferred voice: 穩重');
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

  });
}
