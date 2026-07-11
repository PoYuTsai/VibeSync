enum PracticeHintReplyType { warmUp, steady }

/// The coaching decision behind a generated Hint.
///
/// This is deliberately structured so the later Debrief can evaluate the
/// same move instead of trying to infer a fresh strategy from the visible
/// sentence alone. All fields remain optional for rollout compatibility with
/// older Edge responses.
class PracticeHintDecision {
  final String? phase;
  final String? targetVariable;
  final String? move;
  final String? rationale;
  final String? inviteRoute;

  const PracticeHintDecision({
    this.phase,
    this.targetVariable,
    this.move,
    this.rationale,
    this.inviteRoute,
  });

  bool get isEmpty =>
      _isBlank(phase) &&
      _isBlank(targetVariable) &&
      _isBlank(move) &&
      _isBlank(rationale) &&
      _isBlank(inviteRoute);

  bool get isComplete =>
      !_isBlank(phase) &&
      !_isBlank(targetVariable) &&
      !_isBlank(move) &&
      !_isBlank(rationale) &&
      !_isBlank(inviteRoute);

  Map<String, dynamic> toJson() => {
        if (!_isBlank(phase)) 'phase': phase!.trim(),
        if (!_isBlank(targetVariable)) 'targetVariable': targetVariable!.trim(),
        if (!_isBlank(move)) 'move': move!.trim(),
        if (!_isBlank(rationale)) 'rationale': rationale!.trim(),
        if (!_isBlank(inviteRoute)) 'inviteRoute': inviteRoute!.trim(),
      };

  static PracticeHintDecision? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final decision = PracticeHintDecision(
      phase: _stringOrNull(raw['phase']),
      targetVariable: _stringOrNull(raw['targetVariable']),
      move: _stringOrNull(raw['move']),
      rationale: _stringOrNull(raw['rationale']),
      inviteRoute: _stringOrNull(raw['inviteRoute']),
    );
    return decision.isEmpty ? null : decision;
  }

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;

  static String? _stringOrNull(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class PracticeHintReply {
  final PracticeHintReplyType type;
  final String label;
  final String text;
  final String? hintRequestId;
  final PracticeHintDecision? decision;

  const PracticeHintReply({
    required this.type,
    required this.label,
    required this.text,
    this.hintRequestId,
    this.decision,
  });

  Map<String, dynamic> toJson() => {
        'type': switch (type) {
          PracticeHintReplyType.warmUp => 'warm_up',
          PracticeHintReplyType.steady => 'steady',
        },
        'label': label.trim(),
        'text': text.trim(),
        if (_nonEmptyString(hintRequestId) case final requestId?)
          'hintRequestId': requestId,
        if (decision != null && !decision!.isEmpty)
          'decision': decision!.toJson(),
      };

  static PracticeHintReply? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final type = switch (raw['type']) {
      'warm_up' => PracticeHintReplyType.warmUp,
      'steady' => PracticeHintReplyType.steady,
      _ => null,
    };
    final label = _nonEmptyString(raw['label']);
    final text = _nonEmptyString(raw['text']);
    if (type == null || label == null || text == null) return null;
    return PracticeHintReply(
      type: type,
      label: label,
      text: text,
      hintRequestId: _nonEmptyString(raw['hintRequestId']),
      decision: PracticeHintDecision.fromJson(raw['decision']),
    );
  }
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

  /// JSON representation for the encrypted local replay snapshot.
  ///
  /// Only an already validated successful result reaches this serializer.
  /// Persisting every reply's decision and request id keeps Hint -> Debrief
  /// lineage intact across provider/app rebuilds without a Hive migration.
  Map<String, dynamic> toJson() => {
        'replies':
            replies.map((reply) => reply.toJson()).toList(growable: false),
        'coaching': coaching.trim(),
        'costDeducted': costDeducted,
        'hintUsedCount': hintUsedCount,
        if (monthlyRemaining != null) 'monthlyRemaining': monthlyRemaining,
        if (dailyRemaining != null) 'dailyRemaining': dailyRemaining,
      };

  static PracticeHintResult? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final rawReplies = raw['replies'];
    final coaching = _nonEmptyString(raw['coaching']);
    final costDeducted = raw['costDeducted'];
    final hintUsedCount = raw['hintUsedCount'];
    if (rawReplies is! List ||
        rawReplies.length != 2 ||
        coaching == null ||
        costDeducted is! int ||
        costDeducted < 0 ||
        hintUsedCount is! int ||
        hintUsedCount < 0) {
      return null;
    }
    final replies = rawReplies
        .map(PracticeHintReply.fromJson)
        .whereType<PracticeHintReply>()
        .toList(growable: false);
    if (replies.length != rawReplies.length) return null;
    final monthlyRemaining = _nonNegativeIntOrNull(raw['monthlyRemaining']);
    final dailyRemaining = _nonNegativeIntOrNull(raw['dailyRemaining']);
    if ((raw.containsKey('monthlyRemaining') && monthlyRemaining == null) ||
        (raw.containsKey('dailyRemaining') && dailyRemaining == null)) {
      return null;
    }
    return PracticeHintResult(
      replies: replies,
      coaching: coaching,
      costDeducted: costDeducted,
      hintUsedCount: hintUsedCount,
      monthlyRemaining: monthlyRemaining,
      dailyRemaining: dailyRemaining,
    );
  }
}

String? _nonEmptyString(dynamic raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _nonNegativeIntOrNull(dynamic raw) {
  if (raw == null) return null;
  return raw is int && raw >= 0 ? raw : null;
}
