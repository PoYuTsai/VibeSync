import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

/// opener 扣費 idempotency 的 client 側 requestId 生命週期
/// （docs/plans/2026-07-03-opener-idempotency-design.md，Codex P2 修訂版）。
///
/// 同一次「用戶要一組開場白」的意圖對應一個 requestId：同輸入失敗（含回應
/// 在傳輸層丟失）重試沿用同 id，server 靠 (user, requestId) ledger 去重、
/// 絕不雙扣；成功拿到結果後 rotate。輸入變更也 rotate——server ledger 綁
/// input hash，同 id 換 payload 會被擋（防改造 client 付一次無限重生成）。
class OpenerRequestIdSession {
  String? _pending;
  String? _fingerprint;

  /// 回傳本次生成要帶的 requestId：上次成功過、或輸入指紋變了就鑄新的。
  String beginAttempt({required String fingerprint}) {
    if (_pending == null || _fingerprint != fingerprint) {
      _pending = const Uuid().v4();
      _fingerprint = fingerprint;
    }
    return _pending!;
  }

  /// 成功 parse 出結果後呼叫；下一次生成是新的一次計費。
  void markSuccess() {
    _pending = null;
    _fingerprint = null;
  }

  /// 生成輸入的指紋：同 run 內相同輸入必相同、任一欄位或圖片變動必不同。
  /// 只用於 in-memory 生命週期判斷，不需要跨 app 重啟穩定。
  static String fingerprintFor({
    List<Uint8List>? images,
    String? name,
    String? bio,
    String? interests,
    String? meetingContext,
  }) {
    // jsonEncode 保欄位邊界（純 join 會讓 'a b'+'c' 與 'a'+'b c' 撞指紋）。
    return jsonEncode([
      name,
      bio,
      interests,
      meetingContext,
      images?.map(Object.hashAll).toList(),
    ]);
  }
}
