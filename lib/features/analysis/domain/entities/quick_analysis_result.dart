/// Result of the two-stage analyze `quick` phase.
///
/// Returned by `analyze-chat` when `responseMode: 'quick'`. Carries the
/// `analysisRunId` that the subsequent `full` call must echo so the server
/// can match the run, validate conversation hash, and avoid double-charging
/// quota (invariant I1 of `docs/plans/2026-05-28-two-stage-analyze.md`).
class QuickAnalysisResult {
  final String analysisRunId;
  final String nextStep;
  final String pick;
  final String recommendedReply;
  final String shortReason;
  final bool insufficientContext;
  final String confidence;
  final int? estimatedFullSeconds;

  const QuickAnalysisResult({
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
  ///    `RUN_NOT_FOUND` after the user already paid quick quota.
  /// 2. The UI would render a blank quick summary card.
  /// The service layer wraps this into `AnalysisException(code:
  /// 'INVALID_QUICK_RESPONSE')` so the notifier surfaces a coded error
  /// (invariant I-P3).
  factory QuickAnalysisResult.fromJson(Map<String, dynamic> json) {
    final quick = (json['quickResult'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final etaRaw = json['estimatedFullSeconds'];

    final analysisRunId = (json['analysisRunId'] ?? '').toString().trim();
    final nextStep = (quick['nextStep'] ?? '').toString().trim();
    final pick = _normalizeQuickPick((quick['pick'] ?? '').toString().trim());
    final recommendedReply = (quick['recommendedReply'] ?? '').toString().trim();

    if (analysisRunId.isEmpty) {
      throw const FormatException(
        'QuickAnalysisResult missing required field: analysisRunId',
      );
    }
    if (nextStep.isEmpty) {
      throw const FormatException(
        'QuickAnalysisResult missing required field: nextStep',
      );
    }
    if (recommendedReply.isEmpty) {
      throw const FormatException(
        'QuickAnalysisResult missing required field: recommendedReply',
      );
    }

    return QuickAnalysisResult(
      analysisRunId: analysisRunId,
      nextStep: nextStep,
      pick: pick,
      recommendedReply: recommendedReply,
      shortReason: (quick['shortReason'] ?? '').toString(),
      insufficientContext: quick['insufficientContext'] == true,
      confidence: (quick['confidence'] ?? 'medium').toString(),
      estimatedFullSeconds: etaRaw is num ? etaRaw.round() : null,
    );
  }

  static String _normalizeQuickPick(String pick) {
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
