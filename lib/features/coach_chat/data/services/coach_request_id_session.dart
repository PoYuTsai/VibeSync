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

  static String _newRequestId() => const Uuid().v4();

  /// 回傳本次請求要帶的 requestId：無 pending 或 signature 變了就鑄新的；
  /// 同 signature 重呼（重試場景）沿用同一 id。
  String begin(String signature) {
    if (_requestId == null || _signature != signature) {
      _requestId = _requestIdFactory();
      _signature = signature;
    }
    return _requestId!;
  }

  /// 成功落卡後呼叫；下一次 [begin] 是新的一次計費。
  void retire() {
    _requestId = null;
    _signature = null;
  }
}
