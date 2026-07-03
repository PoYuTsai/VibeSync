import '../entities/effective_style.dart';
import '../entities/partner_style_override.dart';
import '../entities/user_profile.dart';
import 'resolve_effective_style.dart';

/// Spec 2.5 — converts About Me + per-partner style settings into compact AI
/// context. This is the only contract layer that should translate profile
/// settings into prompt text.
class EffectiveStylePromptBuilder {
  static const int analysisMaxChars = 900;
  static const int coachFollowUpMaxChars = 500;

  /// Under the server-side effectiveStyleContext cap (1200) with headroom.
  static const int openerMaxChars = 900;

  const EffectiveStylePromptBuilder();

  /// Full context for analyze-chat / my_message / userDraft optimize.
  ///
  /// [includePartnerOverride] must be false when Spec 3 flags the partner card:
  /// global About Me may still apply, but partner-specific memory is untrusted.
  String? buildForAnalysis({
    required UserProfile? global,
    required PartnerStyleOverride? partner,
    required bool includePartnerOverride,
  }) {
    final effective = resolveEffectiveStyle(
      global: global,
      partner: includePartnerOverride ? partner : null,
    );
    final lines = <String>[];

    final voiceLine = _voiceLine(effective);
    if (voiceLine != null) lines.add(voiceLine);

    if (effective.practiceGoals.isNotEmpty) {
      lines.add(
        '- Practice focus: ${effective.practiceGoals.map(_goalLabel).join('、')}；'
        '${effective.practiceGoals.map(_goalPrompt).join(' ')}',
      );
    }

    final topics = <String>[
      if (global != null) ...global.topicSeeds.map(_topicLabel),
      if (global?.customTopics?.trim().isNotEmpty ?? false)
        global!.customTopics!.trim(),
    ];
    if (topics.isNotEmpty) {
      lines.add(
        '- Topic seeds: ${topics.join('、')}；只在自然時作為延伸素材，不要硬塞。',
      );
    }

    final notes = effective.notes?.trim();
    if (notes != null && notes.isNotEmpty) {
      lines.add('- Notes: $notes');
    }

    if (lines.isEmpty) return null;
    lines.add(
      '- Contract: 這些設定只調整語氣、練習方向和跟進建議；不要替用戶假裝成另一個人。'
      '當前對話、同意與安全、1.8x 黃金法則優先。',
    );
    return _truncate(lines.join('\n'), analysisMaxChars);
  }

  /// Opener (F3-1) slice. Same ingredients as analysis, but the topic-seed
  /// and contract wording guard the opener-specific failure mode: the model
  /// treating the *user's own* interests as the target's, fabricating common
  /// ground the target never showed.
  String? buildForOpener({
    required UserProfile? global,
    required PartnerStyleOverride? partner,
    required bool includePartnerOverride,
  }) {
    final effective = resolveEffectiveStyle(
      global: global,
      partner: includePartnerOverride ? partner : null,
    );
    final lines = <String>[];

    final voiceLine = _voiceLine(effective);
    if (voiceLine != null) lines.add(voiceLine);

    if (effective.practiceGoals.isNotEmpty) {
      lines.add(
        '- Practice focus: ${effective.practiceGoals.map(_goalLabel).join('、')}；'
        '${effective.practiceGoals.map(_goalPrompt).join(' ')}',
      );
    }

    final topics = <String>[
      if (global != null) ...global.topicSeeds.map(_topicLabel),
      if (global?.customTopics?.trim().isNotEmpty ?? false)
        global!.customTopics!.trim(),
    ];
    if (topics.isNotEmpty) {
      lines.add(
        '- Topic seeds: ${topics.join('、')}；這是用戶自己的興趣，'
        '只有與對方可見線索有真實交集時才拿來當開場素材，絕不假造共同點。',
      );
    }

    final notes = effective.notes?.trim();
    if (notes != null && notes.isNotEmpty) {
      lines.add('- Notes: $notes');
    }

    if (lines.isEmpty) return null;
    lines.add(
      '- Contract: 這些是用戶自己的風格設定，只用來調整開場白語氣與風格；'
      '不要替用戶假裝成另一個人。對方可見線索、明確禁忌與安全分寸永遠優先。',
    );
    return _truncate(lines.join('\n'), openerMaxChars);
  }

  /// Lightweight slice for Spec 5 coach-follow-up.
  ///
  /// Deliberately excludes notes/topics so the follow-up coach stays focused on
  /// interaction tone + practice goal, not broad long-term memory.
  String? buildForCoachFollowUp({
    required UserProfile? global,
    required PartnerStyleOverride? partner,
    required bool includePartnerOverride,
  }) {
    final effective = resolveEffectiveStyle(
      global: global,
      partner: includePartnerOverride ? partner : null,
    );
    final lines = <String>[];

    final voiceLine = _voiceLine(effective);
    if (voiceLine != null) lines.add(voiceLine);

    if (effective.practiceGoals.isNotEmpty) {
      lines.add(
        '- Practice focus: ${effective.practiceGoals.map(_goalLabel).join('、')}；'
        '${effective.practiceGoals.map(_goalPrompt).join(' ')}',
      );
    }

    if (lines.isEmpty) return null;
    lines.add(
      '- Contract: 僅用來調整教練語氣與任務 framing；不要拿來推斷對方或寫長期人格。',
    );
    return _truncate(lines.join('\n'), coachFollowUpMaxChars);
  }

