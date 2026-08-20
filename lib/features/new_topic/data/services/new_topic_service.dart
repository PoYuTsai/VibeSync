import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../../../../core/config/environment.dart';
import '../../../../core/services/supabase_service.dart';
import '../../domain/entities/new_topic_result.dart';

/// Server 端 request deadline 50s＋settlement reserve；client 70s 讓
/// server 的逾時/結算結果先到（同 opener 慣例）。
const kNewTopicRequestTimeout = Duration(seconds: 70);

typedef NewTopicInvoker = Future<NewTopicInvokeResponse> Function(
  String functionName, {
  required Map<String, dynamic> body,
});

class NewTopicInvokeResponse {
  final int status;
  final dynamic data;

  const NewTopicInvokeResponse({required this.status, this.data});
}

/// 真正 quota 不足（429 quota payload）：開既有 paywall。
class NewTopicQuotaExceededException implements Exception {
  final String message;
  final int? monthlyRemaining;
  final int? dailyRemaining;
  final int? quotaNeeded;

  const NewTopicQuotaExceededException({
    required this.message,
    this.monthlyRemaining,
    this.dailyRemaining,
    this.quotaNeeded,
  });

  @override
  String toString() => message;
}

/// 同 requestId 正在生成中（409 in progress）：保留 requestId 稍後重試。
class NewTopicRequestInProgressException implements Exception {
  final String message;
  final int? retryAfterMs;

  const NewTopicRequestInProgressException({
    required this.message,
    this.retryAfterMs,
  });

  @override
  String toString() => message;
}

/// 一般 localized 錯誤：raw JSON、SQL、RPC、network 英文絕不外露。
class NewTopicException implements Exception {
  final String message;

  /// true＝client 應沿用同 requestId 重試（settlement pending、claim
  /// 不可用等），不得 rotate。
  final bool retrySameRequest;

  const NewTopicException(this.message, {this.retrySameRequest = false});

  @override
  String toString() => message;
}

/// 請求內容可能已被 server 受理，但 client transport 沒拿到終局結果。
/// 只能沿用同 requestId 接回，不能鑄新 id。
class NewTopicTransportException extends NewTopicException {
  const NewTopicTransportException(super.message)
      : super(retrySameRequest: true);
}

/// Server 已明示 request 狀態尚未收斂（例如 settlement 不確定或 claim
/// 暫時無法釋放）。只能短暫等待後沿用同 requestId 查回結果。
class NewTopicStatePendingException extends NewTopicException {
  final int? retryAfterMs;

  const NewTopicStatePendingException({
    required String message,
    this.retryAfterMs,
  }) : super(message, retrySameRequest: true);
}

class NewTopicService {
  NewTopicService({
    NewTopicInvoker? invoker,
    http.Client Function()? streamClientFactory,
    String? Function()? accessTokenProvider,
  })  : _invoke = _mapFunctionExceptions(invoker ?? _defaultInvoker),
        _streamClientFactory = streamClientFactory ?? http.Client.new,
        _accessTokenProvider =
            accessTokenProvider ?? (() => SupabaseService.accessToken);

  final NewTopicInvoker _invoke;
  final http.Client Function() _streamClientFactory;
  final String? Function() _accessTokenProvider;

  /// flag on 時 stream headers 會立刻到；flag off／舊 Edge 會等完整 legacy
  /// 結果才回 headers。server deadline 是 50s，因此 connect 不能沿用 opener
  /// 的 45s，否則 client 會先誤報失敗、server 卻仍持有 pending claim。
  static const Duration _streamConnectTimeout = kNewTopicRequestTimeout;
  static const Duration _streamIdleTimeout = Duration(seconds: 120);

  /// functions_client 2.5.0 對非 2xx 直接丟 [FunctionException]，不會回
  /// [FunctionResponse]。先還原成 service 自己的 response 形狀，才能讓
  /// 409／429／503 共用同一套 typed error 對映，避免 SDK 例外外露到 UI。
  static NewTopicInvoker _mapFunctionExceptions(NewTopicInvoker inner) {
    return (String fn, {required Map<String, dynamic> body}) async {
      try {
        return await inner(fn, body: body);
      } on FunctionException catch (error) {
        return NewTopicInvokeResponse(
          status: error.status,
          data: error.details,
        );
      }
    };
  }

