/// 新片段要帶的上一輪脈絡（previousRound，Eric 2026-10-18）：伺服器
/// `guide_v3/previous_round.ts` 的 App 端鏡像。分析完的片段會封存，她回了只能另開
/// 新片段，模型原本看不到上一輪；這份帶上次的判讀、他複製的那張卡、上一段最後
/// 幾則。伺服器開關 ANALYZE_GUIDE_V3_PREV_ROUND 沒開時整份不用；不算計費字數。
library;

/// 上一段的一則訊息（只有誰說的與文字）。
class PreviousRoundMessage {
  const PreviousRoundMessage({required this.isFromMe, required this.content});

  final bool isFromMe;
  final String content;

  Map<String, dynamic> toJson() => {'isFromMe': isFromMe, 'content': content};

  @override
  bool operator ==(Object other) =>
      other is PreviousRoundMessage &&
      other.isFromMe == isFromMe &&
      other.content == content;

  @override
  int get hashCode => Object.hash(isFromMe, content);
}

class PreviousRoundContext {
  const PreviousRoundContext({
    required this.decision,
    this.light,
    this.judgment,
    this.sentCard,
    this.messages = const [],
  });

  /// 上次的決定（wire 字串；自傷關心不帶）。
  final String decision;

  /// 上次的燈號（wire 字串）；讀不懂就沒有。
  final String? light;

  /// 上次給他看的判讀。
  final String? judgment;

  /// 他上次複製的那張卡（好幾則用換行接起來）。
  final String? sentCard;

  /// 上一段最後幾則，舊到新。
  final List<PreviousRoundMessage> messages;

  /// 全部文字的長度（伺服器的 600 字上限照這個算）。
  int get charCount =>
      (judgment?.length ?? 0) +
      (sentCard?.length ?? 0) +
      messages.fold<int>(0, (total, m) => total + m.content.length);

  Map<String, dynamic> toJson() => {
        'decision': decision,
        if (light != null) 'light': light,
        if (judgment != null) 'judgment': judgment,
        if (sentCard != null) 'sentCard': sentCard,
        'messages': messages.map((m) => m.toJson()).toList(growable: false),
      };
}
