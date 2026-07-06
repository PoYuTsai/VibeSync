import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/coaching_outcome_event.dart';

/// Testable seam over the Edge Function invocation so tests can capture the
/// wire payload without touching Supabase.
typedef CoachingOutcomeUploadInvoker = Future<CoachingOutcomeUploadResponse>
    Function(
  String functionName, {
  required Map<String, dynamic> body,
});

/// Resolver for the current subscription tier string. Returns null when the
/// tier cannot be determined; uploads must never be blocked because of it.
typedef CoachingOutcomeTierResolver = String? Function();

class CoachingOutcomeUploadResponse {
  const CoachingOutcomeUploadResponse(this.status);

  final int status;
}

/// Best-effort, fire-and-forget de-identified upload of a local outcome event.
///
/// Hard rules (privacy + resilience):
/// - NEVER blocks UI, NEVER retries, NEVER rolls back local Hive state.
/// - Swallows every error (network / non-2xx / exception). NEVER throws.
/// - Whitelist-only payload: `outcomeTextPreview`, `userNote`, `partnerId`
///   and `conversationId` are privacy promises and MUST NOT leave the device.
class CoachingOutcomeUploader {
  CoachingOutcomeUploader({
    CoachingOutcomeUploadInvoker? invoker,
    CoachingOutcomeTierResolver? resolveUserTier,
  })  : _invoke = invoker ?? _defaultInvoker,
        _resolveUserTier = resolveUserTier;

  static const _functionName = 'submit-feedback';

  final CoachingOutcomeUploadInvoker _invoke;
  final CoachingOutcomeTierResolver? _resolveUserTier;

  Future<void> upload(CoachingOutcomeEvent event) async {
    try {
      String? userTier;
      try {
        userTier = _resolveUserTier?.call();
      } catch (_) {
        userTier = null;
      }
      final body = buildOutcomeUploadBody(event, userTier: userTier);
      final response = await _invoke(_functionName, body: body);
      final status = response.status;
      if (status < 200 || status >= 300) {
        debugPrint('[CoachingOutcomeUploader] non-2xx status: $status');
      }
    } catch (e) {
      // Best-effort: local Hive is the source of truth. Swallow everything.
      debugPrint('[CoachingOutcomeUploader] upload failed (ignored): $e');
    }
  }

  /// Builds the de-identified wire body. Only whitelist fields are emitted;
  /// optional string fields are omitted when null. Enums serialize via `.name`.
  @visibleForTesting
  static Map<String, dynamic> buildOutcomeUploadBody(
    CoachingOutcomeEvent event, {
    String? userTier,
  }) {
    final tier = userTier?.trim();
    return <String, dynamic>{
      'kind': 'outcome',
      'event': <String, dynamic>{
        'id': event.id,
        'source': event.source.name,
        if (event.adviceType != null) 'adviceType': event.adviceType,
        if (event.adviceId != null) 'adviceId': event.adviceId,
        'userAction': event.userAction.name,
        'outcome': event.outcome.name,
        'suggestedMoveSummary': event.suggestedMoveSummary,
        'createdAt': event.createdAt.toUtc().toIso8601String(),
        if (tier != null && tier.isNotEmpty) 'userTier': tier,
      },
    };
  }
}

Future<CoachingOutcomeUploadResponse> _defaultInvoker(
  String fn, {
  required Map<String, dynamic> body,
}) async {
  final res = await Supabase.instance.client.functions.invoke(fn, body: body);
  return CoachingOutcomeUploadResponse(res.status);
}
