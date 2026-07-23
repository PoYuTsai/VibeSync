import 'dart:convert';

import 'package:uuid/uuid.dart';

/// 新話題 exactly-once 的 client 側 requestId 生命週期（計畫 §12.4）。
///
/// 不重用 opener 的 image fingerprint：新話題的可見指紋只有
/// partnerId＋situation。一次 attempt 凍結完整 envelope（requestId、
/// partnerId、兩份 normalized context、situation）——同 Partner＋同
/// situation 的 failure retry 沿用同一 frozen envelope，背景 provider
/// 更新不能用同 requestId 偷換 summary／style（server ledger 綁 HMAC，
/// 換 payload 會 409 mismatch）。
///
/// Partner 或 situation 改變必 rotate；partnerId 改變時即使 normalized
/// summary 相同也 rotate（可見指紋含 partnerId）。quota、model limit、
/// timeout、settlement pending 都不清 pending。v1 僅 in-memory，不承諾
/// app 被 kill 後仍保留 requestId。
class NewTopicRequestSession {
  String? _pendingRequestId;
  String? _fingerprint;
  NewTopicAttempt? _pendingAttempt;

  NewTopicAttempt beginAttempt({
    required String? partnerId,
    required String? partnerSummary,
    required String? effectiveStyleContext,
    required String? situation,
  }) {
    final fingerprint = visibleFingerprintFor(
      partnerId: partnerId,
      situation: situation,
    );
    if (_pendingRequestId == null || _fingerprint != fingerprint) {
      _pendingRequestId = const Uuid().v4();
      _fingerprint = fingerprint;
      _pendingAttempt = NewTopicAttempt(
        requestId: _pendingRequestId!,
        partnerId: partnerId,
        partnerSummary: partnerSummary,
        effectiveStyleContext: effectiveStyleContext,
        situation: situation,
      );
    }
    return _pendingAttempt!;
  }

  /// 完整成功（解析出完整 NewTopicResult）後呼叫；下一次生成是新計費。
  void markSuccess() {
    _pendingRequestId = null;
    _fingerprint = null;
    _pendingAttempt = null;
  }

  /// 可見指紋只含 partnerId＋situation（計畫 §12.4）。jsonEncode 保欄位
  /// 邊界，避免串接碰撞。
  static String visibleFingerprintFor({
    required String? partnerId,
    required String? situation,
  }) {
    return jsonEncode([partnerId, situation]);
  }
}

/// [NewTopicRequestSession.beginAttempt] 的產物：requestId 與凍結的完整
/// envelope。實際送出的 payload 必須全部取自這裡，不得用呼叫端手上的
/// 新解析值。
class NewTopicAttempt {
  const NewTopicAttempt({
    required this.requestId,
    required this.partnerId,
    required this.partnerSummary,
    required this.effectiveStyleContext,
    required this.situation,
  });

  final String requestId;
  final String? partnerId;
  final String? partnerSummary;
  final String? effectiveStyleContext;
  final String? situation;
}
