import 'package:uuid/uuid.dart';

/// coach 扣費 idempotency 的 client 側 requestId 生命週期
/// （Phase E，對齊 opener 的 `OpenerRequestIdSession` 範式）。
///
/// 同一次「用戶要一則教練回覆」的意圖對應一個 requestId：同 intent
/// （signature 不變）失敗重試沿用同 id，server 靠 (user, request_id)
/// ledger 去重、絕不雙扣；成功落卡後 [retire]，下一次是新的一次計費。
/// intent 變更（signature 換了）必鑄新 id——server ledger 綁 payload，
/// 同 id 換 payload 會被擋（REPLAY_MISMATCH）。
///
/// 每個 controller instance 持一個 session；signature 由呼叫端組，
/// 本類別不管其格式。
class CoachRequestIdSession {
  CoachRequestIdSession({String Function()? requestIdFactory})
      : _requestIdFactory = requestIdFactory ?? _newRequestId;

  final String Function() _requestIdFactory;

  String? _signature;
  String? _requestId;
  String? _sessionId;

  static String _newRequestId() => const Uuid().v4();

  /// 回傳本次請求要帶的 requestId：無 pending 或 signature 變了就鑄新的；
  /// 同 signature 重呼（重試場景）沿用同一 id。鑄新 id 時一併清掉快取的
  /// 合成 sessionId——新 intent 絕不沿用舊 intent 的合成 session。
  String begin(String signature) {
    if (_requestId == null || _signature != signature) {
      _requestId = _requestIdFactory();
      _signature = signature;
      _sessionId = null;
    }
    return _requestId!;
  }

  /// fresh session（無可 resume 的 sessionId）時取「綁定本 pending 請求」的
  /// 合成 sessionId：首呼以 [create] 合成並快取，同 pending 重呼（重試）
  /// 沿用同一顆。server input_hash 含 wire sessionId，重試若換 sessionId
  /// 會變成同 requestId 不同 hash → REPLAY_MISMATCH（P1 修）。
  /// 必須在 [begin] 之後呼叫；[retire] 或 signature 變更即清。
  String resolveSessionId(String Function() create) {
    return _sessionId ??= create();
  }

  /// 成功落卡後呼叫；下一次 [begin] 是新的一次計費（含新的合成 session）。
  void retire() {
    _requestId = null;
    _signature = null;
    _sessionId = null;
  }
}
