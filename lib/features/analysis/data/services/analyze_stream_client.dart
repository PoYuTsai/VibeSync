/// AnalyzeChat 唯一主傳輸：100% NDJSON streaming。
///
/// 這裡沒有 responseMode 參數、沒有 quick/full/plain/legacy 變體、沒有
/// fallback——`stream()` 固定送 `responseMode: 'stream'`，非 NDJSON 的
/// 200 一律報 `INVALID_STREAM_CONTENT_TYPE`。串流事件模型
/// （[AnalysisStreamUpdate]／[AnalysisStreamContent]）與 client 同庫，
/// 因為顯示文字清洗（schema leak sanitize）是事件解析的一部分。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/environment.dart';
import '../../../../core/services/message_calculator.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/analysis_recommendation_preview.dart';
import 'analysis_exceptions.dart';
import 'analysis_transport_support.dart';

/// [AnalyzeStreamClient.stream] 的完整請求描述。欄位即 wire payload 的
/// 來源；`analysisRunId` 非 null 代表 resume 同一 run（不重扣額度）。
class AnalyzeStreamRequest {
  final String? analysisRunId;
  final List<Message> messages;
  final SessionContext? sessionContext;
  final String? conversationSummary;
  final String? partnerSummary;
  final String? effectiveStyleContext;
  final String? knownContactName;
  final int? previousAnalyzedCount;
  final int? previousAnalyzedCharCount;
  final OverchargeConfirmationPayload? confirmedOvercharge;

  const AnalyzeStreamRequest({
    this.analysisRunId,
    required this.messages,
    this.sessionContext,
    this.conversationSummary,
    this.partnerSummary,
    this.effectiveStyleContext,
    this.knownContactName,
    this.previousAnalyzedCount,
    this.previousAnalyzedCharCount,
    this.confirmedOvercharge,
  });
}

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

/// User-facing copy for a streaming `analysis.error` event.
///
/// The server may put engineering English in `message` (e.g. "Quota failed",
/// raw exceptions, error codes, JSON/schema/streaming fragments). Only surface
/// it when it is actually localized (passes [isReadableAnalysisUserMessage]);
/// otherwise return a fixed Chinese fallback. The raw text is sent to
/// [analysisDebugLog] at the call site for debugging only and never reaches the UI.
/// Mirrors the HTTP path's [mapAnalysisHttpError] gate and the opener DATA-01
/// sanitize precedent. Only the user-visible message is rewritten; the event's
/// `code`, `recoverable`, and `retriesRemaining` are preserved by the caller so
/// quota/paywall routing is never eaten.
String _friendlyStreamErrorMessage(String? rawMessage) {
  final message = (rawMessage ?? '').trim();
  if (message.isNotEmpty && isReadableAnalysisUserMessage(message)) {
    return message;
  }
  return '這次分析沒順利完成，請稍後再試一次。';
}

/// AnalyzeChat 主分析的唯一 client。生命週期：connect 45s 圍籬、
/// 事件間 idle 120s 圍籬；非 200 走共用錯誤對映（429 先判額度）。
class AnalyzeStreamClient {
  static const Duration _streamConnectTimeout = Duration(seconds: 45);
  static const Duration _streamIdleTimeout = Duration(seconds: 120);

  final http.Client Function() _clientFactory;
  final String? Function() _accessTokenProvider;
  final String? Function() _expectedTierProvider;
  final Future<String?> Function() _revenueCatAppUserIdProvider;

  AnalyzeStreamClient({
    http.Client Function()? clientFactory,
    String? Function()? accessTokenProvider,
    String? Function()? expectedTierProvider,
    Future<String?> Function()? revenueCatAppUserIdProvider,
  })  : _clientFactory = clientFactory ?? http.Client.new,
        _accessTokenProvider =
            accessTokenProvider ?? (() => SupabaseService.accessToken),
        _expectedTierProvider =
            expectedTierProvider ?? defaultAnalysisExpectedTier,
        _revenueCatAppUserIdProvider =
            revenueCatAppUserIdProvider ?? defaultAnalysisRevenueCatAppUserId;

