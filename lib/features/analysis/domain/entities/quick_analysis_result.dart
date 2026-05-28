/// Result of the two-stage analyze `quick` phase.
///
/// Returned by `analyze-chat` when `responseMode: 'quick'`. Carries the
/// `analysisRunId` that the subsequent `full` call must echo so the server
/// can match the run, validate conversation hash, and avoid double-charging
/// quota (invariant I1 of `docs/plans/2026-05-28-two-stage-analyze.md`).
class QuickAnalysisResult {
  final String analysisRunId;
  final String nextStep;
  final String recommendedReply;
  final String shortReason;
  final bool insufficientContext;
  final String confidence;
  final int? estimatedFullSeconds;

  const QuickAnalysisResult({
    required this.analysisRunId,
    required this.nextStep,
    required this.recommendedReply,
    required this.shortReason,
    required this.insufficientContext,
    required this.confidence,
    this.estimatedFullSeconds,
  });

  factory QuickAnalysisResult.fromJson(Map<String, dynamic> json) {
    final quick = (json['quickResult'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final etaRaw = json['estimatedFullSeconds'];
    return QuickAnalysisResult(
      analysisRunId: (json['analysisRunId'] ?? '').toString(),
      nextStep: (quick['nextStep'] ?? '').toString(),
      recommendedReply: (quick['recommendedReply'] ?? '').toString(),
      shortReason: (quick['shortReason'] ?? '').toString(),
      insufficientContext: quick['insufficientContext'] == true,
      confidence: (quick['confidence'] ?? 'medium').toString(),
      estimatedFullSeconds: etaRaw is num ? etaRaw.round() : null,
    );
  }
}