  /// 只回完整 [NewTopicResult]；tier 一律信 server access，不自行推。
  Future<NewTopicResult> generateTopics({
    required String requestId,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? situation,
    String? expectedTier,
    String? revenueCatAppUserId,
  }) async {
    final body = _buildRequestBody(
      requestId: requestId,
      partnerSummary: partnerSummary,
      effectiveStyleContext: effectiveStyleContext,
      situation: situation,
      expectedTier: expectedTier,
      revenueCatAppUserId: revenueCatAppUserId,
    );

    final response = await _invoke('analyze-chat', body: body);

    if (response.status == 200) {
      return _parseSuccessData(response.data, requestId: requestId);
    }
    _throwForErrorResponse(response.status, response.data);
  }

  /// 串流版生成（2026-08-18 呈現精修第 2 包）：`responseMode: 'stream'`，
  /// 進度經 [onProgress] 回報，結果與錯誤對映和 [generateTopics] 完全一致。
  /// server flag off／舊 Edge 回一般 JSON 時依 content-type 自動走 legacy。
  Future<NewTopicResult> generateTopicsStreaming({
    required String requestId,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? situation,
    String? expectedTier,
    String? revenueCatAppUserId,
    void Function(String label, String? phase)? onProgress,
  }) async {
    const maxAttemptCount = 3;
    var attemptCount = 0;
    var inProgressRecoveryCount = 0;
    var transportRecoveryCount = 0;
    var stateRecoveryCount = 0;
    while (true) {
      attemptCount += 1;
      try {
        return await _generateTopicsStreamingOnce(
          requestId: requestId,
          partnerSummary: partnerSummary,
          effectiveStyleContext: effectiveStyleContext,
          situation: situation,
          expectedTier: expectedTier,
          revenueCatAppUserId: revenueCatAppUserId,
          onProgress: onProgress,
        );
      } on NewTopicRequestInProgressException catch (error) {
        // 同 requestId 已由前一條連線受理：不要叫使用者再按一次，也不能
        // rotate id。依 server lease 提示等一次，再用同一 envelope 接回
        // stored result；若第二次仍 pending，交回既有友善錯誤避免無限迴圈。
        if (attemptCount >= maxAttemptCount || inProgressRecoveryCount >= 1) {
          rethrow;
        }
        inProgressRecoveryCount += 1;
        onProgress?.call('同一筆結果還在整理，完成後會自動接回', 'reconnecting');
        await Future<void>.delayed(_inProgressRetryDelay(error.retryAfterMs));
      } on NewTopicTransportException {
        // lost response 不代表 server 沒受理。自動重連一次，同 requestId
        // 會得到 pending 或 replay；第二次仍斷才把友善錯誤交回 UI。
        if (attemptCount >= maxAttemptCount || transportRecoveryCount >= 1) {
          rethrow;
        }
        transportRecoveryCount += 1;
        onProgress?.call('連線剛剛中斷，正在接回同一筆結果', 'reconnecting');
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } on NewTopicStatePendingException catch (error) {
        // 這類 503 代表帳本／claim 狀態還沒收斂，不是可安全鑄新 id 的
        // 一般生成失敗。先用同 id 接一次；若轉成 409，再依 lease 等候。
        if (attemptCount >= maxAttemptCount || stateRecoveryCount >= 1) {
          rethrow;
        }
        stateRecoveryCount += 1;
        onProgress?.call('正在確認同一筆結果，完成後會自動接回', 'reconnecting');
        await Future<void>.delayed(_inProgressRetryDelay(error.retryAfterMs));
      }
    }
  }