  Stream<AnalysisStreamUpdate> stream(AnalyzeStreamRequest request) async* {
    final accessToken = _accessTokenProvider();
    if (accessToken == null) {
      throw AnalysisException(
        '請重新登入後再分析。',
        code: 'UNAUTHORIZED',
        suggestedAction: AnalysisErrorAction.relogin,
      );
    }

    final entitlementContext = await buildAnalysisEntitlementContext(
      expectedTierProvider: _expectedTierProvider,
      revenueCatAppUserIdProvider: _revenueCatAppUserIdProvider,
    );
    final client = _clientFactory();
    String? runId;
    int? etaSeconds;
    var sawDone = false;

    try {
      final httpRequest = http.Request(
        'POST',
        Uri.parse('${AppConfig.supabaseUrl}/functions/v1/analyze-chat'),
      )
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
          'apikey': AppConfig.supabaseAnonKey,
        })
        ..body = jsonEncode(_buildStreamBody(request, entitlementContext));

      final response =
          await client.send(httpRequest).timeout(_streamConnectTimeout);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        final responseData = decodeAnalysisResponseBody(
          http.Response(body, response.statusCode, headers: response.headers),
        );

        if (response.statusCode == 429) {
          final quotaException = quotaExceptionFrom429(responseData);
          if (quotaException != null) throw quotaException;
        }

        throw mapAnalysisHttpError(
          statusCode: response.statusCode,
          errorCode: responseData['code'] as String?,
          rawMessage: (responseData['message'] as String?) ??
              (responseData['error'] as String?) ??
              'Streaming analysis failed.',
          hasImages: false,
          recognizeOnly: false,
          hasUserDraft: false,
          // 推薦串流沒有草稿／微調入口。
          hasRefineInstruction: false,
        );
      }

      final contentType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (contentType != 'application/x-ndjson') {
        throw AnalysisException(
          '這次分析沒有以串流方式回傳，請重新分析一次。',
          code: 'INVALID_STREAM_CONTENT_TYPE',
          suggestedAction: AnalysisErrorAction.retry,
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
          throw AnalysisException(
            '這次分析沒順利完成，請重新分析一次。',
            code: 'INVALID_STREAM_RESPONSE',
            suggestedAction: AnalysisErrorAction.retry,
          );
        }

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
              analysisDebugLog(
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
    } catch (error) {
      if (error is AnalysisException) rethrow;
      throw mapUnexpectedAnalysisError(
        error,
        hasImages: false,
        recognizeOnly: false,
        hasUserDraft: false,
        hasRefineInstruction: false,
      );
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _buildStreamBody(
    AnalyzeStreamRequest request,
    AnalysisEntitlementContext entitlementContext,
  ) {
    final sessionContext = request.sessionContext;
    final conversationSummary = request.conversationSummary;
    final partnerSummary = request.partnerSummary;
    final effectiveStyleContext = request.effectiveStyleContext;
    final knownContactName = request.knownContactName;
    final previousAnalyzedCount = request.previousAnalyzedCount;
    final previousAnalyzedCharCount = request.previousAnalyzedCharCount;
    return {
      'responseMode': 'stream',
      if (request.analysisRunId != null) 'analysisRunId': request.analysisRunId,
      'messages': request.messages.map(analysisMessagePayload).toList(),
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
      if (request.confirmedOvercharge != null)
        'confirmedOvercharge': request.confirmedOvercharge!.toJson(),
      if (entitlementContext.expectedTier != null)
        'expectedTier': entitlementContext.expectedTier,
      if (entitlementContext.revenueCatAppUserId != null)
        'revenueCatAppUserId': entitlementContext.revenueCatAppUserId,
    };
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
    final nestedResult = normalizeAnalysisJsonObject(event['result']);
    if (nestedResult != null) return nestedResult;

    final looksLikeResult = event.containsKey('finalRecommendation') ||
        event.containsKey('replies') ||
        (event.containsKey('gameStage') && event.containsKey('enthusiasm'));
    return looksLikeResult ? event : null;
  }

  Map<String, dynamic>? _streamDoneResultPayload(Map<String, dynamic> event) {
    final finalResult = normalizeAnalysisJsonObject(event['finalResult']);
    if (finalResult != null) return finalResult;

    final result = normalizeAnalysisJsonObject(event['result']);
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
      estimatedReportSeconds: etaSeconds,
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
}
