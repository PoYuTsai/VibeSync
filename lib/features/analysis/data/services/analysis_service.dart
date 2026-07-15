import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/environment.dart';
import '../../../../core/services/message_calculator.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/usage_service.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../../subscription/domain/services/subscription_tier_helper.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/analysis_recommendation_preview.dart';

class ImageData {
  final String data;
  final String mediaType;
  final int order;

  ImageData({
    required this.data,
    required this.mediaType,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
        'data': data,
        'mediaType': mediaType,
        'order': order,
      };
}

enum AnalysisProgressStage {
  preparingPayload,
  uploadingRequest,
  awaitingAi,
}

class AnalysisProgressUpdate {
  final AnalysisProgressStage stage;
  final int imageCount;
  final Duration elapsed;
  final int? requestBodyBytes;

  const AnalysisProgressUpdate({
    required this.stage,
    required this.imageCount,
    required this.elapsed,
    this.requestBodyBytes,
  });
}

class AnalysisTelemetry {
  final String? requestType;
  final int imageCount;
  final int requestBodyBytes;
  final Duration payloadPreparationDuration;
  final Duration roundTripDuration;
  final Duration? edgeAiDuration;
  final int? totalCompressedImageBytes;
  final bool cacheHit;
  final bool fallbackUsed;
  final int retryCount;
  final Duration? timeoutDuration;
  final bool? allowModelFallback;
  final String? contextMode;
  final int? inputMessageCount;
  final int? compiledMessageCount;
  final int? truncatedMessageCount;
  final int? openingMessagesUsed;
  final int? recentMessagesUsed;
  final bool conversationSummaryUsed;
  final String? recognizedClassification;
  final String? recognizedConfidence;
  final String? recognizedSideConfidence;
  final int? recognizedMessageCount;
  final int? uncertainSideCount;
  final int? continuityAdjustedCount;
  final int? groupedAdjustedCount;
  final int? layoutFirstAdjustedCount;
  final int? systemRowsRemovedCount;
  final int? quotedPreviewRemovedCount;
  final int? quotedPreviewAttachedCount;
  final int? overlapRemovedCount;
  final bool? shouldChargeQuota;
  final int? chargedMessageCount;
  final int? estimatedMessageCount;
  final String? quotaReason;

  const AnalysisTelemetry({
    this.requestType,
    required this.imageCount,
    required this.requestBodyBytes,
    required this.payloadPreparationDuration,
    required this.roundTripDuration,
    this.edgeAiDuration,
    this.totalCompressedImageBytes,
    this.cacheHit = false,
    this.fallbackUsed = false,
    this.retryCount = 0,
    this.timeoutDuration,
    this.allowModelFallback,
    this.contextMode,
    this.inputMessageCount,
    this.compiledMessageCount,
    this.truncatedMessageCount,
    this.openingMessagesUsed,
    this.recentMessagesUsed,
    this.conversationSummaryUsed = false,
    this.recognizedClassification,
    this.recognizedConfidence,
    this.recognizedSideConfidence,
    this.recognizedMessageCount,
    this.uncertainSideCount,
    this.continuityAdjustedCount,
    this.groupedAdjustedCount,
    this.layoutFirstAdjustedCount,
    this.systemRowsRemovedCount,
    this.quotedPreviewRemovedCount,
    this.quotedPreviewAttachedCount,
    this.overlapRemovedCount,
    this.shouldChargeQuota,
    this.chargedMessageCount,
    this.estimatedMessageCount,
    this.quotaReason,
  });

  Duration? get estimatedTransferDuration {
    if (edgeAiDuration == null) {
      return null;
    }

    final remainingMs =
        roundTripDuration.inMilliseconds - edgeAiDuration!.inMilliseconds;
    return Duration(milliseconds: remainingMs < 0 ? 0 : remainingMs);
  }
}

typedef AnalysisProgressCallback = void Function(
  AnalysisProgressUpdate update,
);

typedef AnalysisTelemetryCallback = void Function(
  AnalysisTelemetry telemetry,
);

enum AnalysisStreamUpdateKind {
  started,
  progress,
  content,
  recommendation,
  done,
}

enum AnalysisStreamContentKind {
  decision,
  replyOption,
  metrics,
  coachHint,
  reportSection,
}

class AnalysisStreamContent {
  final AnalysisStreamContentKind kind;
  final String title;
  final String body;
  final String? tag;
  final Map<String, dynamic> rawEvent;

  const AnalysisStreamContent({
    required this.kind,
    required this.title,
    required this.body,
    this.tag,
    required this.rawEvent,
  });

