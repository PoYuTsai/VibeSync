/// analyze-chat HTTP 傳輸共用層：錯誤對映、429 額度判別、回應解碼、
/// entitlement 脈絡與訊息 payload 形狀。串流與非串流 client 共用，
/// 行為即原 `analysis_service.dart` 內的私有實作，逐字搬移。
library;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../subscription/domain/services/subscription_tier_helper.dart';
import 'analysis_exceptions.dart';

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

class AnalysisEntitlementContext {
  const AnalysisEntitlementContext({
    this.expectedTier,
    this.revenueCatAppUserId,
  });

  final String? expectedTier;
  final String? revenueCatAppUserId;
}

String? defaultAnalysisExpectedTier() {
  try {
    final tier = SubscriptionTierHelper.normalizeTier(
      UsageService().getLocalUsage().tier,
    );
    return tier == SubscriptionTierHelper.free ? null : tier;
  } catch (_) {
    return null;
  }
}

Future<String?> defaultAnalysisRevenueCatAppUserId() async {
  try {
    final customerInfo = await RevenueCatService.getCustomerInfo().timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );
    return RevenueCatService.getRevenueCatAppUserId(customerInfo);
  } catch (_) {
    return null;
  }
}

Future<AnalysisEntitlementContext> buildAnalysisEntitlementContext({
  required String? Function() expectedTierProvider,
  required Future<String?> Function() revenueCatAppUserIdProvider,
}) async {
  final expectedTier = SubscriptionTierHelper.normalizeTier(
    expectedTierProvider(),
  );
  if (expectedTier == SubscriptionTierHelper.free) {
    return const AnalysisEntitlementContext();
  }

  final revenueCatAppUserId = await revenueCatAppUserIdProvider();
  final cleanedRevenueCatAppUserId = revenueCatAppUserId?.trim();
  return AnalysisEntitlementContext(
    expectedTier: expectedTier,
    revenueCatAppUserId:
        cleanedRevenueCatAppUserId == null || cleanedRevenueCatAppUserId.isEmpty
            ? null
            : cleanedRevenueCatAppUserId,
  );
}

/// analyze-chat wire 上單一則訊息的 payload 形狀（串流與非串流一致；
/// 改這裡等於改 server input hash 的輸入，動之前先想 replay）。
Map<String, dynamic> analysisMessagePayload(Message message) => {
      'isFromMe': message.isFromMe,
      'content': message.content,
      if (message.quotedReplyPreview != null &&
          message.quotedReplyPreview!.trim().isNotEmpty)
        'quotedReplyPreview': message.quotedReplyPreview!.trim(),
      if (message.quotedReplyPreview != null &&
          message.quotedReplyPreview!.trim().isNotEmpty &&
          message.quotedReplyPreviewIsFromMe != null)
        'quotedReplyPreviewIsFromMe': message.quotedReplyPreviewIsFromMe,
    };

void analysisDebugLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

bool isReadableAnalysisUserMessage(String message) {
  return message.contains(RegExp(r'[\u4e00-\u9fff]'));
}

Map<String, dynamic> decodeAnalysisResponseBody(http.Response response) {
  final body = response.body.trim();
  if (body.isEmpty) {
    return <String, dynamic>{};
  }

  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{'data': decoded};
  } on FormatException {
    final shortenedBody =
        body.length > 300 ? '${body.substring(0, 300)}...' : body;
    return <String, dynamic>{
      '_nonJson': true,
      '_rawBody': shortenedBody,
    };
  }
}

Map<String, dynamic>? normalizeAnalysisJsonObject(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  return null;
}

