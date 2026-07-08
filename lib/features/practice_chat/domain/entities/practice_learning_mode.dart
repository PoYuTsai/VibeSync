enum PracticeLearningMode {
  standard,
  beginner,
  game;

  String get wireName => switch (this) {
        PracticeLearningMode.standard => 'standard',
        PracticeLearningMode.beginner => 'beginner',
        PracticeLearningMode.game => 'game',
      };

  String get label => switch (this) {
        PracticeLearningMode.standard => '標準',
        PracticeLearningMode.beginner => '新手',
        PracticeLearningMode.game => 'Game',
      };

  bool get usesAssistedLearning => switch (this) {
        PracticeLearningMode.standard => false,
        PracticeLearningMode.beginner || PracticeLearningMode.game => true,
      };

  static PracticeLearningMode fromWire(String? value) {
    return switch (value) {
      'beginner' => PracticeLearningMode.beginner,
      'game' => PracticeLearningMode.game,
      _ => PracticeLearningMode.standard,
    };
  }
}
