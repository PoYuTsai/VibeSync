/// First useful recommendation emitted by the AnalyzeChat stream.
///
/// Carries the durable [analysisRunId] used to resume the same paid stream
/// without starting another run or charging quota again.
class AnalysisRecommendationPreview {
  final String analysisRunId;
  final String nextStep;
  final String pick;
  final String recommendedReply;
  final String shortReason;
  final bool insufficientContext;
  final String confidence;
  final int? estimatedReportSeconds;

  const AnalysisRecommendationPreview({
    required this.analysisRunId,
    required this.nextStep,
    required this.pick,
    required this.recommendedReply,
    required this.shortReason,
    required this.insufficientContext,
    required this.confidence,
    this.estimatedReportSeconds,
  });
}
