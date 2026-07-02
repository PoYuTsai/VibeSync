import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/data/services/opener_request_session.dart';

// opener 扣費 idempotency 的 client 側 requestId 生命週期
// （docs/plans/2026-07-03-opener-idempotency-design.md）：
//   - 首按產生新 id；失敗重試沿用同 id（server 靠它去重雙扣）
//   - 成功 parse 結果後才 rotate（下一次生成是新的一次計費）
//   - 輸入變更不 rotate：用戶已付未得的那次，改完輸入重試仍不重扣
void main() {
  group('OpenerRequestIdSession', () {
    test('first attempt mints a canonical UUID', () {
      final session = OpenerRequestIdSession();

      final id = session.beginAttempt();

      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
        reason: 'server 只認 canonical UUID，其他形狀會退回無去重舊路',
      );
    });

    test('retry after failure reuses the same id (server dedups the charge)',
        () {
      final session = OpenerRequestIdSession();

      final first = session.beginAttempt();
      // 沒有 markSuccess＝上一輪失敗（或回應丟失），重試必須同 id。
      final retry = session.beginAttempt();

      expect(retry, first);
    });

    test('markSuccess rotates: next attempt is a fresh id (new billable run)',
        () {
      final session = OpenerRequestIdSession();

      final first = session.beginAttempt();
      session.markSuccess();
      final second = session.beginAttempt();

      expect(second, isNot(first));
    });

    test('markSuccess before any attempt is a safe no-op', () {
      final session = OpenerRequestIdSession();

      session.markSuccess();

      expect(session.beginAttempt(), isNotEmpty);
    });
  });
}
