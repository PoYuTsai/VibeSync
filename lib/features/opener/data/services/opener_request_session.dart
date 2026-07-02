import 'package:uuid/uuid.dart';

/// opener 扣費 idempotency 的 client 側 requestId 生命週期
/// （docs/plans/2026-07-03-opener-idempotency-design.md）。
///
/// 同一次「用戶要一組開場白」的意圖對應一個 requestId：失敗（含回應在
/// 傳輸層丟失）重試沿用同 id，server 靠 (user, requestId) ledger 去重、
/// 絕不雙扣；成功拿到結果後才 rotate。輸入變更不 rotate——已付未得的
/// 那次額度，改完輸入重試仍不重扣。
class OpenerRequestIdSession {
  String? _pending;

  /// 回傳本次生成要帶的 requestId：沒有進行中的（上次已成功）就鑄新的。
  String beginAttempt() => _pending ??= const Uuid().v4();

  /// 成功 parse 出結果後呼叫；下一次生成是新的一次計費。
  void markSuccess() => _pending = null;
}
