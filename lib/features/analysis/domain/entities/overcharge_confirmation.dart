/// ADR #19 定案 #5 — >2000 字確認帶的用戶確認憑證（domain 值物件）。
///
/// 歷史 import 路徑（transport support／analysis_service barrel）以
/// re-export 相容。
library;

/// ADR #19 定案 #5 — >2000 字確認帶的用戶確認憑證。
///
/// 用戶在本地確認框按下「確認扣 20 則」後生成；綁定送出 payload 的
/// hash（MessageCalculator.computeBillingPayloadHash）＋計費字數＋
/// 一次性 confirmationId（idempotency：同一確認重送絕不重扣）。
class OverchargeConfirmationPayload {
  final String payloadHash;
  final int billableChars;
  final String confirmationId;

  const OverchargeConfirmationPayload({
    required this.payloadHash,
    required this.billableChars,
    required this.confirmationId,
  });

  Map<String, dynamic> toJson() => {
        'payloadHash': payloadHash,
        'billableChars': billableChars,
        'confirmationId': confirmationId,
      };
}
