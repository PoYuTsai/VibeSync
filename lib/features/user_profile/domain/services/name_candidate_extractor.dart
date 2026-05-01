import '../../../conversation/domain/entities/message.dart';

/// Heuristic extractor that decides whether a free-form `Conversation.name`
/// looks like a person-name worth surfacing as the partner's display name,
/// or is a placeholder / date / sentence we should silently ignore.
///
/// Pure local Dart — no async, no Hive, no Riverpod. Same input → same output.
///
/// Spec 3 Task 14: Conversation.name placeholder filter only.
/// Spec 3 Task 15: `fromMessages()` — narrow regex fallback over 前 5 + 後 5
/// incoming messages. No full-text NER; only matches explicit self-intros
/// (`我叫 X` / `Hi I'm X` / `Call me X`).
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
  ///
  /// `和` excluded — common Japanese surname character (和田/和泉/和久).
  static final _cjkSentenceParticlePattern = RegExp(r'[跟與是在把對於從到]');

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
    // Must contain at least one letter (Latin) OR CJK ideograph — rejects
    // number-only, emoji-only, punctuation-only inputs that the earlier
    // filters miss.
    if (!RegExp(r'[A-Za-z一-鿿]').hasMatch(s)) return null;
    return s.toLowerCase();
  }

  /// Narrow self-introduction regex patterns. Order matters — match-first-wins.
  ///
  /// Each requires an explicit self-intro marker (我叫 / I'm / Call me) so the
  /// false-positive rate stays near zero. Speaking ABOUT a third person
  /// (`她是 May`, `我跟 May 聊天`) does NOT match because there is no marker.
  static final _selfIntroPatterns = <RegExp>[
    // Chinese: 我叫 X (CJK or Latin given/surname, 2-10 chars).
    RegExp(r'我叫\s*([一-龥A-Za-z]{2,10})'),
    // English: optional "Hi, " + I + (straight ' or curly ‘ ’) + m, then
    // 2-15 letters. caseSensitive false → matches "i'm" / "I'M" too.
    // ‘ = left single quotation mark ‘, ’ = right single quotation mark ’.
    RegExp(
      "(?:Hi,?\\s*)?I['‘’]?m\\s+([A-Za-z]{2,15})",
      caseSensitive: false,
    ),
    // English: "Call me X" (2-15 letters).
    RegExp(r'Call\s+me\s+([A-Za-z]{2,15})', caseSensitive: false),
  ];

  /// Returns a lowercase candidate name extracted from [messages] using narrow
  /// self-introduction regex over the first [n] + last [n] **incoming** msgs
  /// (outgoing/`isFromMe` messages are skipped — those are the user, not the
  /// partner). Returns `null` if no pattern matches.
  ///
  /// Sample window:
  /// - `incoming` = messages where `!isFromMe`, in original order.
  /// - If `incoming.length <= 2 * n` → use ALL incoming messages.
  /// - Otherwise → first `n` + last `n` (no overlap because length > 2n).
  ///
  /// This intentionally does NOT do full-text NER over middle-of-list
  /// messages: it would balloon false positives. Spec 3 Task 15.
  String? fromMessages(List<Message> messages, {int n = 5}) {
    final incoming = messages.where((m) => !m.isFromMe).toList();
    if (incoming.isEmpty) return null;

    final sample = incoming.length <= 2 * n
        ? incoming
        : <Message>[
            ...incoming.take(n),
            ...incoming.skip(incoming.length - n),
          ];

    for (final m in sample) {
      for (final p in _selfIntroPatterns) {
        final match = p.firstMatch(m.content);
        if (match != null) {
          // CJK has no case; .toLowerCase() is a no-op for CJK characters
          // and applies cleanly to Latin captures.
          return match.group(1)!.toLowerCase();
        }
      }
    }
    return null;
  }
}
