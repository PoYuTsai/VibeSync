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

  /// 上一個 partner-scoped 有效互動階段（弱先驗，閉環規則 8）。
  final String? previousStage;
  final int? analysisFragmentStartIndex;
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
    this.previousStage,
    this.analysisFragmentStartIndex,
    this.previousAnalyzedCount,
    this.previousAnalyzedCharCount,
    this.confirmedOvercharge,
  });
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
}

/// wire decode 之後、顯示映射之前的 seam（data-owned）。
///
/// client 只負責 NDJSON decode 與事件分流；把 event 變成顯示內容
/// （中文標題／內文、schema-leak 清洗）的責任在 presentation 的
/// mapper 實作，於 composition root 注入。production adapter 與測試
/// 走同一條 seam。
abstract class AnalysisStreamDisplayMapper {
  /// 內容型事件 → 顯示內容；不可顯示（未知型別／空內文）回 null。
  AnalysisStreamContent? contentFromEvent(Map<String, dynamic> event);

  /// 進度 label／detail 的顯示守門（trim ＋ schema-leak 清洗）。
  String? displayText(dynamic value);
}

enum AnalysisStreamUpdateKind {
  started,
  progress,
  content,
  recommendation,
  done,
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

  final AnalysisStreamDisplayMapper _displayMapper;
  final http.Client Function() _clientFactory;
  final String? Function() _accessTokenProvider;
  final String? Function() _expectedTierProvider;
  final Future<String?> Function() _revenueCatAppUserIdProvider;

  AnalyzeStreamClient({
    required AnalysisStreamDisplayMapper displayMapper,
    http.Client Function()? clientFactory,
    String? Function()? accessTokenProvider,
    String? Function()? expectedTierProvider,
    Future<String?> Function()? revenueCatAppUserIdProvider,
  })  : _displayMapper = displayMapper,
        _clientFactory = clientFactory ?? http.Client.new,
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
        ..body = jsonEncode(buildStreamBody(request, entitlementContext));

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
              label: _displayMapper.displayText(
                    event['label'],
                  ) ??
                  '開始完整分析',
              detail: _displayMapper.displayText(
                event['detail'],
              ),
              etaSeconds: etaSeconds,
              rawEvent: event,
            );
            break;
          case 'analysis.progress':
            yield AnalysisStreamUpdate.progress(
              runId: runId,
              label: _displayMapper.displayText(
                    event['label'],
                  ) ??
                  '完整分析進行中',
              detail: _displayMapper.displayText(
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
            final content = _displayMapper.contentFromEvent(event);
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

  /// Wire payload builder（公開 seam）：情境接線測試據此驗證
  /// `sessionContext.meetingContext` 等欄位實際送出的值。
  static Map<String, dynamic> buildStreamBody(
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
      if (request.previousStage != null &&
          request.previousStage!.trim().isNotEmpty)
        'previousStage': request.previousStage!.trim(),
      if (request.analysisFragmentStartIndex != null)
        'analysisFragmentStartIndex': request.analysisFragmentStartIndex,
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
