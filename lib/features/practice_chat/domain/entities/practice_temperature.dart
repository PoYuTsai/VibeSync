class PracticeTemperature {
  final int score;
  final int delta;
  final String band;
  final String reason;

  const PracticeTemperature({
    required this.score,
    required this.delta,
    required this.band,
    required this.reason,
  });

  bool get wentUp => delta > 0;
  bool get wentDown => delta < 0;
}
