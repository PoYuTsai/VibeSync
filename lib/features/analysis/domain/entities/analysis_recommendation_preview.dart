/// Recommendation preview parsed from legacy quick/full or streaming analyze events.
///
/// Returned by `analyze-chat` as the legacy `quickResult` payload or synthesized from streaming recommendation events. Carries the
/// `analysisRunId` that the subsequent `full` call must echo so the server
/// can match the run, validate conversation hash, and avoid double-charging
/// quota in the legacy rollback lifecycle.
class AnalysisRecommendationPreview {
  final String analysisRunId;
  final String nextStep;
  final String pick;
  final String recommendedReply;
  final String shortReason;
  final bool insufficientContext;
  final String confidence;
  final int? estimatedFullSeconds;

  const AnalysisRecommendationPreview({
    required this.analysisRunId,
    required this.nextStep,
    required this.pick,
    required this.recommendedReply,
    required this.shortReason,
    required this.insufficientContext,
    required this.confidence,
    this.estimatedFullSeconds,
  });

  /// Throws [FormatException] when any of `analysisRunId`, `nextStep`, or
  /// `recommendedReply` is missing or empty after trim. Backend guardrails
  /// should make this unreachable, but fail-closed prevents two downstream
  /// hazards if a malformed 200 ever slips through:
  /// 1. The full-mode call would echo an empty `analysisRunId`, returning
  ///    `RUN_NOT_FOUND` after the user already paid recommendation quota.
  /// 2. The UI would render a blank recommendation preview.
  /// The service layer wraps this into `AnalysisException(code:
  /// 'INVALID_QUICK_RESPONSE')` so the notifier surfaces a coded error
  /// (invariant I-P3).
  factory AnalysisRecommendationPreview.fromJson(Map<String, dynamic> json) {
    final payload = (json['quickResult'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final etaRaw = json['estimatedFullSeconds'];

    final analysisRunId = (json['analysisRunId'] ?? '').toString().trim();
    final nextStep = (payload['nextStep'] ?? '').toString().trim();
    final pick =
        _normalizeRecommendationPick((payload['pick'] ?? '').toString().trim());
    final recommendedReply =
        (payload['recommendedReply'] ?? '').toString().trim();

    if (analysisRunId.isEmpty) {
      throw const FormatException(
        'AnalysisRecommendationPreview missing required field: analysisRunId',
      );
    }
    if (nextStep.isEmpty) {
      throw const FormatException(
        'AnalysisRecommendationPreview missing required field: nextStep',
      );
    }
    if (recommendedReply.isEmpty) {
      throw const FormatException(
        'AnalysisRecommendationPreview missing required field: recommendedReply',
      );
    }

    return AnalysisRecommendationPreview(
      analysisRunId: analysisRunId,
      nextStep: nextStep,
      pick: pick,
      recommendedReply: recommendedReply,
      shortReason: (payload['shortReason'] ?? '').toString(),
      insufficientContext: payload['insufficientContext'] == true,
      confidence: (payload['confidence'] ?? 'medium').toString(),
      estimatedFullSeconds: etaRaw is num ? etaRaw.round() : null,
    );
  }

  static String _normalizeRecommendationPick(String pick) {
    switch (pick) {
      case 'extend':
      case 'resonate':
      case 'tease':
      case 'humor':
      case 'coldRead':
        return pick;
      default:
        return '';
    }
  }
}