/// 429 quota payload → typed exception。集中三個 429 呼叫點的判別邏輯。
///
/// 舊 server payload 只帶單一 limit 欄位（monthly 或 daily 擇一）；ADR #19 的
/// `buildQuotaExceededPayload` 同時帶 `monthlyLimit` + `dailyLimit`，必須改用
/// remaining vs quotaNeeded 判別是哪個額度擋下這次分析——否則月額度爆掉會被
/// `dailyLimit != null` 先判而誤報成「今日額度已用完」（wait 而非 upgrade，
/// 直接傷 Free→付費轉換；smoke P1 fix 2026-06-11）。
AnalysisException? quotaExceptionFrom429(Map<String, dynamic> data) {
  final monthlyLimit = (data['monthlyLimit'] as num?)?.toInt();
  final dailyLimit = (data['dailyLimit'] as num?)?.toInt();
  if (monthlyLimit == null && dailyLimit == null) return null;

  final quotaNeeded = (data['quotaNeeded'] as num?)?.toInt();
  final monthlyRemaining = (data['monthlyRemaining'] as num?)?.toInt();
  final dailyRemaining = (data['dailyRemaining'] as num?)?.toInt();
  final used = (data['used'] as num?)?.toInt() ?? 0;
  final monthlyUsed = (data['monthlyUsed'] as num?)?.toInt() ?? used;
  final dailyUsed = (data['dailyUsed'] as num?)?.toInt() ?? used;

  final bool isMonthly;
  if (monthlyLimit != null && dailyLimit == null) {
    isMonthly = true;
  } else if (dailyLimit != null && monthlyLimit == null) {
    isMonthly = false;
  } else if (monthlyRemaining != null && quotaNeeded != null) {
    // server 先檢查月額度、月夠才輪到日，所以月剩餘不足 = 月額度擋下。
    isMonthly = monthlyRemaining < quotaNeeded;
  } else {
    // 無法判別時偏向 monthly：upgrade CTA 比「明天再試」安全。
    isMonthly = true;
  }

  if (isMonthly) {
    return MonthlyLimitExceededException(
      monthlyLimit: monthlyLimit ?? 0,
      used: monthlyUsed,
      remaining: monthlyRemaining,
      quotaNeeded: quotaNeeded,
    );
  }
  return DailyLimitExceededException(
    dailyLimit: dailyLimit ?? 0,
    used: dailyUsed,
    remaining: dailyRemaining,
    quotaNeeded: quotaNeeded,
  );
}

/// 走 optimize-message 那條計費流程的功能名稱。
///
/// server 端錯誤碼是穩定契約、訊息寫死「草稿潤飾」，兩個入口共用同一條
/// exactly-once 流程，所以名稱只能在 client 依當前入口切換。
String _optimizeFeatureLabel({required bool hasRefineInstruction}) =>
    hasRefineInstruction ? '回覆微調' : '草稿潤飾';

/// 泛用失敗（500/502/timeout 等）用的動作名稱，草稿潤飾沿用既有「訊息優化」。
String optimizeFlowLabel({required bool hasRefineInstruction}) =>
    hasRefineInstruction ? '回覆微調' : '訊息優化';

