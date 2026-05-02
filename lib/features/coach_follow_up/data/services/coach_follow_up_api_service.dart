// Spec 5 C19 — coach-follow-up Edge function HTTP client.
//
// Sole Flutter→Edge wire for the coach-follow-up generation endpoint. Owns:
//   • request body shape (mirrors supabase/functions/coach-follow-up/schemas.ts)
//   • status-code → exception mapping (400 / 429 / 5xx + 4xx-other)
//   • client-side defense-in-depth on the success-path card
//       — boundaryReminder must be non-null + non-empty (Codex P1 #3 contract)
//       — banned-token assertCardSafe mirror of validate.ts BANNED_TOKENS
//
// The `partnerHint` payload may ONLY come from buildCoachFollowUpPartnerHint
// (C17). This service does not rebuild it inline — privacy contract is held
// by the helper at the type boundary, never re-derived here.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/coach_follow_up_phase.dart';
import '../../domain/entities/coach_follow_up_result.dart';
import '../../domain/services/coach_follow_up_partner_hint_builder.dart';

// ── Public DTOs ───────────────────────────────────────────────────────────

/// Request answers — mirrors the Edge `RequestSchema.answers` shape exactly.
/// q1 always required; q2/q3 are phase-specific (e.g. preDateReminder uses q2,
/// postDateReflection allows free-text q3 capped at 80 chars).
class CoachFollowUpAnswers {
  final String q1;
  final String? q2;
  final String? q3;

  const CoachFollowUpAnswers({
    required this.q1,
    this.q2,
    this.q3,
  });
}

/// Testability seam: the production wire calls
/// `Supabase.instance.client.functions.invoke`, but tests inject a fake so they
/// can fabricate any (status, data) pair without touching real Supabase.
typedef CoachFollowUpInvoker = Future<CoachFollowUpInvokeResponse> Function(
  String functionName, {
  required Map<String, dynamic> body,
});

/// Minimal adapter over `FunctionResponse` — keeps tests from having to
/// construct a real `FunctionResponse` (which is supabase_flutter package type).
class CoachFollowUpInvokeResponse {
  final int status;
  final dynamic data;

  const CoachFollowUpInvokeResponse({
    required this.status,
    this.data,
  });
}

// ── Exceptions ────────────────────────────────────────────────────────────

/// 4xx that isn't 429 (validation, auth, payload). Caller surfaces as
/// "request rejected by API"; this is NOT a generation/AI failure.
class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, {this.status});
  @override
  String toString() => 'ApiException($status): $message';
}

/// 429 daily/monthly limit. `used` / `limit` propagate from the Edge response
/// so the UI can show "X / Y used" without a second round-trip.
class QuotaExceededException implements Exception {
  final String message;
  final int? used;
  final int? limit;
  QuotaExceededException(this.message, {this.used, this.limit});
  @override
  String toString() =>
      'QuotaExceededException: $message (used=$used, limit=$limit)';
}

/// 5xx OR success-path that fails the client-side card guard. From the user's
/// perspective: "AI didn't produce a usable card." Includes credit_deduct_failed
/// (the user wasn't actually charged AND didn't get a card → safe to retry).
class GenerationFailedException implements Exception {
  final String message;
  GenerationFailedException(this.message);
  @override
  String toString() => 'GenerationFailedException: $message';
}

// ── Banned-token guard (mirrors supabase/functions/coach-follow-up/validate.ts) ──
//
// Defense in depth — the Edge already runs assertCardSafe before responding,
// but a corrupted/replayed/cached response could still reach the client. We
// re-check here so a banned token never makes it into the Hive box or the UI.

const _bannedTokens = <String>[
  'PUA',
  '收割',
  '控住',
  '攻略',
  '壞女人',
  '高分妹',
  '玩咖',
];

const _visibleCardFields = <String>[
  'headline',
  'observation',
  'task',
  'suggestedLine',
  'boundaryReminder',
];

void _assertCardSafe(Map<String, dynamic> card) {
  for (final field in _visibleCardFields) {
    final value = card[field];
    if (value is! String) continue;
    for (final token in _bannedTokens) {
      if (value.contains(token)) {
        throw GenerationFailedException(
          'banned_token: $token found in $field',
        );
      }
    }
  }
}

// ── Service ───────────────────────────────────────────────────────────────

class CoachFollowUpApiService {
  final CoachFollowUpInvoker _invoke;

  CoachFollowUpApiService({CoachFollowUpInvoker? invoker})
      : _invoke = invoker ?? _defaultInvoker;