  Future<NewTopicResult> _generateTopicsStreamingOnce({
    required String requestId,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? situation,
    String? expectedTier,
    String? revenueCatAppUserId,
    void Function(String label, String? phase)? onProgress,
  }) async {
    final accessToken = _accessTokenProvider();
    if (accessToken == null) {
      throw const NewTopicException('請重新登入後再生成新話題。');
    }

    final body = _buildRequestBody(
      requestId: requestId,
      partnerSummary: partnerSummary,
      effectiveStyleContext: effectiveStyleContext,
      situation: situation,
      expectedTier: expectedTier,
      revenueCatAppUserId: revenueCatAppUserId,
      responseMode: 'stream',
    );

    final client = _streamClientFactory();
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
        ..body = jsonEncode(body);

      final response =
          await client.send(request).timeout(_streamConnectTimeout);
      final contentType = response.headers['content-type'] ?? '';

      if (response.statusCode != 200 || !contentType.contains('x-ndjson')) {
        final bodyText =
            await response.stream.bytesToString().timeout(_streamIdleTimeout);
        dynamic decoded;
        try {
          decoded = bodyText.isEmpty ? null : jsonDecode(bodyText);
        } catch (_) {
          decoded = null;
        }
        // 舊 Edge 對帶 responseMode 的 new_topic 一律 400（claim 之前拒絕、
        // 不扣費）：降級重打一次 legacy 請求（R2 主審 minor-5）。新 Edge 的
        // 真 sanitize 400 會在 legacy 重試時得到同樣錯誤，只多一次呼叫。
        if (response.statusCode == 400 &&
            decoded is Map &&
            decoded['code'] == 'NEW_TOPIC_REQUEST_INVALID') {
          return await generateTopics(
            requestId: requestId,
            partnerSummary: partnerSummary,
            effectiveStyleContext: effectiveStyleContext,
            situation: situation,
            expectedTier: expectedTier,
            revenueCatAppUserId: revenueCatAppUserId,
          );
        }
        if (response.statusCode != 200) {
          _throwForErrorResponse(response.statusCode, decoded);
        }
        return _parseSuccessData(decoded, requestId: requestId);
      }

      await for (final rawLine in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_streamIdleTimeout)) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        final dynamic decoded;
        try {
          decoded = jsonDecode(line);
        } catch (_) {
          continue; // 壞行忽略，等 done/error 終局事件。
        }
        if (decoded is! Map<String, dynamic>) continue;
        final type = decoded['type'] as String?;
        switch (type) {
          case 'new_topic.started':
          case 'new_topic.progress':
            final label = decoded['label'];
            if (label is String && label.trim().isNotEmpty) {
              onProgress?.call(
                label.trim(),
                decoded['phase'] is String ? decoded['phase'] as String : null,
              );
            }
          case 'new_topic.done':
            return _parseSuccessData(decoded['result'], requestId: requestId);
          case 'new_topic.error':
            final status = (decoded['status'] as num?)?.round() ?? 500;
            _throwForErrorResponse(status, decoded);
          default:
            continue; // 未知事件型別向前相容：忽略。
        }
      }
      // 終局事件沒到＝結果不明（server 可能已 settle）：沿用同 requestId
      // 重試會 replay 原結果、不會雙扣。
      throw const NewTopicTransportException(
        '連線中斷，請再試一次；同一筆請求不會重複扣額度。',
      );
    } on TimeoutException {
      throw const NewTopicTransportException(
        '連線逾時，請再試一次；同一筆請求不會重複扣額度。',
      );
    } on http.ClientException {
      throw const NewTopicTransportException(
        '連線中斷，請再試一次；同一筆請求不會重複扣額度。',
      );
    } finally {
      client.close();
    }
  }

  static Duration _inProgressRetryDelay(int? retryAfterMs) {
    final serverDelay = retryAfterMs ?? 1000;
    // 加一點邊界緩衝，避免剛好在 lease 到期前重送又拿到同一個 409；
    // 同時封頂，壞 payload 不得把畫面卡住數分鐘。
    final boundedMs = (serverDelay + 250).clamp(250, 65000);
    return Duration(milliseconds: boundedMs);
  }

  Map<String, dynamic> _buildRequestBody({
    required String requestId,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? situation,
    String? expectedTier,
    String? revenueCatAppUserId,
    String? responseMode,
  }) {
    return <String, dynamic>{
      'mode': 'new_topic',
      'requestId': requestId,
      if (responseMode != null) 'responseMode': responseMode,
      // blank optional fields 不送（server allowlist strict）。
      if (_hasText(partnerSummary)) 'partnerSummary': partnerSummary!.trim(),
      if (_hasText(effectiveStyleContext))
        'effectiveStyleContext': effectiveStyleContext!.trim(),
      if (_hasText(situation)) 'situation': situation!.trim(),
      if (_hasText(expectedTier)) 'expectedTier': expectedTier!.trim(),
      if (_hasText(revenueCatAppUserId))
        'revenueCatAppUserId': revenueCatAppUserId!.trim(),
    };
  }

  NewTopicResult _parseSuccessData(dynamic data, {required String requestId}) {
    final result = NewTopicResult.tryParse(data, requestId: requestId);
    if (result == null) {
      // 半套 200 一律視為失敗；同 requestId 重試會 replay 原結果，
      // 不會雙扣。
      throw const NewTopicException(
        '新話題結果格式異常，請再試一次。',
        retrySameRequest: true,
      );
    }
    return result;
  }

  /// 非 200 的統一對映（legacy 與 stream 共用）：一定 throw。
  Never _throwForErrorResponse(int status, dynamic data) {
    final errorData = data is Map ? data : const {};
    final code = errorData['code']?.toString();
    final serverMessage = _localizedMessage(errorData['message']);

    if (status == 429) {
      if (code == 'MODEL_RATE_LIMITED') {
        throw NewTopicException(
          serverMessage ?? '請求太頻繁，請稍後再試。',
          retrySameRequest: true,
        );
      }
      // 429 但 payload 沒有額度鍵＝不是訂閱額度（lease/限流等其他 429）：
      // 同 analysis_service _quotaExceptionFrom429 的鍵判別式，絕不誤開
      // paywall——額度沒真用完不得擋核心功能。
      if (errorData['monthlyLimit'] == null &&
          errorData['dailyLimit'] == null) {
        throw NewTopicException(
          serverMessage ?? '請求太頻繁，請稍後再試。',
          retrySameRequest: true,
        );
      }
      throw NewTopicQuotaExceededException(
        message: serverMessage ?? '額度不足，請先升級方案。',
        monthlyRemaining: (errorData['monthlyRemaining'] as num?)?.round(),
        dailyRemaining: (errorData['dailyRemaining'] as num?)?.round(),
        quotaNeeded: (errorData['quotaNeeded'] as num?)?.round(),
      );
    }

    if (status == 409 && code == 'NEW_TOPIC_REQUEST_IN_PROGRESS') {
      throw NewTopicRequestInProgressException(
        message: serverMessage ?? '這筆請求正在生成中，請稍候再試。',
        retryAfterMs: (errorData['retryAfterMs'] as num?)?.round(),
      );
    }

    if (code == 'NEW_TOPIC_SETTLEMENT_PENDING' ||
        code == 'NEW_TOPIC_CLAIM_RELEASE_RETRYABLE') {
      throw NewTopicStatePendingException(
        message: serverMessage ?? '這筆請求的結果正在確認，請稍候再試。',
        retryAfterMs: (errorData['retryAfterMs'] as num?)?.round(),
      );
    }

    final retryable = errorData['retryable'] == true ||
        code == 'NEW_TOPIC_SETTLEMENT_PENDING';
    throw NewTopicException(
      serverMessage ??
          (status >= 500 ? 'AI 暫時生成失敗，請稍後再試；本次不會扣額度。' : '新話題生成失敗，請稍後再試。'),
      retrySameRequest: retryable,
    );
  }

  /// 只放行含中文的 server message；工程/網路英文字串換固定中文文案。
  static String? _localizedMessage(dynamic raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return RegExp(r'[一-鿿]').hasMatch(trimmed) ? trimmed : null;
  }

  static bool _hasText(String? value) => value?.trim().isNotEmpty ?? false;
}

Future<NewTopicInvokeResponse> _defaultInvoker(
  String fn, {
  required Map<String, dynamic> body,
}) async {
  final res = await SupabaseService.invokeFunction(
    fn,
    body: body,
    timeout: kNewTopicRequestTimeout,
  );
  return NewTopicInvokeResponse(status: res.status, data: res.data);
}