AnalysisException mapAnalysisHttpError({
  required int statusCode,
  required String? errorCode,
  required String rawMessage,
  required bool hasImages,
  required bool recognizeOnly,
  required bool hasUserDraft,
  required bool hasRefineInstruction,
}) {
  final normalizedMessage = rawMessage.trim();
  final lowerMessage = normalizedMessage.toLowerCase();
  final featureLabel =
      _optimizeFeatureLabel(hasRefineInstruction: hasRefineInstruction);
  final flowLabel =
      optimizeFlowLabel(hasRefineInstruction: hasRefineInstruction);

  String recognitionUnsupportedMessage() {
    if (normalizedMessage.isEmpty) {
      return '這張圖目前不像可匯入的聊天截圖，請改傳完整聊天視窗後再試。';
    }

    if (isReadableAnalysisUserMessage(normalizedMessage)) {
      return normalizedMessage;
    }

    if (lowerMessage.contains('call log') ||
        lowerMessage.contains('system notification')) {
      return '這張圖看起來比較像通話紀錄或系統通知畫面。若這其實是聊天視窗，請保留標題列與完整訊息泡泡後再試。';
    }

    if (lowerMessage.contains('social feed') ||
        lowerMessage.contains('comment thread')) {
      return '這張圖看起來比較像社群貼文或留言串，不是一般雙人聊天截圖。請改傳聊天視窗後再試。';
    }

    return '這張圖目前不像可匯入的聊天截圖，請改傳完整聊天視窗後再試。';
  }

  switch (statusCode) {
    case 400:
      switch (errorCode) {
        case 'INVALID_OPTIMIZE_MESSAGE_REQUEST_ID':
        case 'OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH':
          return AnalysisException(
            '這次$featureLabel請求無法安全重送，請重新操作。本次不會扣額度。',
            code: errorCode,
            suggestedAction: AnalysisErrorAction.retry,
          );
        case 'RECOGNITION_UNSUPPORTED':
          return AnalysisException(
            recognitionUnsupportedMessage(),
            code: errorCode,
            suggestedAction: AnalysisErrorAction.rescreenshot,
          );
        case 'RECOGNITION_FAILED':
          return AnalysisException(
            isReadableAnalysisUserMessage(normalizedMessage) &&
                    normalizedMessage.isNotEmpty
                ? normalizedMessage
                : '這張圖暫時辨識不穩，請換一張更清楚的截圖再試。',
            code: errorCode,
            suggestedAction: AnalysisErrorAction.rescreenshot,
          );
        case 'CONTENT_TOO_LONG_FOR_ANALYSIS':
          // ADR #19：計費字數 4001+ server 守門 reject（不扣費）。
          // 正常流程 client 預覽層已先擋，這是雙層防線的 server 層。
          return AnalysisException(
            '內容過長，請分批分析。',
            code: errorCode,
            suggestedAction: AnalysisErrorAction.shortenInput,
          );
      }

      if (normalizedMessage == 'Messages cannot be empty') {
        return AnalysisException(
          '請先加入對話內容再分析。',
          code: 'EMPTY_MESSAGES',
          suggestedAction: AnalysisErrorAction.addIncomingMessage,
        );
      }

      if (normalizedMessage == 'Request body too large' ||
          normalizedMessage == 'Total image payload too large') {
        return AnalysisException(
          '這次上傳的內容太多或圖片太大，請減少張數或重新截圖後再試。',
          code: 'REQUEST_TOO_LARGE',
          suggestedAction: AnalysisErrorAction.shortenInput,
        );
      }

      if (normalizedMessage == 'Unsupported image type' ||
          lowerMessage.contains('unsupported image type')) {
        return AnalysisException(
          '目前不支援這種圖片格式，請改用一般截圖後再試。',
          code: 'UNSUPPORTED_IMAGE_TYPE',
          suggestedAction: AnalysisErrorAction.rescreenshot,
        );
      }

      if (normalizedMessage.contains('圖片格式錯誤') ||
          lowerMessage.contains('invalid image format')) {
        return AnalysisException(
          '圖片格式有誤，請重新截圖後再試。',
          code: 'INVALID_IMAGE_FORMAT',
          suggestedAction: AnalysisErrorAction.rescreenshot,
        );
      }

      if (normalizedMessage.contains('圖片順序錯誤') ||
          normalizedMessage.contains('圖片排序重複') ||
          lowerMessage.contains('invalid image order')) {
        return AnalysisException(
          '截圖順序有誤，請重新選擇圖片後再試。',
          code: 'INVALID_IMAGE_ORDER',
          suggestedAction: AnalysisErrorAction.rescreenshot,
        );
      }

      if (normalizedMessage.startsWith('userDraft too long')) {
        return AnalysisException(
          '你輸入的草稿太長了，請精簡後再試。',
          code: 'USER_DRAFT_TOO_LONG',
          suggestedAction: AnalysisErrorAction.shortenInput,
        );
      }

      if (normalizedMessage.startsWith('conversationSummary too long')) {
        return AnalysisException(
          '這段對話的上下文太長了，請精簡後再試。',
          code: 'CONTEXT_TOO_LONG',
          suggestedAction: AnalysisErrorAction.shortenInput,
        );
      }

      if (normalizedMessage ==
          'At least one incoming message is required for analysis') {
        return AnalysisException(
          '至少要有一則對方訊息才能開始分析。',
          code: 'NO_INCOMING_MESSAGE',
          suggestedAction: AnalysisErrorAction.addIncomingMessage,
        );
      }

      if (normalizedMessage ==
          'my_message mode requires the latest message to be from the user') {
        return AnalysisException(
          '「優化我說」需要最新一則是你自己發出的訊息。',
          code: 'INVALID_MY_MESSAGE_CONTEXT',
          suggestedAction: AnalysisErrorAction.retry,
        );
      }

      if (normalizedMessage == 'recognizeOnly requires images') {
        return AnalysisException(
          '請先選擇截圖再開始辨識。',
          code: 'IMAGES_REQUIRED',
          suggestedAction: AnalysisErrorAction.rescreenshot,
        );
      }

      return AnalysisException(
        hasImages
            ? '這次上傳的截圖內容有誤，請重新截圖後再試。'
            : hasUserDraft
                ? '這次送出的草稿內容有誤，請修改後再試。'
                : '這次送出的對話內容有誤，請檢查後再試。',
        code: errorCode ?? 'BAD_REQUEST',
        suggestedAction: hasImages
            ? AnalysisErrorAction.rescreenshot
            : AnalysisErrorAction.retry,
      );
    case 401:
      return AnalysisException(
        '登入狀態已失效，請重新登入後再試。',
        code: errorCode ?? 'UNAUTHORIZED',
        suggestedAction: AnalysisErrorAction.relogin,
      );
    case 403:
      if (errorCode == 'FEATURE_NOT_AVAILABLE') {
        return AnalysisException(
          '這個功能需要 Essential 方案才能使用。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.upgrade,
        );
      }
      return AnalysisException(
        '你目前沒有權限使用這個功能。',
        code: errorCode ?? 'FORBIDDEN',
        suggestedAction: AnalysisErrorAction.wait,
      );
    case 409:
      if (errorCode == 'OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH') {
        return AnalysisException(
          hasRefineInstruction
              ? '這次微調內容和先前的重試不一致，請重新操作。本次不會扣額度。'
              : '這次草稿和先前的重試不一致，請重新操作。本次不會扣額度。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.retry,
        );
      }
      if (errorCode == 'OVERCHARGE_CONFIRMATION_REQUIRED') {
        // ADR #19 定案 #5：>2000 字確認帶 server 守門。正常流程 client
        // 已先本地確認；走到這代表確認缺失或內容已變更（hash 不符）。
        // fail loud 請用戶重按分析重新走確認流程，絕不自動拿舊確認
        // 重綁新內容。
        return AnalysisException(
          '這次內容較長，需要重新確認一次扣費。請再按一次分析。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.retry,
        );
      }
      return AnalysisException(
        '這次分析狀態有衝突，請重新分析一次。',
        code: errorCode ?? 'CONFLICT',
        suggestedAction: AnalysisErrorAction.retry,
      );
    case 413:
      return AnalysisException(
        '這次上傳的內容太大，請減少張數或重新截圖後再試。',
        code: errorCode ?? 'PAYLOAD_TOO_LARGE',
        suggestedAction: AnalysisErrorAction.shortenInput,
      );
    case 429:
      // 免費 OCR（recognizeOnly）限流：6/分、60/天。payload 不帶
      // monthlyLimit/dailyLimit 鍵，所以不會被 quotaExceptionFrom429
      // 判成訂閱額度（那會誤導升級 paywall CTA）。wait 而非 retry。
      // MODEL_RATE_LIMITED＝analyze 模型呼叫限流（6/分、60/天），同型契約
      // （docs/plans/2026-07-03-model-rate-limit-design.md）。
      if (errorCode == 'OCR_RATE_LIMITED' ||
          errorCode == 'MODEL_RATE_LIMITED') {
        return AnalysisException(
          isReadableAnalysisUserMessage(normalizedMessage) &&
                  normalizedMessage.isNotEmpty
              ? normalizedMessage
              : errorCode == 'OCR_RATE_LIMITED'
                  ? '截圖辨識太頻繁，請稍等一下再試。'
                  : '請求太頻繁，請稍後再試。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.wait,
        );
      }
      // 其他 429（訂閱額度）已在呼叫端被 quotaExceptionFrom429 接走；
      // 走到這代表 payload 缺額度欄位，保守給 wait。
      return AnalysisException(
        '請求太頻繁，請稍後再試。',
        code: errorCode ?? 'RATE_LIMITED',
        suggestedAction: AnalysisErrorAction.wait,
      );
    case 500:
      // 帳本快照不合法時 server 回 500（其他無效結果路徑回 502），兩邊都是
      // 不扣費，文案不能因為狀態碼不同就把保證漏掉。
      if (errorCode == 'OPTIMIZE_MESSAGE_RESULT_INVALID') {
        return AnalysisException(
          hasRefineInstruction
              ? '這次沒有產生可用的微調結果，請稍後再試。本次不會扣額度。'
              : '這次沒有產生可用的潤飾結果，請稍後再試。本次不會扣額度。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.wait,
        );
      }
      if (errorCode == 'OPTIMIZE_MESSAGE_REPLAY_INVALID' ||
          errorCode == 'OPTIMIZE_MESSAGE_SETTLEMENT_FAILED') {
        return AnalysisException(
          errorCode == 'OPTIMIZE_MESSAGE_REPLAY_INVALID'
              ? '$featureLabel結果暫時無法恢復，請重新操作。本次不會扣額度。'
              : '$featureLabel額度確認失敗，請稍後再試。本次不會扣額度。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.wait,
        );
      }
      return AnalysisException(
        hasImages
            ? recognizeOnly
                ? '截圖辨識暫時失敗，請稍後再試。'
                : '圖片分析暫時失敗，請稍後再試。'
            : hasUserDraft
                ? '$flowLabel暫時失敗，請稍後再試。'
                : '分析暫時失敗，請稍後再試。',
        code: errorCode ?? 'UNKNOWN_HTTP_ERROR',
        suggestedAction: AnalysisErrorAction.retry,
      );
    case 502:
    case 503:
    case 504:
      if (errorCode == 'AI_RESPONSE_INVALID' && recognizeOnly) {
        return AnalysisException(
          '這次辨識結果格式異常，請再試一次。本次不會扣額度。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.retry,
        );
      }
      if (errorCode == 'OPTIMIZE_MESSAGE_RESULT_INVALID') {
        return AnalysisException(
          hasRefineInstruction
              ? '這次沒有產生可用的微調結果，請稍後再試。本次不會扣額度。'
              : '這次沒有產生可用的潤飾結果，請稍後再試。本次不會扣額度。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.wait,
        );
      }
      // 亂碼防呆：模型宣告草稿無法理解，server 不扣費。文案要引導換草稿，
      // 不能是「請稍後再試」——同一段亂碼再送幾次結果都一樣。
      if (errorCode == 'OPTIMIZE_MESSAGE_DRAFT_UNREADABLE') {
        return AnalysisException(
          '看不懂這段草稿，請換成想傳的訊息再試一次。本次不會扣額度。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.retry,
        );
      }
      // 安全守門攔下：內容問題不是暫時性失敗，文案要引導改寫、不能說
      // 「請稍後再試」。
      if (errorCode == 'OPTIMIZE_MESSAGE_SAFETY_BLOCKED') {
        return AnalysisException(
          hasRefineInstruction
              ? '這次調出來的內容帶有施壓或威脅的說法，已被安全守門攔下。請改成尊重對方意願的方向再調。本次不會扣額度。'
              : '這段內容帶有施壓或威脅的說法，不提供潤飾。請改成尊重對方意願的說法再試一次。本次不會扣額度。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.retry,
        );
      }
      if (errorCode == 'OVERCHARGE_CLAIM_UNAVAILABLE') {
        // ADR #19：idempotency claim 不可用時 server fail closed 不扣費。
        return AnalysisException(
          '長內容分析暫時無法啟動，請稍後再試。本次不會扣額度。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.wait,
        );
      }
      return AnalysisException(
        hasImages
            ? recognizeOnly
                ? '截圖辨識服務目前較忙，請稍後再試。'
                : '圖片分析服務目前較忙，請稍後再試。'
            : hasUserDraft
                ? '$flowLabel服務目前較忙，請稍後再試。'
                : '分析服務目前較忙，請稍後再試。',
        code: errorCode ?? 'UPSTREAM_UNAVAILABLE',
        suggestedAction: AnalysisErrorAction.wait,
      );
    default:
      return AnalysisException(
        hasImages
            ? recognizeOnly
                ? '截圖辨識暫時失敗，請稍後再試。'
                : '圖片分析暫時失敗，請稍後再試。'
            : hasUserDraft
                ? '$flowLabel暫時失敗，請稍後再試。'
                : '分析暫時失敗，請稍後再試。',
        code: errorCode ?? 'UNKNOWN_HTTP_ERROR',
        suggestedAction: AnalysisErrorAction.retry,
      );
  }
}

