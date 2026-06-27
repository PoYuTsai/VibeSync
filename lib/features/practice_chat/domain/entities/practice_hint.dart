enum PracticeHintReplyType { warmUp, steady }

class PracticeHintReply {
  final PracticeHintReplyType type;
  final String label;
  final String text;

  const PracticeHintReply({
    required this.type,
    required this.label,
    required this.text,
  });
}

class PracticeHintResult {
  final List<PracticeHintReply> replies;
  final String coaching;
  final int costDeducted;
  final int hintUsedCount;
  final int? monthlyRemaining;
  final int? dailyRemaining;

  const PracticeHintResult({
    required this.replies,
    required this.coaching,
    required this.costDeducted,
    required this.hintUsedCount,
    this.monthlyRemaining,
    this.dailyRemaining,
  });
}
