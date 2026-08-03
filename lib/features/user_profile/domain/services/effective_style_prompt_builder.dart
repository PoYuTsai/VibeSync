import '../entities/effective_style.dart';
import '../entities/partner_style_override.dart';
import '../entities/user_profile.dart';
import 'resolve_effective_style.dart';

/// Spec 2.5 — converts About Me + per-partner style settings into compact AI
/// context. This is the only contract layer that should translate profile
/// settings into prompt text.
class EffectiveStylePromptBuilder {
  static const int analysisMaxChars = 900;
  static const int coachFollowUpMaxChars = 900;

  /// Under the server-side effectiveStyleContext cap (1200) with headroom.
  static const int openerMaxChars = 900;

  /// New Topic（破冰腦力）slice；同 server cap 1200 之下留 headroom。
  static const int newTopicMaxChars = 900;

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

  /// New Topic（破冰腦力）slice。與 opener 同素材，但 topic-seed 與
  /// contract 針對新話題的失敗模式收緊：使用者興趣只能作自然的自我揭露
  /// （分享自身生活畫面），絕不能被寫成對方也喜歡；也不得為了配合對方
  /// 假裝身份、經歷或興趣。visible 文字統一用「自然展現生活感、品味或
  /// 行動力」表述，不用內部技巧術語。
  String? buildForNewTopic({
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
        '可以自然分享自身生活畫面、自然展現生活感、品味或行動力，'
        '但不得聲稱對方也喜歡，也不得假造共同點。',
      );
    }

    final notes = effective.notes?.trim();
    if (notes != null && notes.isNotEmpty) {
      lines.add('- Notes: $notes');
    }

    if (lines.isEmpty) return null;
    lines.add(
      '- Contract: 這些是用戶自己的風格設定，只調整話題的說法與語氣；'
      '不得為了配合對方假裝身份、經歷或興趣。'
      '對方明確紀錄、同意與低壓互動要求永遠優先。',
    );
    return _truncate(lines.join('\n'), newTopicMaxChars);
  }

  /// Lightweight slice for Spec 5 coach-follow-up.
  ///
  /// 2026-08 關於我重新定位案 批3：補讀 stuckPoints（現在卡住的處境）與
  /// notes（使用者邊界）——先前故意不讀是為了避免長期人格推斷，這次拍板
  /// 補上是因為處境與邊界屬於「現在」而非長期人格。Topics 仍不進來，
  /// 因為那是話題素材不是語氣/處境設定。
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

    final comfortLine = _comfortZoneLine(effective);
    if (comfortLine != null) {
      lines.add(comfortLine);
      lines.add(_singleCardStretchInstruction);
    }

    if (effective.stuckPoints.isNotEmpty) {
      lines.add(
        '- Stuck points: ${effective.stuckPoints.map(_stuckPointLabel).join('、')}；'
        '這是使用者現在卡住的處境，回答時要接住這個情境，不要給通用建議。',
      );
    }

    if (effective.practiceGoals.isNotEmpty) {
      lines.add(
        '- Practice focus: ${effective.practiceGoals.map(_goalLabel).join('、')}；'
        '${effective.practiceGoals.map(_goalPrompt).join(' ')}',
      );
    }

    final notes = effective.notes?.trim();
    if (notes != null && notes.isNotEmpty) {
      lines.add('- Boundary: $notes；這是使用者的邊界，任何建議都不能違反。');
    }

    if (lines.isEmpty) return null;
    lines.add(
      '- Contract: 僅用來調整教練語氣與任務 framing；不要拿來推斷對方或寫長期人格。',
    );
    return _truncate(lines.join('\n'), coachFollowUpMaxChars);
  }

  /// Comfort-zone description for the (主, 副) style pair.
  ///
  /// 2026-08 關於我重新定位案 批3：指令風格從「模仿模板」反轉成「舒適區標尺」——
  /// 這是使用者現在寫得出來的範圍，不是要 AI 收斂成那個樣子。這一版**刻意**
  /// 打破舊版「主-only byte-for-byte identical to pre-pair format」鎖，
  /// 見批3設計文件。只描述舒適區，不含 stretch 指令——後者依 caller 是
  /// 「五選一回覆」還是「單張建議卡」而不同，見 [_voiceLine]／
  /// [_singleCardStretchInstruction]。
  static String? _comfortZoneLine(EffectiveStyle effective) {
    final style = effective.interactionStyle;
    if (style == null) return null;
    final secondary = effective.secondaryStyle;
    final comfortDesc = secondary == null
        ? _styleLabel(style)
        : '以${_styleLabel(style)}為主、${_styleLabel(secondary)}為輔';
    return '- 使用者目前的舒適區：$comfortDesc。這不是你要模仿的模板，'
        '是他現在寫得出來的範圍。';
  }

  /// [buildForAnalysis]／[buildForOpener]／[buildForNewTopic] 專用：這三個
  /// slice 都輸出五種平行風格，stretch 指令要求至少一種明顯超出舒適區。
  static const String _fiveStyleStretchInstruction =
      '- 五種回覆風格請照常全力發揮，不要因為舒適區而收斂任何一種；'
      '至少一種要明顯超出他的舒適區。';

  /// [buildForCoachFollowUp] 專用：Coach 1:1 只產一張結構化建議卡，沒有
  /// 「五種風格」這回事——套用 [_fiveStyleStretchInstruction] 會是指著不存在
  /// 的輸出格式下指令。這張卡本身可以超出舒適區，但不需要五選一的收斂提醒。
  static const String _singleCardStretchInstruction =
      '- 這張建議可以明顯超出他的舒適區，不需要收斂成他習慣的樣子。';

  static String? _voiceLine(EffectiveStyle effective) {
    final comfortLine = _comfortZoneLine(effective);
    if (comfortLine == null) return null;
    return '$comfortLine\n$_fiveStyleStretchInstruction';
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

  static String _stuckPointLabel(StuckPoint s) => switch (s) {
        StuckPoint.fadesOut => '話題卡住接不下去',
        StuckPoint.dontKnowHowToAsk => '不知道怎麼開口約',
        StuckPoint.anxiousWontSend => '緊張不敢傳',
        StuckPoint.overExplains => '容易解釋太多',
        StuckPoint.leftOnRead => '已讀不回',
      };

  static String _goalLabel(PracticeGoal goal) {
    switch (goal) {
      case PracticeGoal.softInvite:
        return '想約得出來';
      case PracticeGoal.comfortableChat:
        return '想先能自在聊天';
      case PracticeGoal.humorousReply:
        return '想讓對話更幽默、有來有往';
      case PracticeGoal.buildCloseness:
        return '想培養穩定的親近感';
      case PracticeGoal.findCompatiblePartner:
        return '想找到聊得來的對象';
    }
  }

  static String _goalPrompt(PracticeGoal goal) {
    switch (goal) {
      case PracticeGoal.softInvite:
        return '更早給清楚但低壓的邀約方向。';
      case PracticeGoal.comfortableChat:
        return '避免連續確認、追問或把對方反應綁到自我價值。';
      case PracticeGoal.humorousReply:
        return '優先給自然、短、好接的幽默。';
      case PracticeGoal.buildCloseness:
        return '多用情緒與小故事建立連結，不只交換資訊。';
      case PracticeGoal.findCompatiblePartner:
        return '保持開放、不預設對方要符合單一條件；重點是找到聊得來的感覺，不要急著篩選或設限。';
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