  static AnalysisStreamContent? fromEvent(Map<String, dynamic> event) {
    final type = _stringField(event['type']);
    switch (type) {
      case 'analysis.decision':
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.decision,
          title: _stringField(event['nextStepTitle']) ?? '下一步策略',
          body: _joinNonEmpty([
            _stringField(event['nextStepBody']) ??
                _stringField(event['nextStep']),
            _prefix('建議', _stringField(event['doThis'])),
            _prefix('避免', _stringField(event['avoidThis'])),
          ]),
          rawEvent: event,
        );
      case 'analysis.reply_option':
        final style = _stringField(event['style']) ??
            _stringField(event['selectedStyle']);
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.replyOption,
          title: '回覆選項：${_styleLabel(style)}',
          body: _joinNonEmpty([
            _stringField(event['message']),
            _prefix(
              '思路',
              _stringField(event['reason']) ?? _stringField(event['approach']),
            ),
            _prefix(
              '對應',
              _stringField(event['quotedContext']) ??
                  _stringField(event['sourceMessage']),
            ),
          ]),
          tag: style,
          rawEvent: event,
        );
      case 'analysis.metrics':
        final score = _numberField(
          event['heat'] ?? event['enthusiasmScore'] ?? event['score'],
        );
        final topicDepth = _recordField(event['topicDepth']);
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.metrics,
          title: '互動指標',
          body: _joinNonEmpty([
            score == null ? null : '本次投入：$score/100',
            _prefix(
              '話題深度',
              _stringField(topicDepth?['suggestion']) ??
                  _stringField(topicDepth?['current']),
            ),
          ]),
          rawEvent: event,
        );
      case 'analysis.coach_hint':
        final hint = event['coachActionHint'];
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.coachHint,
          title: '教練提示',
          body: _stringify(hint) ??
              _joinNonEmpty([
                _stringField(event['title']),
                _stringField(event['message']),
                _stringField(event['body']),
              ]),
          rawEvent: event,
        );
      case 'analysis.report_section':
        final section = _stringField(event['section']);
        final body = _reportSectionBody(section, event);
        if (body == null) return null;
        return AnalysisStreamContent(
          kind: AnalysisStreamContentKind.reportSection,
          title: _sectionLabel(section),
          body: body,
          tag: section,
          rawEvent: event,
        );
      default:
        return null;
    }
  }

  static String _styleLabel(String? style) {
    switch (style) {
      case 'extend':
        return '延伸話題';
      case 'resonate':
        return '共鳴回應';
      case 'tease':
        return '輕鬆挑逗';
      case 'humor':
        return '幽默回覆';
      case 'coldRead':
        return '冷讀觀察';
      default:
        return '可用回覆';
    }
  }

  static String _sectionLabel(String? section) {
    switch (section) {
      case 'strategy':
        return '深度策略';
      case 'warnings':
        return '注意事項';
      case 'psychology':
        return '心理訊號';
      case 'topicDepth':
        return '話題深度';
      case 'gameStage':
        return '關係階段';
      case 'status':
      case 'gameStage.status':
        return '關係狀態';
      default:
        return '完整分析段落';
    }
  }

  static String? _prefix(String label, String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return '$label：${value.trim()}';
  }

  static String _joinNonEmpty(Iterable<String?> values) {
    return values
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join('\n');
  }

  static String? _stringField(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _displayTextField(dynamic value) {
    final raw = _stringField(value);
    if (raw == null) return null;
    final sanitized = _sanitizeSchemaLeakText(raw).trim();
    return sanitized.isEmpty ? null : sanitized;
  }

  static int? _numberField(dynamic value) {
    if (value is num && value.isFinite) return value.round();
    return null;
  }

  static Map<String, dynamic>? _recordField(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static String? _stringify(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = _stringField(value);
      if (trimmed == null) return null;
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          final decoded = jsonDecode(trimmed);
          final formatted = _stringify(decoded);
          if (formatted != null && formatted.trim().isNotEmpty) {
            return formatted;
          }
        } on FormatException {
          // Fall through to the original text.
        }
      }
      return trimmed;
    }
    if (value is List) {
      final joined = value
          .map(_stringify)
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .join('\n');
      return joined.isEmpty ? null : joined;
    }
    if (value is Map) {
      final direct = _joinNonEmpty([
        _stringField(value['title']),
        _stringField(value['message']),
        _stringField(value['body']),
        _stringField(value['summary']),
        _stringField(value['suggestion']),
      ]);
      if (direct.isNotEmpty) return direct;
      final structured = _formatStructuredMap(value);
      if (structured != null) return structured;
      return null;
    }
    return value.toString();
  }

  static String? _formatStructuredMap(Map value) {
    final lines = <String>[];
    final usedKeys = <String>{};

    void add(String key, String label) {
      if (!value.containsKey(key)) return;
      final formatted = _formatStructuredValueForKey(key, value[key]);
      if (formatted == null || formatted.isEmpty) return;
      usedKeys.add(key);
      lines.add('$label：$formatted');
    }

    add('subtext', '她話裡的意思');
    add('qualificationSignal', '主動投入訊號');
    add('current', '目前狀態');
    add('status', '狀態');
    add('suggestion', '建議');
    add('nextStep', '下一步');
    add('catchablePoint', '可接的球');
    add('read', '判讀');
    add('microMove', '微行動');
    add('avoid', '先避免');
    add('confidence', '信心');
    add('interests', '她的興趣/偏好');
    add('traits', '她的特質');
    add('notes', '補充觀察');

    value.forEach((key, rawValue) {
      final keyText = key.toString();
      if (usedKeys.contains(keyText)) return;
      final formatted = _formatStructuredValue(rawValue);
      if (formatted == null || formatted.isEmpty) return;
      lines.add(formatted);
    });

    final joined = lines.join('\n');
    return joined.trim().isEmpty ? null : joined;
  }

  static String? _reportSectionBody(
    String? section,
    Map<String, dynamic> event,
  ) {
    final rawValue = event.containsKey('payload')
        ? event['payload']
        : event.containsKey('content')
            ? event['content']
            : event['message'];
    final formatted = _stringify(rawValue);
    if (formatted == null || formatted.trim().isEmpty) return null;
    return _formatReportSectionScalar(section, formatted);
  }

  static String? _formatReportSectionScalar(String? section, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final sectionKey = section?.trim();
    final statusLabel = _schemaStatusLabel(trimmed);
    if (statusLabel != null) {
      switch (sectionKey) {
        case 'status':
        case 'gameStage.status':
          return statusLabel;
        case 'gameStage':
          return '狀態：$statusLabel';
        default:
          return null;
      }
    }

    final currentLabel = _schemaCurrentLabel(trimmed);
    if (currentLabel != null) {
      switch (sectionKey) {
        case 'gameStage':
        case 'gameStage.current':
          return '目前狀態：$currentLabel';
        case 'topicDepth':
        case 'topicDepth.current':
          return '目前層次：$currentLabel';
        default:
          return null;
      }
    }

    return _sanitizeSchemaLeakText(trimmed);
  }

  static String? _formatStructuredValueForKey(String key, dynamic value) {
    switch (key) {
      case 'interests':
      case 'traits':
      case 'notes':
        if (value is List) {
          final joined = value
              .map(_stringify)
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .join('、');
          return joined.isEmpty ? null : joined;
        }
        break;
    }

    final formatted = _formatStructuredValue(value);
    if (formatted == null || formatted.isEmpty) return null;
    switch (key) {
      case 'status':
        return _schemaStatusLabel(formatted) ?? formatted;
      case 'current':
        return _schemaCurrentLabel(formatted) ?? formatted;
      default:
        return formatted;
    }
  }

  static String _sanitizeSchemaLeakText(String value) {
    var text = value.trim();
    if (text.isEmpty) return text;

    text = text.replaceAllMapped(
      RegExp(r'\bpersonal\s*階段', caseSensitive: false),
      (_) => '個人層階段',
    );
    text = text.replaceAllMapped(
      RegExp(r'(^|[^A-Za-z])normal(?=([^A-Za-z]|$))', caseSensitive: false),
      (match) => '${match.group(1) ?? ''}進展順利',
    );

    return _replaceSchemaListFields(text);
  }

  static String _replaceSchemaListFields(String text) {
    final schemaLabels = <String, String>{
      'interests': '她的興趣/偏好',
      'traits': '她的特質',
      'notes': '補充觀察',
    };
    final schemaFieldPattern = RegExp(
      r'''["']?(interests|traits|notes)["']?\s*[:：]\s*(\[[^\]]*\]|[^,\n]+)\s*,?''',
      caseSensitive: false,
    );
    final matches = schemaFieldPattern.allMatches(text).toList();
    if (matches.isEmpty) return text;

    final leftover = text
        .replaceAll(schemaFieldPattern, '')
        .replaceAll(RegExp(r'[\s,，{}]+'), '');
    if (matches.length > 1 && leftover.isEmpty) {
      return matches.map((match) {
        final key = match.group(1)!.toLowerCase();
        final rawValue = match.group(2) ?? '';
        return '${schemaLabels[key]}：${_humanizeSchemaList(rawValue)}';
      }).join('\n');
    }

    return text.replaceAllMapped(schemaFieldPattern, (match) {
      final key = match.group(1)!.toLowerCase();
      final rawValue = match.group(2) ?? '';
      return '${schemaLabels[key]}：${_humanizeSchemaList(rawValue)}';
    });
  }

  static String _humanizeSchemaList(String value) {
    var text = value.trim();
    if (text.endsWith(',')) {
      text = text.substring(0, text.length - 1).trim();
    }
    if (text.startsWith('[') && text.endsWith(']')) {
      text = text.substring(1, text.length - 1);
    }

    final items = text
        .split(RegExp(r'[,，]'))
        .map((item) => item.replaceAll(RegExp(r'''["']'''), '').trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    return items.isEmpty ? value.trim() : items.join('、');
  }

  static String? _formatStructuredValue(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value ? '有' : '沒有';
    if (value is num && value.isFinite) return value.toString();
    if (value is String) return _stringify(value);
    if (value is List || value is Map) return _stringify(value);
    return value.toString();
  }

  static String? _schemaStatusLabel(String value) {
    switch (value.trim()) {
      case 'normal':
        return '進展順利';
      case 'stuckFriend':
        return '偏向朋友';
      case 'canAdvance':
        return '可以更進一步';
      case 'shouldRetreat':
        return '放慢節奏';
      default:
        return null;
    }
  }

  static String? _schemaCurrentLabel(String value) {
    switch (value.trim()) {
      case 'opening':
        return '破冰階段';
      case 'premise':
        return '建立男女感';
      case 'qualification':
        return '互相評估';
      case 'narrative':
        return '展現個人魅力';
      case 'close':
        return '準備邀約';
      case 'facts':
      case 'event':
        return '事件層';
      case 'personal':
        return '個人層';
      case 'intimate':
        return '曖昧層';
      default:
        return null;
    }
  }
}

class AnalysisStreamUpdate {
  final AnalysisStreamUpdateKind kind;
  final String? runId;
  final String? label;
  final String? detail;
  final int? etaSeconds;
  final AnalysisStreamContent? content;
  final AnalysisRecommendationPreview? recommendationPreview;
  final AnalysisResult? result;
  final Map<String, dynamic>? rawEvent;

