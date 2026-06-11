// lib/core/services/message_calculator.dart
//
// ADR #19 r3 計費鏡像（Dart 端）。server 權威實作在
// supabase/functions/analyze-chat/billing.ts，本檔必須與其 byte-for-byte
// 同義；JS/Dart mirror tests 共用 test/fixtures/adr19_billing_mirror_vectors.json。
//
// 分段帶（整數閉區間，作用對象 = 本次計費字數 = payload 字數 − baseline）：
//   1~40      → 1 則
//   41~400    → ceil(chars/40) = 2~10 則
//   401~2000  → 一律 10 則（緩衝帶）
//   2001~4000 → 固定 20 則，需用戶確認（confirmedOvercharge）
//   4001+     → 請分批分析，不送出
//
// 字數定義（r2 規格 #4）：UTF-16 code units（Dart `String.length` ≡ JS）、
// 各則 content trim 後加總、不 normalize、零寬字元照算、
// quotedReplyPreview 不計費。
//
// 已知接受：JS 與 Dart 的 trim 對 U+0085 (NEL) 行為不同（Dart 會修剪、
// JS 不會）。聊天文字幾乎不可能出現 NEL；萬一出現造成 hash 漂移，
// server 會回 OVERCHARGE_CONFIRMATION_REQUIRED 帶權威 hash，client
// 以該 hash 重新確認即可自癒。
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../features/conversation/domain/entities/message.dart';

enum BillingBandKind { standard, overcharge, reject }

class BillingBand {
  final BillingBandKind kind;

  /// standard = 1~10、overcharge = 20；reject 時為 null。
  final int? units;

  const BillingBand._(this.kind, this.units);
}

/// Billing mirror for ADR #19 r3（取代逐則 200 字制的 MessageCalculator）。
class MessageCalculator {
  static const charsPerMessageUnit = 40;
  static const softCapUnits = 10;
  static const softCapBandMaxChars = 2000;
  static const overchargeUnits = 20;
  static const maxBillableChars = 4000;

  /// Capability contract（ADR #19 定案 #6）：所有 analyze 請求必送。
  static const billingProtocolVersion = 3;

  /// 單一字數 helper（規格 #8）：預覽與 billing 都走這裡。
  static int countPayloadChars(List<Message> messages) =>
      countContentChars(messages.map((message) => message.content).toList());

  static int countContentChars(List<String> contents) {
    var total = 0;
    for (final content in contents) {
      total += content.trim().length;
    }
    return total;
  }

  /// 分段帶查表（鏡像 billing.ts bandForBillableChars，必須同閉區間）。
  static BillingBand bandForBillableChars(int chars) {
    if (chars > maxBillableChars) {
      return const BillingBand._(BillingBandKind.reject, null);
    }
    if (chars > softCapBandMaxChars) {
      return const BillingBand._(BillingBandKind.overcharge, overchargeUnits);
    }
    final raw = (chars / charsPerMessageUnit).ceil();
    final units = raw.clamp(1, softCapUnits);
    return BillingBand._(BillingBandKind.standard, units);
  }

  /// 確認綁定 hash（ADR #19 定案 #5）：SHA-256 hex，輸入 = trim 後的各則
  /// content 以 U+0000 串接的 UTF-8 bytes。鏡像 billing.ts
  /// computeBillingPayloadHash —— 兩端必須 byte-for-byte 一致。
  static String computeBillingPayloadHash(List<String> contents) {
    final joined = contents.map((content) => content.trim()).join('\u0000');
    return sha256.convert(utf8.encode(joined)).toString();
  }

  /// 對「即將送出的 requestMessages」建立計費預覽。
  ///
  /// [previousAnalyzedCharCount] = conversation.lastAnalyzedCharCount
  /// （上次送出 payload 的計費字數 baseline）。billable = 差額（≥0）；
  /// hash 綁定對象是整包 payload（[payloadChars]），不是差額。
  static MessagePreview previewConversation(
    List<Message> requestMessages, {
    int previousAnalyzedCharCount = 0,
  }) {
    final payloadChars = countPayloadChars(requestMessages);
    final baseline = previousAnalyzedCharCount.clamp(0, payloadChars);
    final billableChars = payloadChars - baseline;

    return MessagePreview(
      payloadChars: payloadChars,
      billableChars: billableChars,
      band: bandForBillableChars(billableChars),
    );
  }
}

/// ADR #19 r3 計費預覽結果。
class MessagePreview {
  /// 整包 requestMessages 的計費字數（hash 綁定與 baseline 持久化對象）。
  final int payloadChars;

  /// 本次計費字數（payload − baseline，≥0）。
  final int billableChars;

  final BillingBand band;

  const MessagePreview({
    required this.payloadChars,
    required this.billableChars,
    required this.band,
  });
}
