class PracticeTemperature {
  final int score;
  final int delta;
  final String band;
  final String reason;
  final int? familiarityScore;
  final int? familiarityDelta;
  final String? stageLabel;

  const PracticeTemperature({
    required this.score,
    required this.delta,
    required this.band,
    required this.reason,
    this.familiarityScore,
    this.familiarityDelta,
    this.stageLabel,
  });

  bool get wentUp => delta > 0;
  bool get wentDown => delta < 0;
}