  Future<CoachFollowUpResult> generate({
    required String partnerId,
    required CoachFollowUpPhase phase,
    required CoachFollowUpAnswers answers,
    CoachFollowUpPartnerHint? partnerHint,
  }) async {
    final body = <String, dynamic>{
      'phase': phase.name,
      'answers': _answersToWire(answers),
      if (partnerHint != null) 'partnerHint': _hintToWire(partnerHint),
    };

    final response = await _invoke('coach-follow-up', body: body);

    switch (response.status) {
      case 200:
        return _parseSuccess(
          partnerId: partnerId,
          phase: phase,
          data: response.data,
        );
      case 429:
        final data = response.data;
        final asMap = data is Map ? data : const {};
        throw QuotaExceededException(
          asMap['error']?.toString() ?? 'quota_exceeded',
          used: asMap['used'] is int ? asMap['used'] as int : null,
          limit: asMap['limit'] is int ? asMap['limit'] as int : null,
        );
      default:
        if (response.status >= 500) {
          throw GenerationFailedException(_extractError(response.data));
        }
        // All other 4xx (400/401/403/413/...): "request rejected by API."
        throw ApiException(
          _extractError(response.data),
          status: response.status,
        );
    }
  }

  // ── wire helpers ────────────────────────────────────────────────────────

  Map<String, dynamic> _answersToWire(CoachFollowUpAnswers a) {
    return <String, dynamic>{
      'q1': a.q1,
      if (a.q2 != null) 'q2': a.q2,
      if (a.q3 != null) 'q3': a.q3,
    };
  }

  Map<String, dynamic> _hintToWire(CoachFollowUpPartnerHint h) {
    return <String, dynamic>{
      'name': h.name,
      if (h.heatScore != null) 'heatScore': h.heatScore,
      if (h.gameStage != null) 'gameStage': h.gameStage,
      if (h.lastConversationSummary != null)
        'lastConversationSummary': h.lastConversationSummary,
    };
  }

  CoachFollowUpResult _parseSuccess({
    required String partnerId,
    required CoachFollowUpPhase phase,
    required dynamic data,
  }) {
    if (data is! Map) {
      throw GenerationFailedException('malformed_response: not_a_map');
    }
    final card = data['card'];
    if (card is! Map) {
      throw GenerationFailedException('malformed_response: missing_card');
    }
    final cardMap = Map<String, dynamic>.from(card);

    final boundary = cardMap['boundaryReminder'];
    if (boundary is! String || boundary.isEmpty) {
      throw GenerationFailedException(
        'missing_boundary_reminder: required field is null/empty',
      );
    }

    _assertCardSafe(cardMap);

    final headline = cardMap['headline'];
    final observation = cardMap['observation'];
    final task = cardMap['task'];
    if (headline is! String ||
        observation is! String ||
        task is! String ||
        headline.isEmpty ||
        observation.isEmpty ||
        task.isEmpty) {
      throw GenerationFailedException('malformed_response: required_card_field_missing');
    }
    final suggestedLine = cardMap['suggestedLine'];
    final model = data['model'];
    final generatedAt = data['generatedAt'];
    if (model is! String) {
      throw GenerationFailedException('malformed_response: missing_model');
    }
    if (generatedAt is! String) {
      throw GenerationFailedException('malformed_response: missing_generatedAt');
    }
    final parsedAt = DateTime.tryParse(generatedAt);
    if (parsedAt == null) {
      throw GenerationFailedException('malformed_response: bad_generatedAt');
    }

    return CoachFollowUpResult(
      partnerId: partnerId,
      phase: phase.name,
      headline: headline,
      observation: observation,
      task: task,
      suggestedLine: suggestedLine is String ? suggestedLine : null,
      boundaryReminder: boundary,
      generatedAt: parsedAt,
      modelUsed: model,
    );
  }

  String _extractError(dynamic data) {
    if (data is Map && data['error'] != null) return data['error'].toString();
    return 'unknown_error';
  }
}

// Production default: thin wrapper around `Supabase.instance.client.functions
// .invoke`. Kept private so the test path always goes through the typedef.
Future<CoachFollowUpInvokeResponse> _defaultInvoker(
  String fn, {
  required Map<String, dynamic> body,
}) async {
  final res = await Supabase.instance.client.functions.invoke(fn, body: body);
  return CoachFollowUpInvokeResponse(status: res.status, data: res.data);
}