  /// Voice line for the (主, 副) style pair.
  ///
  /// 主-only output is **byte-for-byte identical** to the pre-pair format —
  /// that is the regression guarantee for every existing user (snapshot
  /// tested). 主+副 leads with the pair framing, then full 主 prompt, then
  /// the deliberately down-weighted 副 prompt so the LLM doesn't average the
  /// two styles into mush.
  static String? _voiceLine(EffectiveStyle effective) {
    final style = effective.interactionStyle;
    if (style == null) return null;
    final secondary = effective.secondaryStyle;
    if (secondary == null) {
      return '- Preferred voice: ${_styleLabel(style)}；${_stylePrompt(style)}';
    }
    return '- Preferred voice: 以${_styleLabel(style)}為主、'
        '${_styleLabel(secondary)}為輔；${_stylePrompt(style)}。'
        '${_secondaryStylePrompt(secondary)}';
  }

  static String _styleLabel(InteractionStyle style) {
    switch (style) {
      case InteractionStyle.steady:
        return '穩重';
      case InteractionStyle.direct:
        return '直接';
      case InteractionStyle.humorous:
        return '幽默';
      case InteractionStyle.gentle:
        return '溫柔';
      case InteractionStyle.playful:
        return '有玩心';
    }
  }

  static String _stylePrompt(InteractionStyle style) {
    switch (style) {
      case InteractionStyle.steady:
        return '回覆乾淨穩定，不急著推進，也不要過度解釋';
      case InteractionStyle.direct:
        return '可以更清楚表達意圖，適合給明確但低壓的邀約方向';
      case InteractionStyle.humorous:
        return '回覆要輕鬆、有畫面感，可以自然幽默但不要硬講笑話';
      case InteractionStyle.gentle:
        return '語氣低壓溫和，先安住情緒，不催促、不追問';
      case InteractionStyle.playful:
        return '可以保留曖昧張力與玩心，但尊重對方反應和邊界';
    }
  }

  /// Down-weighted 副風格 prompt — 點綴 wording on purpose, never reusing the
  /// full-strength [_stylePrompt], so the 副 colors the voice without the LLM
  /// averaging it against the 主基調.
  static String _secondaryStylePrompt(InteractionStyle style) {
    switch (style) {
      case InteractionStyle.steady:
        return '偶爾點綴一點穩定的底氣讓回覆收得住，不要蓋過主基調';
      case InteractionStyle.direct:
        return '偶爾點綴一句更清楚的意圖表達，不要蓋過主基調';
      case InteractionStyle.humorous:
        return '偶爾點綴一點輕鬆幽默調味，不要蓋過主基調';
      case InteractionStyle.gentle:
        return '在情緒處點綴一點溫柔緩衝，不要蓋過主基調';
      case InteractionStyle.playful:
        return '偶爾點綴一點玩心與曖昧張力，不要蓋過主基調';
    }
  }

  static String _goalLabel(PracticeGoal goal) {
    switch (goal) {
      case PracticeGoal.softInvite:
        return '模糊邀約';
      case PracticeGoal.reduceAnxiety:
        return '降低焦慮';
      case PracticeGoal.humorousReply:
        return '幽默回應';
      case PracticeGoal.buildCloseness:
        return '建立連結';
      case PracticeGoal.explainLess:
        return '減少解釋';
    }
  }

  static String _goalPrompt(PracticeGoal goal) {
    switch (goal) {
      case PracticeGoal.softInvite:
        return '更早給清楚但低壓的邀約方向。';
      case PracticeGoal.reduceAnxiety:
        return '避免連續確認、追問或把對方反應綁到自我價值。';
      case PracticeGoal.humorousReply:
        return '優先給自然、短、好接的幽默。';
      case PracticeGoal.buildCloseness:
        return '多用情緒與小故事建立連結，不只交換資訊。';
      case PracticeGoal.explainLess:
        return '回覆更短、更有留白，避免長篇說明。';
    }
  }

  static String _topicLabel(TopicSeed seed) {
    switch (seed) {
      case TopicSeed.fitness:
        return '健身';
      case TopicSeed.travel:
        return '旅行';
      case TopicSeed.coffee:
        return '咖啡';
      case TopicSeed.music:
        return '音樂';
      case TopicSeed.movies:
        return '電影';
      case TopicSeed.photography:
        return '攝影';
      case TopicSeed.food:
        return '美食';
      case TopicSeed.pets:
        return '寵物';
      case TopicSeed.reading:
        return '閱讀';
      case TopicSeed.workLife:
        return '工作生活';
    }
  }

  static String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars - 1).trimRight()}…';
  }
}