  const AnalysisStreamUpdate._({
    required this.kind,
    this.runId,
    this.label,
    this.detail,
    this.etaSeconds,
    this.content,
    this.recommendationPreview,
    this.result,
    this.rawEvent,
  });

  const AnalysisStreamUpdate.started({
    String? runId,
    String? label,
    String? detail,
    int? etaSeconds,
    Map<String, dynamic>? rawEvent,
  }) : this._(
          kind: AnalysisStreamUpdateKind.started,
          runId: runId,
          label: label,
          detail: detail,
          etaSeconds: etaSeconds,
          rawEvent: rawEvent,
        );

  const AnalysisStreamUpdate.progress({
    String? runId,
    String? label,
    String? detail,
    int? etaSeconds,
    Map<String, dynamic>? rawEvent,
  }) : this._(
          kind: AnalysisStreamUpdateKind.progress,
          runId: runId,
          label: label,
          detail: detail,
          etaSeconds: etaSeconds,
          rawEvent: rawEvent,
        );

  const AnalysisStreamUpdate.content({
    required AnalysisStreamContent content,
    String? runId,
    String? label,
    String? detail,
    int? etaSeconds,
    Map<String, dynamic>? rawEvent,
  }) : this._(
          kind: AnalysisStreamUpdateKind.content,
          runId: runId,
          label: label,
          detail: detail,
          etaSeconds: etaSeconds,
          content: content,
          rawEvent: rawEvent,
        );

  const AnalysisStreamUpdate.recommendation({
    required AnalysisRecommendationPreview recommendationPreview,
    String? runId,
    String? label,
    String? detail,
    int? etaSeconds,
    Map<String, dynamic>? rawEvent,
  }) : this._(
          kind: AnalysisStreamUpdateKind.recommendation,
          runId: runId,
          label: label,
          detail: detail,
          etaSeconds: etaSeconds,
          recommendationPreview: recommendationPreview,
          rawEvent: rawEvent,
        );

  const AnalysisStreamUpdate.done({
    required AnalysisResult result,
    String? runId,
    String? label,
    String? detail,
    int? etaSeconds,
    Map<String, dynamic>? rawEvent,
  }) : this._(
          kind: AnalysisStreamUpdateKind.done,
          runId: runId,
          label: label,
          detail: detail,
          etaSeconds: etaSeconds,
          result: result,
          rawEvent: rawEvent,
        );
}

enum AnalysisErrorAction {
  retry,
  relogin,
  rescreenshot,
  shortenInput,
  upgrade,
  wait,
  addIncomingMessage,
}

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

void _debugLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

bool _isReadableUserMessage(String message) {
  return message.contains(RegExp(r'[\u4e00-\u9fff]'));
}

/// User-facing copy for a streaming `analysis.error` event.
///
/// The server may put engineering English in `message` (e.g. "Quota failed",
/// raw exceptions, error codes, JSON/schema/streaming fragments). Only surface
/// it when it is actually localized (passes [_isReadableUserMessage]);
/// otherwise return a fixed Chinese fallback. The raw text is sent to
/// [_debugLog] at the call site for debugging only and never reaches the UI.
/// Mirrors the HTTP path's [_mapAnalysisHttpError] gate and the opener DATA-01
/// sanitize precedent. Only the user-visible message is rewritten; the event's
/// `code`, `recoverable`, and `retriesRemaining` are preserved by the caller so
/// quota/paywall routing is never eaten.
String _friendlyStreamErrorMessage(String? rawMessage) {
  final message = (rawMessage ?? '').trim();
  if (message.isNotEmpty && _isReadableUserMessage(message)) {
    return message;
  }
  return '這次分析沒順利完成，請稍後再試一次。';
}

