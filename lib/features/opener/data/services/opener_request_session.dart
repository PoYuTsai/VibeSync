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
  String? _pendingStyleContext;

  /// 回傳本次生成要帶的 requestId＋風格快照：上次成功過、或可見輸入指紋
  /// 變了就鑄新的並凍結本次 [styleContext]。
  ///
  /// 同指紋重試沿用凍結快照、忽略新解析值（Codex R2 P2）：pending 的
  /// 已扣費 run 必須原封重送才 dedup 得到；resolver 首發失敗（null）、
  /// 重試才恢復的情境不得讓 payload 換形。風格設定的變更會在下一次
  /// 成功 rotate 或可見輸入變更時生效。
  OpenerAttempt beginAttempt({
    required String fingerprint,
    String? styleContext,
  }) {
    if (_pending == null || _fingerprint != fingerprint) {
      _pending = const Uuid().v4();
      _fingerprint = fingerprint;
      _pendingStyleContext = styleContext;
    }
    return OpenerAttempt(
      requestId: _pending!,
      styleContext: _pendingStyleContext,
    );
  }

  /// 成功 parse 出結果後呼叫；下一次生成是新的一次計費。
  void markSuccess() {
    _pending = null;
    _fingerprint = null;
    _pendingStyleContext = null;
  }

  /// 生成輸入的指紋：同 run 內相同輸入必相同、任一欄位或圖片變動必不同。
  /// 只用於 in-memory 生命週期判斷，不需要跨 app 重啟穩定。
  /// 指紋只含用戶可見輸入，不含風格快照——風格由 [beginAttempt] 凍結在
  /// pending attempt 上，入指紋反而會讓 resolver 時序差異誤鑄新 id。
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

/// [OpenerRequestIdSession.beginAttempt] 的產物：requestId 與它綁定的
/// 風格快照。實際送出的 payload 必須用這裡的 [styleContext]，不得用
/// 呼叫端手上的新解析值。
class OpenerAttempt {
  final String requestId;
  final String? styleContext;

  const OpenerAttempt({required this.requestId, this.styleContext});
}
