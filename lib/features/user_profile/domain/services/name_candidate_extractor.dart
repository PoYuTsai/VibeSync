/// Heuristic extractor that decides whether a free-form `Conversation.name`
/// looks like a person-name worth surfacing as the partner's display name,
/// or is a placeholder / date / sentence we should silently ignore.
///
/// Pure local Dart — no async, no Hive, no Riverpod. Same input → same output.
///
/// Spec 3 Task 14: Conversation.name placeholder filter only.
/// Task 15 will add `fromMessages()` (regex over incoming messages) and
/// Task 16 wires both into `dataQualityFlagProvider`.
class NameCandidateExtractor {
  /// Exact-match placeholders the app (or a defensive UI default) uses when no
  /// real partner name is known. Treat as "user has not named the conversation".
  static const _placeholders = {'新對話', '新的對話', '互動紀錄'};

  /// Auto-segmented conversation titles like `第 1 段`, `第3段`.
  static final _segmentPattern = RegExp(r'^第\s*\d+\s*段$');

  /// Pure date-like titles: `2026/05/01`, `2026-05-01`, `5月1日`.
  static final _datePattern = RegExp(
    r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}$|^\d{1,2}月\d{1,2}日$',
  );

  /// Anything longer than this is almost certainly a sentence, not a name.
  static const _maxNameLen = 20;

  /// Common Chinese sentence particles. If a candidate string contains any of
  /// these characters, it is almost certainly a sentence ("我**跟**她聊天",
  /// "她**是**朋友") rather than a person name. Real Chinese given/surnames
  /// extremely rarely contain these characters, so the false-positive risk is
  /// low and the heuristic catches short-CJK sentences that slip past
  /// [_maxNameLen]. See plan Task 14 (Option A) for rationale.
  static final _cjkSentenceParticlePattern = RegExp(
    r'[跟和與是在把對於從到]',
  );

  /// Returns the canonical lowercase name for [raw], or `null` if [raw] looks
  /// like a placeholder, segment marker, date, or sentence rather than a
  /// person name.
  String? fromConversationName(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (_placeholders.contains(s)) return null;
    if (_segmentPattern.hasMatch(s)) return null;
    if (_datePattern.hasMatch(s)) return null;
    if (s.length > _maxNameLen) return null;
    if (_cjkSentenceParticlePattern.hasMatch(s)) return null;
    return s.toLowerCase();
  }
}