AnalysisException mapUnexpectedAnalysisError(
  Object error, {
  required bool hasImages,
  required bool recognizeOnly,
  required bool hasUserDraft,
  required bool hasRefineInstruction,
}) {
  final errorMessage = error.toString();
  final flowLabel =
      optimizeFlowLabel(hasRefineInstruction: hasRefineInstruction);

  if (errorMessage.contains('Unauthorized') || errorMessage.contains('401')) {
    return AnalysisException(
      '登入狀態已失效，請重新登入後再試。',
      code: 'UNAUTHORIZED',
      suggestedAction: AnalysisErrorAction.relogin,
    );
  }

  if (error is http.ClientException ||
      errorMessage.contains('SocketException') ||
      errorMessage.contains('Connection refused')) {
    return AnalysisException(
      '網路連線不穩，請確認網路後再試。',
      code: 'NETWORK_ERROR',
      suggestedAction: AnalysisErrorAction.retry,
    );
  }

  if (errorMessage.contains('timeout') || errorMessage.contains('Timeout')) {
    return AnalysisException(
      hasImages
          ? recognizeOnly
              ? '截圖辨識花太久了，請稍後再試。'
              : '圖片分析花太久了，請稍後再試。'
          : hasUserDraft
              ? '$flowLabel花太久了，請稍後再試。'
              : '分析花太久了，請稍後再試。',
      code: 'TIMEOUT',
      suggestedAction: AnalysisErrorAction.wait,
    );
  }

  return AnalysisException(
    hasImages
        ? recognizeOnly
            ? '截圖辨識暫時失敗，請稍後再試。'
            : '圖片分析暫時失敗，請稍後再試。'
        : hasUserDraft
            ? '$flowLabel暫時失敗，請稍後再試。'
            : '分析暫時失敗，請稍後再試。',
    code: 'UNEXPECTED_ERROR',
    suggestedAction: AnalysisErrorAction.retry,
  );
}
