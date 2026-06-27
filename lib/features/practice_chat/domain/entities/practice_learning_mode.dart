enum PracticeLearningMode {
  standard,
  beginner;

  String get wireName => switch (this) {
        PracticeLearningMode.standard => 'standard',
        PracticeLearningMode.beginner => 'beginner',
      };

  String get label => switch (this) {
        PracticeLearningMode.standard => '練習',
        PracticeLearningMode.beginner => '新手',
      };

  static PracticeLearningMode fromWire(String? value) {
    return value == 'beginner'
        ? PracticeLearningMode.beginner
        : PracticeLearningMode.standard;
  }
}
