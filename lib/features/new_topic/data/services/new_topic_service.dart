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

class NewTopicService {
  NewTopicService({NewTopicInvoker? invoker})
      : _invoke = invoker ?? _defaultInvoker;

  final NewTopicInvoker _invoke;

  /// 只回完整 [NewTopicResult]；tier 一律信 server access，不自行推。
  Future<NewTopicResult> generateTopics({
    required String requestId,
    String? partnerSummary,
    String? effectiveStyleContext,
    String? situation,
    String? expectedTier,
    String? revenueCatAppUserId,
  }) async {
    final body = <String, dynamic>{
      'mode': 'new_topic',
      'requestId': requestId,
      // blank optional fields 不送（server allowlist strict）。
      if (_hasText(partnerSummary)) 'partnerSummary': partnerSummary!.trim(),
      if (_hasText(effectiveStyleContext))
        'effectiveStyleContext': effectiveStyleContext!.trim(),
      if (_hasText(situation)) 'situation': situation!.trim(),
      if (_hasText(expectedTier)) 'expectedTier': expectedTier!.trim(),
      if (_hasText(revenueCatAppUserId))
        'revenueCatAppUserId': revenueCatAppUserId!.trim(),
    };

    final response = await _invoke('analyze-chat', body: body);
    final data = response.data;

    if (response.status == 200) {
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

    final errorData = data is Map ? data : const {};
    final code = errorData['code']?.toString();
    final serverMessage = _localizedMessage(errorData['message']);

    if (response.status == 429) {
      if (code == 'MODEL_RATE_LIMITED') {
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

    if (response.status == 409 && code == 'NEW_TOPIC_REQUEST_IN_PROGRESS') {
      throw NewTopicRequestInProgressException(
        message: serverMessage ?? '這筆請求正在生成中，請稍候再試。',
        retryAfterMs: (errorData['retryAfterMs'] as num?)?.round(),
      );
    }

    final retryable = errorData['retryable'] == true ||
        code == 'NEW_TOPIC_SETTLEMENT_PENDING';
    throw NewTopicException(
      serverMessage ??
          (response.status >= 500
              ? 'AI 暫時生成失敗，請稍後再試；本次不會扣額度。'
              : '新話題生成失敗，請稍後再試。'),
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