/// 429 quota payload → typed exception。集中三個 429 呼叫點的判別邏輯。
///
/// 舊 server payload 只帶單一 limit 欄位（monthly 或 daily 擇一）；ADR #19 的
/// `buildQuotaExceededPayload` 同時帶 `monthlyLimit` + `dailyLimit`，必須改用
/// remaining vs quotaNeeded 判別是哪個額度擋下這次分析——否則月額度爆掉會被
/// `dailyLimit != null` 先判而誤報成「今日額度已用完」（wait 而非 upgrade，
/// 直接傷 Free→付費轉換；smoke P1 fix 2026-06-11）。
AnalysisException? _quotaExceptionFrom429(Map<String, dynamic> data) {
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

AnalysisException _mapAnalysisHttpError({
  required int statusCode,
  required String? errorCode,
  required String rawMessage,
  required bool hasImages,
  required bool recognizeOnly,
  required bool hasUserDraft,
}) {
  final normalizedMessage = rawMessage.trim();
  final lowerMessage = normalizedMessage.toLowerCase();

  String recognitionUnsupportedMessage() {
    if (normalizedMessage.isEmpty) {
      return '這張圖目前不像可匯入的聊天截圖，請改傳完整聊天視窗後再試。';
    }

    if (_isReadableUserMessage(normalizedMessage)) {
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
        case 'RECOGNITION_UNSUPPORTED':
          return AnalysisException(
            recognitionUnsupportedMessage(),
            code: errorCode,
            suggestedAction: AnalysisErrorAction.rescreenshot,
          );
        case 'RECOGNITION_FAILED':
          return AnalysisException(
            _isReadableUserMessage(normalizedMessage) &&
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
      // monthlyLimit/dailyLimit 鍵，所以不會被 _quotaExceptionFrom429
      // 判成訂閱額度（那會誤導升級 paywall CTA）。wait 而非 retry。
      // MODEL_RATE_LIMITED＝analyze 模型呼叫限流（6/分、60/天），同型契約
      // （docs/plans/2026-07-03-model-rate-limit-design.md）。
      if (errorCode == 'OCR_RATE_LIMITED' ||
          errorCode == 'MODEL_RATE_LIMITED') {
        return AnalysisException(
          _isReadableUserMessage(normalizedMessage) &&
                  normalizedMessage.isNotEmpty
              ? normalizedMessage
              : errorCode == 'OCR_RATE_LIMITED'
                  ? '截圖辨識太頻繁，請稍等一下再試。'
                  : '請求太頻繁，請稍後再試。',
          code: errorCode,
          suggestedAction: AnalysisErrorAction.wait,
        );
      }
      // 其他 429（訂閱額度）已在呼叫端被 _quotaExceptionFrom429 接走；
      // 走到這代表 payload 缺額度欄位，保守給 wait。
      return AnalysisException(
        '請求太頻繁，請稍後再試。',
        code: errorCode ?? 'RATE_LIMITED',
        suggestedAction: AnalysisErrorAction.wait,
      );
    case 502:
    case 503:
    case 504:
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
                ? '訊息優化服務目前較忙，請稍後再試。'
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
                ? '訊息優化暫時失敗，請稍後再試。'
                : '分析暫時失敗，請稍後再試。',
        code: errorCode ?? 'UNKNOWN_HTTP_ERROR',
        suggestedAction: AnalysisErrorAction.retry,
      );
  }
}

AnalysisException _mapUnexpectedAnalysisError(
  Object error, {
  required bool hasImages,
  required bool recognizeOnly,
  required bool hasUserDraft,
}) {
  final errorMessage = error.toString();

  if (errorMessage.contains('Unauthorized') || errorMessage.contains('401')) {
    return AnalysisException(
      '登入狀態已失效，請重新登入後再試。',
      code: 'UNAUTHORIZED',
      suggestedAction: AnalysisErrorAction.relogin,
    );
  }

  if (errorMessage.contains('SocketException') ||
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
              ? '訊息優化花太久了，請稍後再試。'
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
            ? '訊息優化暫時失敗，請稍後再試。'
            : '分析暫時失敗，請稍後再試。',
    code: 'UNEXPECTED_ERROR',
    suggestedAction: AnalysisErrorAction.retry,
  );
}

class AnalysisService {
  static const Duration _streamConnectTimeout = Duration(seconds: 45);
  static const Duration _streamIdleTimeout = Duration(seconds: 120);

  static const _retriableCodes = <String>{
    'NETWORK_ERROR',
    'TIMEOUT',
    'UNEXPECTED_ERROR',
    'UPSTREAM_UNAVAILABLE',
  };

  /// 圖片完整分析（已扣費路徑）的 TIMEOUT 不自動重試：server Claude timeout
  /// 120s（parse 失敗再 retry 最壞 +120s）≥ client 120s，client timeout 時
  /// server 很可能已完成並扣費，自動重打會讓一次操作重複扣 2-3 則。
  /// recognizeOnly 免費、無圖路徑走 stream 有 run-id 豁免，維持自動重試。
  @visibleForTesting
  static bool isAutoRetriableAnalysisError({
    required String? code,
    required bool hasImages,
    required bool recognizeOnly,
  }) {
    if (code == null || !_retriableCodes.contains(code)) {
      return false;
    }
    if (code == 'TIMEOUT' && hasImages && !recognizeOnly) {
      return false;
    }
    return true;
  }

  final http.Client Function() _clientFactory;
  final String? Function() _accessTokenProvider;
  final String? Function() _expectedTierProvider;
  final Future<String?> Function() _revenueCatAppUserIdProvider;

  AnalysisService({
    http.Client Function()? clientFactory,
    String? Function()? accessTokenProvider,
    String? Function()? expectedTierProvider,
    Future<String?> Function()? revenueCatAppUserIdProvider,
  })  : _clientFactory = clientFactory ?? http.Client.new,
        _accessTokenProvider =
            accessTokenProvider ?? (() => SupabaseService.accessToken),
        _expectedTierProvider =
            expectedTierProvider ?? _defaultExpectedTierProvider,
        _revenueCatAppUserIdProvider =
            revenueCatAppUserIdProvider ?? _defaultRevenueCatAppUserIdProvider;

  static String? _defaultExpectedTierProvider() {
    try {
      final tier = SubscriptionTierHelper.normalizeTier(
        UsageService().getLocalUsage().tier,
      );
      return tier == SubscriptionTierHelper.free ? null : tier;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _defaultRevenueCatAppUserIdProvider() async {
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

  Future<_AnalysisEntitlementContext> _buildEntitlementContext() async {
    final expectedTier = SubscriptionTierHelper.normalizeTier(
      _expectedTierProvider(),
    );
    if (expectedTier == SubscriptionTierHelper.free) {
      return const _AnalysisEntitlementContext();
    }

    final revenueCatAppUserId = await _revenueCatAppUserIdProvider();
    final cleanedRevenueCatAppUserId = revenueCatAppUserId?.trim();
    return _AnalysisEntitlementContext(
      expectedTier: expectedTier,
      revenueCatAppUserId: cleanedRevenueCatAppUserId == null ||
              cleanedRevenueCatAppUserId.isEmpty
          ? null
          : cleanedRevenueCatAppUserId,
    );
  }

  Future<AnalysisResult> analyzeConversation(
    List<Message> messages, {
    List<Uint8List>? images,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    String? userDraft,
    String? analyzeMode,
    bool recognizeOnly = false,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
    AnalysisProgressCallback? onProgress,
    AnalysisTelemetryCallback? onTelemetry,
  }) async {
    final sanitizedMessages = recognizeOnly
        ? messages.where((message) => message.id != 'placeholder').toList()
        : messages;

    if (sanitizedMessages.isEmpty && !recognizeOnly) {
      throw AnalysisException(
        '請先加入對話內容再分析。',
        code: 'EMPTY_MESSAGES',
        suggestedAction: AnalysisErrorAction.addIncomingMessage,
      );
    }

    const maxRetries = 2;

    Exception? lastError;

    _debugLog('[AnalysisService] analyzeConversation start');
    _debugLog(
      '[AnalysisService] messages: ${sanitizedMessages.length}, images: ${images?.length ?? 0}, recognizeOnly: $recognizeOnly',
    );

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        _debugLog(
          '[AnalysisService] attempt ${attempt + 1}/${maxRetries + 1}',
        );
        return await _doAnalyze(
          sanitizedMessages,
          images: images,
          sessionContext: sessionContext,
          conversationSummary: conversationSummary,
          partnerSummary: partnerSummary,
          effectiveStyleContext: effectiveStyleContext,
          knownContactName: knownContactName,
          userDraft: userDraft,
          analyzeMode: analyzeMode,
          recognizeOnly: recognizeOnly,
          previousAnalyzedCount: previousAnalyzedCount,
          previousAnalyzedCharCount: previousAnalyzedCharCount,
          confirmedOvercharge: confirmedOvercharge,
          onProgress: onProgress,
          onTelemetry: onTelemetry,
        );
      } catch (error) {
        _debugLog(
          '[AnalysisService] attempt ${attempt + 1} failed: ${error.runtimeType} - $error',
        );
        lastError = error is Exception ? error : Exception(error.toString());

        if (error is AnalysisException &&
            !isAutoRetriableAnalysisError(
              code: error.code,
              hasImages: images != null && images.isNotEmpty,
              recognizeOnly: recognizeOnly,
            )) {
          rethrow;
        }

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }
    }

    throw lastError ?? AnalysisException('分析暫時失敗，請稍後再試。');
  }

  Map<String, dynamic> _decodeResponseBody(http.Response response) {
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

  Map<String, dynamic>? _normalizeObject(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    return null;
  }

  Duration? _durationFromMilliseconds(dynamic value) {
    if (value is num) {
      return Duration(milliseconds: value.round());
    }

    return null;
  }

  Future<AnalysisResult> _doAnalyze(
    List<Message> messages, {
    List<Uint8List>? images,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    String? userDraft,
    String? analyzeMode,
    required bool recognizeOnly,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
    AnalysisProgressCallback? onProgress,
    AnalysisTelemetryCallback? onTelemetry,
  }) async {
    final hasUserDraft = userDraft != null && userDraft.trim().isNotEmpty;
    final hasImages = images != null && images.isNotEmpty;

    try {
      final overallStartTime = DateTime.now();
      final imageCount = images?.length ?? 0;

      onProgress?.call(
        AnalysisProgressUpdate(
          stage: AnalysisProgressStage.preparingPayload,
          imageCount: imageCount,
          elapsed: Duration.zero,
        ),
      );

      List<Map<String, dynamic>>? imageDataList;
      if (hasImages) {
        imageDataList = images.asMap().entries.map((entry) {
          final base64Data = base64Encode(entry.value);
          return ImageData(
            data: base64Data,
            mediaType: 'image/jpeg',
            order: entry.key + 1,
          ).toJson();
        }).toList();
      }

      final timeout = hasImages
          ? const Duration(seconds: 120)
          : const Duration(seconds: 60);

      // 走注入的 provider（預設即 SupabaseService.accessToken），測試才能
      // 不初始化 Supabase 就打到 HTTP 層。
      final accessToken = _accessTokenProvider();
      if (accessToken == null) {
        throw AnalysisException(
          '請先重新登入後再試。',
          code: 'UNAUTHORIZED',
          suggestedAction: AnalysisErrorAction.relogin,
        );
      }

      final entitlementContext = await _buildEntitlementContext();
      final requestBody = {
        'messages': messages
            .map(
              (message) => {
                'isFromMe': message.isFromMe,
                'content': message.content,
                if (message.quotedReplyPreview != null &&
                    message.quotedReplyPreview!.trim().isNotEmpty)
                  'quotedReplyPreview': message.quotedReplyPreview!.trim(),
                if (message.quotedReplyPreview != null &&
                    message.quotedReplyPreview!.trim().isNotEmpty &&
                    message.quotedReplyPreviewIsFromMe != null)
                  'quotedReplyPreviewIsFromMe':
                      message.quotedReplyPreviewIsFromMe,
              },
            )
            .toList(),
        if (imageDataList != null) 'images': imageDataList,
        if (sessionContext != null)
          'sessionContext': {
            'meetingContext': sessionContext.meetingContext.label,
            'duration': sessionContext.duration.label,
            'goal': sessionContext.goal.label,
            if (sessionContext.analysisContextNote != null &&
                sessionContext.analysisContextNote!.trim().isNotEmpty)
              'analysisContextNote': sessionContext.analysisContextNote!.trim(),
          },
        if (conversationSummary != null &&
            conversationSummary.trim().isNotEmpty)
          'conversationSummary': conversationSummary.trim(),
        if (partnerSummary != null && partnerSummary.trim().isNotEmpty)
          'partnerSummary': partnerSummary.trim(),
        if (effectiveStyleContext != null &&
            effectiveStyleContext.trim().isNotEmpty)
          'effectiveStyleContext': effectiveStyleContext.trim(),
        if (knownContactName != null && knownContactName.trim().isNotEmpty)
          'knownContactName': knownContactName.trim(),
        if (hasUserDraft) 'userDraft': userDraft.trim(),
        if (analyzeMode != null) 'analyzeMode': analyzeMode,
        if (recognizeOnly) 'recognizeOnly': true,
        if (previousAnalyzedCount != null && previousAnalyzedCount > 0)
          'previousAnalyzedCount': previousAnalyzedCount,
        // ADR #19 定案 #6 capability contract：所有 analyze 請求必送。
        'billingProtocolVersion': MessageCalculator.billingProtocolVersion,
        if (previousAnalyzedCharCount != null && previousAnalyzedCharCount > 0)
          'previousAnalyzedCharCount': previousAnalyzedCharCount,
        if (confirmedOvercharge != null)
          'confirmedOvercharge': confirmedOvercharge.toJson(),
        if (entitlementContext.expectedTier != null)
          'expectedTier': entitlementContext.expectedTier,
        if (entitlementContext.revenueCatAppUserId != null)
          'revenueCatAppUserId': entitlementContext.revenueCatAppUserId,
      };

      final encodedRequestBody = jsonEncode(requestBody);
      final requestBodyBytes = utf8.encode(encodedRequestBody).length;
      final payloadPreparationDuration =
          DateTime.now().difference(overallStartTime);

      onProgress?.call(
        AnalysisProgressUpdate(
          stage: AnalysisProgressStage.uploadingRequest,
          imageCount: imageCount,
          elapsed: payloadPreparationDuration,
          requestBodyBytes: requestBodyBytes,
        ),
      );

      // 走注入的 factory（預設即 http.Client.new，同 analyzeQuick/analyzeFull），
      // 測試才能攔截 recognizeOnly 的 HTTP 層。
      final httpClient = _clientFactory();
      try {
        final requestStartTime = DateTime.now();
        final awaitingAiTimer = Timer(const Duration(milliseconds: 700), () {
          onProgress?.call(
            AnalysisProgressUpdate(
              stage: AnalysisProgressStage.awaitingAi,
              imageCount: imageCount,
              elapsed: DateTime.now().difference(requestStartTime),
              requestBodyBytes: requestBodyBytes,
            ),
          );
        });

        try {
          final httpResponse = await httpClient
              .post(
                Uri.parse('${AppConfig.supabaseUrl}/functions/v1/analyze-chat'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $accessToken',
                  'apikey': AppConfig.supabaseAnonKey,
                },
                body: encodedRequestBody,
              )
              .timeout(timeout);

          awaitingAiTimer.cancel();

          final roundTripDuration = DateTime.now().difference(requestStartTime);
          final responseData = _decodeResponseBody(httpResponse);
          final telemetryData = _normalizeObject(responseData['telemetry']);

          onTelemetry?.call(
            AnalysisTelemetry(
              requestType: telemetryData?['requestType'] as String?,
              imageCount: imageCount,
              requestBodyBytes: requestBodyBytes,
              payloadPreparationDuration: payloadPreparationDuration,
              roundTripDuration: roundTripDuration,
              edgeAiDuration: _durationFromMilliseconds(
                telemetryData?['serverAiLatencyMs'],
              ),
              totalCompressedImageBytes:
                  telemetryData?['totalImageBytes'] is num
                      ? (telemetryData?['totalImageBytes'] as num).round()
                      : null,
              cacheHit: false,
              fallbackUsed: telemetryData?['fallbackUsed'] == true,
              retryCount: telemetryData?['retries'] is num
                  ? (telemetryData?['retries'] as num).round()
                  : 0,
              timeoutDuration: _durationFromMilliseconds(
                telemetryData?['timeoutMs'],
              ),
              allowModelFallback: telemetryData?['allowModelFallback'] as bool?,
              contextMode: telemetryData?['contextMode'] as String?,
              inputMessageCount: telemetryData?['inputMessageCount'] is num
                  ? (telemetryData?['inputMessageCount'] as num).round()
                  : null,
              compiledMessageCount:
                  telemetryData?['compiledMessageCount'] is num
                      ? (telemetryData?['compiledMessageCount'] as num).round()
                      : null,
              truncatedMessageCount:
                  telemetryData?['truncatedMessageCount'] is num
                      ? (telemetryData?['truncatedMessageCount'] as num).round()
                      : null,
              openingMessagesUsed: telemetryData?['openingMessagesUsed'] is num
                  ? (telemetryData?['openingMessagesUsed'] as num).round()
                  : null,
              recentMessagesUsed: telemetryData?['recentMessagesUsed'] is num
                  ? (telemetryData?['recentMessagesUsed'] as num).round()
                  : null,
              conversationSummaryUsed:
                  telemetryData?['conversationSummaryUsed'] == true,
              recognizedClassification:
                  telemetryData?['recognizedClassification'] as String?,
              recognizedConfidence:
                  telemetryData?['recognizedConfidence'] as String?,
              recognizedSideConfidence:
                  telemetryData?['recognizedSideConfidence'] as String?,
              recognizedMessageCount: telemetryData?['recognizedMessageCount']
                      is num
                  ? (telemetryData?['recognizedMessageCount'] as num).round()
                  : null,
              uncertainSideCount: telemetryData?['uncertainSideCount'] is num
                  ? (telemetryData?['uncertainSideCount'] as num).round()
                  : null,
              continuityAdjustedCount: telemetryData?['continuityAdjustedCount']
                      is num
                  ? (telemetryData?['continuityAdjustedCount'] as num).round()
                  : null,
              groupedAdjustedCount:
                  telemetryData?['groupedAdjustedCount'] is num
                      ? (telemetryData?['groupedAdjustedCount'] as num).round()
                      : null,
              layoutFirstAdjustedCount:
                  telemetryData?['layoutFirstAdjustedCount'] is num
                      ? (telemetryData?['layoutFirstAdjustedCount'] as num)
                          .round()
                      : null,
              systemRowsRemovedCount: telemetryData?['systemRowsRemovedCount']
                      is num
                  ? (telemetryData?['systemRowsRemovedCount'] as num).round()
                  : null,
              quotedPreviewRemovedCount:
                  telemetryData?['quotedPreviewRemovedCount'] is num
                      ? (telemetryData?['quotedPreviewRemovedCount'] as num)
                          .round()
                      : null,
              quotedPreviewAttachedCount:
                  telemetryData?['quotedPreviewAttachedCount'] is num
                      ? (telemetryData?['quotedPreviewAttachedCount'] as num)
                          .round()
                      : null,
              overlapRemovedCount: telemetryData?['overlapRemovedCount'] is num
                  ? (telemetryData?['overlapRemovedCount'] as num).round()
                  : null,
              shouldChargeQuota: telemetryData?['shouldChargeQuota'] as bool?,
              chargedMessageCount: telemetryData?['chargedMessageCount'] is num
                  ? (telemetryData?['chargedMessageCount'] as num).round()
                  : null,
              estimatedMessageCount:
                  telemetryData?['estimatedMessageCount'] is num
                      ? (telemetryData?['estimatedMessageCount'] as num).round()
                      : null,
              quotaReason: telemetryData?['quotaReason'] as String?,
            ),
          );

          final status = httpResponse.statusCode;
          if (responseData['_nonJson'] == true && status == 200) {
            throw AnalysisException(
              '這次分析沒順利完成，請稍後再試。',
              code: 'INVALID_RESPONSE_FORMAT',
              suggestedAction: AnalysisErrorAction.retry,
            );
          }

          if (status != 200) {
            final errorCode = responseData['code'] as String?;
            final errorMessage = responseData['message'] as String? ??
                responseData['error'] as String? ??
                (responseData['_nonJson'] == true
                    ? '伺服器暫時無法正確回應，請稍後再試。'
                    : 'Analysis failed');

            if (status == 429) {
              final quotaException = _quotaExceptionFrom429(responseData);
              if (quotaException != null) throw quotaException;
            }

            throw _mapAnalysisHttpError(
              statusCode: status,
              errorCode: errorCode,
              rawMessage: errorMessage,
              hasImages: hasImages,
              recognizeOnly: recognizeOnly,
              hasUserDraft: hasUserDraft,
            );
          }

          return AnalysisResult.fromJson(responseData);
        } finally {
          awaitingAiTimer.cancel();
        }
      } finally {
        httpClient.close();
      }
    } on TimeoutException {
      throw AnalysisException(
        hasImages
            ? recognizeOnly
                ? '截圖辨識花太久了，請稍後再試。'
                : '圖片分析花太久了，請稍後再試。'
            : hasUserDraft
                ? '訊息優化花太久了，請稍後再試。'
                : '分析花太久了，請稍後再試。',
        code: 'TIMEOUT',
        suggestedAction: AnalysisErrorAction.wait,
      );
    } catch (error) {
      if (error is AnalysisException) {
        rethrow;
      }

      throw _mapUnexpectedAnalysisError(
        error,
        hasImages: hasImages,
        recognizeOnly: recognizeOnly,
        hasUserDraft: hasUserDraft,
      );
    }
  }

  /// Legacy quick/full rollback — recommendation phase.
  ///
  /// Posts `responseMode: 'quick'` to `analyze-chat`. Returns a [AnalysisRecommendationPreview]
  /// carrying the `analysisRunId` that [analyzeFull] must echo.
  Future<AnalysisRecommendationPreview> analyzeQuick({
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
  }) async {
    final entitlementContext = await _buildEntitlementContext();
    final responseData = await _postAnalyzeModeRequest(
      body: _buildAnalyzeModeBody(
        responseMode: 'quick',
        analysisRunId: null,
        messages: messages,
        sessionContext: sessionContext,
        conversationSummary: conversationSummary,
        partnerSummary: partnerSummary,
        effectiveStyleContext: effectiveStyleContext,
        knownContactName: knownContactName,
        previousAnalyzedCount: previousAnalyzedCount,
        previousAnalyzedCharCount: previousAnalyzedCharCount,
        confirmedOvercharge: confirmedOvercharge,
        entitlementContext: entitlementContext,
      ),
      timeout: const Duration(seconds: 15),
    );
    try {
      return AnalysisRecommendationPreview.fromJson(responseData);
    } on FormatException catch (_) {
      // Backend should not return a malformed 200, but if it does the user has
      // already been charged quick quota. Surface a coded error so the
      // notifier maps it to a failedBeforeRecommendation state and the UI offers retry rather
      // than rendering blank fields (I-P3).
      throw AnalysisException(
        '這次分析沒順利完成，請稍後再試。',
        code: 'INVALID_QUICK_RESPONSE',
      );
    }
  }

  /// Legacy quick/full rollback — full phase.
  ///
  /// Echoes [analysisRunId] from a prior [analyzeQuick] so the server can match
  /// the run, validate conversation hash, and avoid double-charging quota (I1).
  /// Maps server `RUN_*` codes to [FullModeException] so the orchestrator can
  /// decide between user-facing retry CTA and a hard "重新分析" path.
  Future<AnalysisResult> analyzeFull({
    required String analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
  }) async {
    final entitlementContext = await _buildEntitlementContext();
    final responseData = await _postAnalyzeModeRequest(
      body: _buildAnalyzeModeBody(
        responseMode: 'full',
        analysisRunId: analysisRunId,
        messages: messages,
        sessionContext: sessionContext,
        conversationSummary: conversationSummary,
        partnerSummary: partnerSummary,
        effectiveStyleContext: effectiveStyleContext,
        knownContactName: knownContactName,
        previousAnalyzedCount: previousAnalyzedCount,
        previousAnalyzedCharCount: previousAnalyzedCharCount,
        entitlementContext: entitlementContext,
      ),
      timeout: const Duration(seconds: 60),
      onErrorResponse: _mapFullModeError,
    );
    return AnalysisResult.fromJson(_extractFullResultPayload(responseData));
  }

  Stream<AnalysisStreamUpdate> analyzeStream({
    String? analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
  }) async* {
    final accessToken = _accessTokenProvider();
    if (accessToken == null) {
      throw AnalysisException(
        '請重新登入後再分析。',
        code: 'UNAUTHORIZED',
        suggestedAction: AnalysisErrorAction.relogin,
      );
    }

    final entitlementContext = await _buildEntitlementContext();
    final client = _clientFactory();
    String? runId;
    int? etaSeconds;
    var sawTypedStreamEvent = false;
    var sawDone = false;

    try {
      final request = http.Request(
        'POST',
        Uri.parse('${AppConfig.supabaseUrl}/functions/v1/analyze-chat'),
      )
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
          'apikey': AppConfig.supabaseAnonKey,
        })
        ..body = jsonEncode(
          _buildAnalyzeModeBody(
            responseMode: 'stream',
            analysisRunId: analysisRunId,
            messages: messages,
            sessionContext: sessionContext,
            conversationSummary: conversationSummary,
            partnerSummary: partnerSummary,
            effectiveStyleContext: effectiveStyleContext,
            knownContactName: knownContactName,
            previousAnalyzedCount: previousAnalyzedCount,
            previousAnalyzedCharCount: previousAnalyzedCharCount,
            confirmedOvercharge: confirmedOvercharge,
            entitlementContext: entitlementContext,
          ),
        );

      final response =
          await client.send(request).timeout(_streamConnectTimeout);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        final responseData = _decodeResponseBody(
          http.Response(body, response.statusCode, headers: response.headers),
        );

        if (response.statusCode == 429) {
          final quotaException = _quotaExceptionFrom429(responseData);
          if (quotaException != null) throw quotaException;
        }

        throw _mapAnalysisHttpError(
          statusCode: response.statusCode,
          errorCode: responseData['code'] as String?,
          rawMessage: (responseData['message'] as String?) ??
              (responseData['error'] as String?) ??
              'Streaming analysis failed.',
          hasImages: false,
          recognizeOnly: false,
          hasUserDraft: false,
        );
      }

      await for (final rawLine in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_streamIdleTimeout)) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        final event = _decodeStreamEventLine(line);
        final type = event['type'] as String?;

        if (type == null) {
          if (!sawTypedStreamEvent) {
            final resultPayload = _streamResultPayload(event);
            if (resultPayload != null) {
              sawDone = true;
              yield AnalysisStreamUpdate.done(
                result: _parseStreamAnalysisResult(resultPayload),
                rawEvent: event,
              );
              return;
            }
          }
          throw AnalysisException(
            '這次分析沒順利完成，請重新分析一次。',
            code: 'INVALID_STREAM_RESPONSE',
            suggestedAction: AnalysisErrorAction.retry,
          );
        }

        sawTypedStreamEvent = true;
        runId = _stringField(event['runId']) ?? runId;
        etaSeconds = _intField(event['etaSeconds']) ?? etaSeconds;

        switch (type) {
          case 'analysis.started':
            yield AnalysisStreamUpdate.started(
              runId: runId,
              label: AnalysisStreamContent._displayTextField(
                    event['label'],
                  ) ??
                  '開始完整分析',
              detail: AnalysisStreamContent._displayTextField(
                event['detail'],
              ),
              etaSeconds: etaSeconds,
              rawEvent: event,
            );
            break;
          case 'analysis.progress':
            yield AnalysisStreamUpdate.progress(
              runId: runId,
              label: AnalysisStreamContent._displayTextField(
                    event['label'],
                  ) ??
                  '完整分析進行中',
              detail: AnalysisStreamContent._displayTextField(
                event['detail'],
              ),
              etaSeconds: etaSeconds,
              rawEvent: event,
            );
            break;
          case 'analysis.decision':
          case 'analysis.reply_option':
          case 'analysis.metrics':
          case 'analysis.coach_hint':
          case 'analysis.report_section':
            final content = AnalysisStreamContent.fromEvent(event);
            if (content == null || content.body.trim().isEmpty) {
              break;
            }
            yield AnalysisStreamUpdate.content(
              content: content,
              runId: runId,
              label: content.title,
              detail: content.body,
              etaSeconds: etaSeconds,
              rawEvent: event,
            );
            break;
          case 'analysis.recommendation':
            final recommendationPreview = _streamRecommendationPreview(
              event,
              runId: runId,
              etaSeconds: etaSeconds,
            );
            yield AnalysisStreamUpdate.recommendation(
              recommendationPreview: recommendationPreview,
              runId: runId,
              label: '先產生建議回覆',
              detail: '完整分析仍在補齊脈絡與細節。',
              etaSeconds: etaSeconds,
              rawEvent: event,
            );
            break;
          case 'analysis.done':
            final finalResult = _streamDoneResultPayload(event);
            if (finalResult == null) {
              throw AnalysisException(
                '這次分析沒順利完成，請重新分析一次。',
                code: 'INVALID_STREAM_DONE',
                suggestedAction: AnalysisErrorAction.retry,
              );
            }
            sawDone = true;
            yield AnalysisStreamUpdate.done(
              result: _parseStreamAnalysisResult(finalResult),
              runId: runId,
              label: '完整分析完成',
              etaSeconds: etaSeconds,
              rawEvent: event,
            );
            return;
          case 'analysis.error':
            final recoverable = event['recoverable'] != false;
            final rawErrorMessage = _stringField(event['message']);
            if (rawErrorMessage != null) {
              _debugLog(
                '[analyze.stream] analysis.error raw message: $rawErrorMessage',
              );
            }
            throw StreamModeException(
              _friendlyStreamErrorMessage(rawErrorMessage),
              code: _stringField(event['code']) ?? 'STREAM_FAILED',
              recoverable: recoverable,
              retriesRemaining:
                  _intField(event['retriesRemaining']) ?? (recoverable ? 1 : 0),
              suggestedAction: recoverable
                  ? AnalysisErrorAction.retry
                  : AnalysisErrorAction.wait,
            );
          default:
            break;
        }
      }

      if (!sawDone) {
        throw AnalysisException(
          '這次分析還沒完成，請重新分析一次。',
          code: 'STREAM_INCOMPLETE',
          suggestedAction: AnalysisErrorAction.retry,
        );
      }
    } on TimeoutException {
      throw AnalysisException(
        '這次分析等待過久，請稍後重新分析。',
        code: 'TIMEOUT',
        suggestedAction: AnalysisErrorAction.wait,
      );
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _extractFullResultPayload(
    Map<String, dynamic> responseData,
  ) {
    final result = responseData['result'];
    if (result is Map<String, dynamic>) {
      return result;
    }
    if (result is Map) {
      return result.map((key, value) => MapEntry(key.toString(), value));
    }

    if (responseData['responseMode'] == 'full') {
      throw AnalysisException(
        '完整分析資料異常，請再試一次。',
        code: 'INVALID_FULL_RESPONSE',
        suggestedAction: AnalysisErrorAction.retry,
      );
    }

    return responseData;
  }

  Map<String, dynamic> _decodeStreamEventLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      // Fall through to the typed AnalysisException below.
    }

    throw AnalysisException(
      '這次分析沒順利完成，請重新分析一次。',
      code: 'INVALID_STREAM_RESPONSE',
      suggestedAction: AnalysisErrorAction.retry,
    );
  }

  Map<String, dynamic>? _streamResultPayload(Map<String, dynamic> event) {
    final nestedResult = _normalizeObject(event['result']);
    if (nestedResult != null) return nestedResult;

    final looksLikeResult = event.containsKey('finalRecommendation') ||
        event.containsKey('replies') ||
        (event.containsKey('gameStage') && event.containsKey('enthusiasm'));
    return looksLikeResult ? event : null;
  }

  Map<String, dynamic>? _streamDoneResultPayload(Map<String, dynamic> event) {
    final finalResult = _normalizeObject(event['finalResult']);
    if (finalResult != null) return finalResult;

    final result = _normalizeObject(event['result']);
    if (result != null) return result;

    return _streamResultPayload(event);
  }

  AnalysisResult _parseStreamAnalysisResult(Map<String, dynamic> payload) {
    try {
      return AnalysisResult.fromJson(payload);
    } catch (_) {
      throw AnalysisException(
        '這次分析沒順利完成，請重新分析一次。',
        code: 'INVALID_STREAM_RESULT',
        suggestedAction: AnalysisErrorAction.retry,
      );
    }
  }

  AnalysisRecommendationPreview _streamRecommendationPreview(
    Map<String, dynamic> event, {
    required String? runId,
    required int? etaSeconds,
  }) {
    final message = _stringField(event['message']);
    if (message == null || message.isEmpty) {
      throw AnalysisException(
        '這次分析沒能給出建議回覆，請重新分析一次。',
        code: 'INVALID_STREAM_RECOMMENDATION',
        suggestedAction: AnalysisErrorAction.retry,
      );
    }

    final pick = _normalizeStreamPick(
      _stringField(event['selectedStyle']) ?? _stringField(event['style']),
    );
    final reason = _stringField(event['reason']) ?? '';

    return AnalysisRecommendationPreview(
      analysisRunId:
          runId == null || runId.trim().isEmpty ? 'stream-preview' : runId,
      nextStep: reason.isNotEmpty ? reason : '先用這個方向回覆，完整分析正在完成。',
      pick: pick,
      recommendedReply: message,
      shortReason: reason,
      insufficientContext: false,
      confidence: 'high',
      estimatedFullSeconds: etaSeconds,
    );
  }

  String _normalizeStreamPick(String? value) {
    switch (value) {
      case 'extend':
      case 'resonate':
      case 'tease':
      case 'humor':
      case 'coldRead':
        return value!;
      default:
        return 'extend';
    }
  }

  String? _stringField(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _intField(dynamic value) {
    if (value is num && value.isFinite) return value.round();
    return null;
  }

  Map<String, dynamic> _buildAnalyzeModeBody({
    required String responseMode,
    String? analysisRunId,
    required List<Message> messages,
    SessionContext? sessionContext,
    String? conversationSummary,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? knownContactName,
    int? previousAnalyzedCount,
    int? previousAnalyzedCharCount,
    OverchargeConfirmationPayload? confirmedOvercharge,
    _AnalysisEntitlementContext entitlementContext =
        const _AnalysisEntitlementContext(),
  }) {
    return {
      'responseMode': responseMode,
      if (analysisRunId != null) 'analysisRunId': analysisRunId,
      'messages': messages
          .map(
            (message) => {
              'isFromMe': message.isFromMe,
              'content': message.content,
              if (message.quotedReplyPreview != null &&
                  message.quotedReplyPreview!.trim().isNotEmpty)
                'quotedReplyPreview': message.quotedReplyPreview!.trim(),
              if (message.quotedReplyPreview != null &&
                  message.quotedReplyPreview!.trim().isNotEmpty &&
                  message.quotedReplyPreviewIsFromMe != null)
                'quotedReplyPreviewIsFromMe':
                    message.quotedReplyPreviewIsFromMe,
            },
          )
          .toList(),
      if (sessionContext != null)
        'sessionContext': {
          'meetingContext': sessionContext.meetingContext.label,
          'duration': sessionContext.duration.label,
          'goal': sessionContext.goal.label,
          if (sessionContext.analysisContextNote != null &&
              sessionContext.analysisContextNote!.trim().isNotEmpty)
            'analysisContextNote': sessionContext.analysisContextNote!.trim(),
        },
      if (conversationSummary != null && conversationSummary.trim().isNotEmpty)
        'conversationSummary': conversationSummary.trim(),
      if (partnerSummary != null && partnerSummary.trim().isNotEmpty)
        'partnerSummary': partnerSummary.trim(),
      if (effectiveStyleContext != null &&
          effectiveStyleContext.trim().isNotEmpty)
        'effectiveStyleContext': effectiveStyleContext.trim(),
      if (knownContactName != null && knownContactName.trim().isNotEmpty)
        'knownContactName': knownContactName.trim(),
      if (previousAnalyzedCount != null && previousAnalyzedCount > 0)
        'previousAnalyzedCount': previousAnalyzedCount,
      // ADR #19 定案 #6 capability contract：所有 analyze 請求必送。
      'billingProtocolVersion': MessageCalculator.billingProtocolVersion,
      if (previousAnalyzedCharCount != null && previousAnalyzedCharCount > 0)
        'previousAnalyzedCharCount': previousAnalyzedCharCount,
      if (confirmedOvercharge != null)
        'confirmedOvercharge': confirmedOvercharge.toJson(),
      if (entitlementContext.expectedTier != null)
        'expectedTier': entitlementContext.expectedTier,
      if (entitlementContext.revenueCatAppUserId != null)
        'revenueCatAppUserId': entitlementContext.revenueCatAppUserId,
    };
  }

  Future<Map<String, dynamic>> _postAnalyzeModeRequest({
    required Map<String, dynamic> body,
    required Duration timeout,
    Exception Function(int status, Map<String, dynamic> data)? onErrorResponse,
  }) async {
    final accessToken = _accessTokenProvider();
    if (accessToken == null) {
      throw AnalysisException(
        '請先重新登入後再試。',
        code: 'UNAUTHORIZED',
        suggestedAction: AnalysisErrorAction.relogin,
      );
    }

    final client = _clientFactory();
    try {
      final response = await client
          .post(
            Uri.parse('${AppConfig.supabaseUrl}/functions/v1/analyze-chat'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
              'apikey': AppConfig.supabaseAnonKey,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

      final responseData = _decodeResponseBody(response);
      final status = response.statusCode;

      if (responseData['_nonJson'] == true && status == 200) {
        throw AnalysisException(
          '這次分析沒順利完成，請稍後再試。',
          code: 'INVALID_RESPONSE_FORMAT',
          suggestedAction: AnalysisErrorAction.retry,
        );
      }

      if (status == 200) {
        return responseData;
      }

      if (status == 429) {
        final quotaException = _quotaExceptionFrom429(responseData);
        if (quotaException != null) throw quotaException;
      }

      if (onErrorResponse != null) {
        throw onErrorResponse(status, responseData);
      }

      throw AnalysisException(
        (responseData['message'] as String?) ??
            (responseData['error'] as String?) ??
            '分析暫時失敗，請稍後再試。',
        code: responseData['code'] as String?,
        suggestedAction: AnalysisErrorAction.retry,
      );
    } on TimeoutException {
      throw AnalysisException(
        '分析花太久了，請稍後再試。',
        code: 'TIMEOUT',
        suggestedAction: AnalysisErrorAction.wait,
      );
    } finally {
      client.close();
    }
  }

  Exception _mapFullModeError(int status, Map<String, dynamic> data) {
    final code = (data['code'] as String?) ?? (data['error'] as String?);
    final retriesRemainingRaw = data['retriesRemaining'];
    final retriesRemaining =
        retriesRemainingRaw is num ? retriesRemainingRaw.toInt() : 0;

    switch (code) {
      case 'RUN_EXPIRED':
        return FullModeException(
          '分析記錄已過期，請重新分析。',
          code: 'RUN_EXPIRED',
          retriesRemaining: 0,
          suggestedAction: AnalysisErrorAction.retry,
        );
      case 'RUN_CONVERSATION_MISMATCH':
        return FullModeException(
          '對話內容已變動，請重新分析。',
          code: 'RUN_CONVERSATION_MISMATCH',
          retriesRemaining: 0,
          suggestedAction: AnalysisErrorAction.retry,
        );
      case 'RUN_RETRY_EXHAUSTED':
        return FullModeException(
          '完整分析已達重試上限，請重新分析。',
          code: 'RUN_RETRY_EXHAUSTED',
          retriesRemaining: 0,
          suggestedAction: AnalysisErrorAction.retry,
        );
      default:
        return FullModeException(
          (data['message'] as String?) ?? '完整分析失敗，可以重試。',
          code: code ?? 'FULL_FAILED',
          retriesRemaining: retriesRemaining,
          suggestedAction: AnalysisErrorAction.retry,
        );
    }
  }
}

class _AnalysisEntitlementContext {
  const _AnalysisEntitlementContext({
    this.expectedTier,
    this.revenueCatAppUserId,
  });

  final String? expectedTier;
  final String? revenueCatAppUserId;
}

class AnalysisException implements Exception {
  final String message;
  final String? code;
  final AnalysisErrorAction? suggestedAction;

  AnalysisException(
    this.message, {
    this.code,
    this.suggestedAction,
  });

  @override
  String toString() => 'AnalysisException: $message';
}

class StreamModeException extends AnalysisException {
  final bool recoverable;
  final int retriesRemaining;

  StreamModeException(
    super.message, {
    super.code,
    super.suggestedAction,
    required this.recoverable,
    required this.retriesRemaining,
  });
}

class DailyLimitExceededException extends AnalysisException {
  final int dailyLimit;
  final int used;

  /// 429 payload 的 dailyRemaining（server 算好的剩餘則數），可能缺。
  final int? remaining;

  /// 429 payload 的 quotaNeeded（本次分析需要的則數），可能缺。
  final int? quotaNeeded;

  DailyLimitExceededException({
    required this.dailyLimit,
    required this.used,
    this.remaining,
    this.quotaNeeded,
  }) : super(
          '今日額度已用完，可以明天再試，或升級解鎖更多分析。',
          code: 'DAILY_LIMIT_EXCEEDED',
          suggestedAction: AnalysisErrorAction.wait,
        );
}

class MonthlyLimitExceededException extends AnalysisException {
  final int monthlyLimit;
  final int used;

  /// 429 payload 的 monthlyRemaining（server 算好的剩餘則數），可能缺。
  final int? remaining;

  /// 429 payload 的 quotaNeeded（本次分析需要的則數），可能缺。
  final int? quotaNeeded;

  MonthlyLimitExceededException({
    required this.monthlyLimit,
    required this.used,
    this.remaining,
    this.quotaNeeded,
  }) : super(
          '本月額度已用完，升級後可以繼續分析。',
          code: 'MONTHLY_LIMIT_EXCEEDED',
          suggestedAction: AnalysisErrorAction.upgrade,
        );
}

/// Raised when the legacy quick/full `full` phase fails on the server.
///
/// [retriesRemaining] is 0 for terminal failures (`RUN_EXPIRED`,
/// `RUN_CONVERSATION_MISMATCH`, `RUN_RETRY_EXHAUSTED`) and matches the server
/// budget for generic 502 `FULL_FAILED`. The orchestrator uses it to decide
/// whether to surface a retry CTA or force "重新分析".
class FullModeException extends AnalysisException {
  final int retriesRemaining;

  FullModeException(
    super.message, {
    super.code,
    super.suggestedAction,
    required this.retriesRemaining,
  });
}
