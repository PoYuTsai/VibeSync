import 'package:characters/characters.dart';

import '../../../../core/constants/app_constants.dart';
import '../entities/analysis_models.dart';
import '../entities/game_stage.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../user_profile/domain/entities/user_profile.dart';
import 'coach_action_card_data.dart';
import 'coach_action_type.dart';
import 'learning_link_resolver.dart';

/// Deterministic policy that picks one CoachAction per analysis result.
class CoachActionPolicy {
  const CoachActionPolicy._();

  static const int _briefNameAnswerMaxLength = 12;
  static const int _briefNameFollowUpGraceLength = 36;

  static const List<String> _meetingKeywords = [
    '見面',
    '邀約',
    '約她',
    '約他',
    '約出來',
    '約出門',
    '約會',
    '吃飯',
    '喝咖啡',
    '看電影',
    '一起去',
    '碰面',
    '見個面',
  ];

  static bool _payloadSuggestsMeeting(String text) =>
      _meetingKeywords.any(text.contains);

  static const List<String> _emotionSignalKeywords = [
    '不安',
    '焦慮',
    '緊張',
    '擔心',
    '壓力',
    '委屈',
    '失落',
    '難過',
    '受傷',
    '害怕',
    '脆弱',
    '生氣',
    '不舒服',
    '被忽略',
    '需要被理解',
    '想被理解',
    '需要被看見',
    '想被看見',
    '安全感',
    '安撫',
    '修復',
    '道歉',
    '前任',
    '邊界',
    '吃醋',
    '嫉妒',
    '暈船',
  ];

  static bool _hasEmotionSignal(PsychologyAnalysis? psychology) {
    final subtext = psychology?.subtext.trim() ?? '';
    if (subtext.isEmpty) return false;
    return _emotionSignalKeywords.any(subtext.contains);
  }

  static bool _hasMeetingGameplaySignal(
    GameStageInfo gameStage,
    FinalRecommendation finalRecommendation,
  ) {
    return gameStage.current == GameStage.close ||
        gameStage.status == GameStageStatus.canAdvance ||
        _payloadSuggestsMeeting(gameStage.nextStep) ||
        _payloadSuggestsMeeting(finalRecommendation.content) ||
        _payloadSuggestsMeeting(finalRecommendation.reason);
  }

  static bool _userOverextendedReply(List<Message> messages) {
    if (messages.length < 2) return false;
    Message? latestUserReply;
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.isFromMe) {
        latestUserReply ??= message;
        continue;
      }

      if (latestUserReply == null) {
        return false;
      }

      final partnerText = message.content.trim();
      final partnerLength = partnerText.characters.length;
      if (partnerLength == 0) return false;
      final userLength = latestUserReply.content.trim().characters.length;
      if (_isBriefNameAnswerTurn(
        messages: messages,
        partnerIndex: i,
        partnerLength: partnerLength,
        userLength: userLength,
      )) {
        return false;
      }

      return userLength > partnerLength * AppConstants.goldenRuleMultiplier;
    }
    return false;
  }

  static bool _isBriefNameAnswerTurn({
    required List<Message> messages,
    required int partnerIndex,
    required int partnerLength,
    required int userLength,
  }) {
    if (partnerLength > _briefNameAnswerMaxLength ||
        userLength > _briefNameFollowUpGraceLength ||
        partnerIndex <= 0) {
      return false;
    }

    for (var i = partnerIndex - 1; i >= 0; i--) {
      final previous = messages[i];
      final text = previous.content.trim();
      if (text.isEmpty) continue;

      if (!previous.isFromMe) return false;
      return _asksForName(text);
    }
    return false;
  }

  static bool _asksForName(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('’', "'")
        .replaceAll('？', '?');
    return normalized.contains('怎麼稱呼') ||
        normalized.contains('怎麼叫') ||
        normalized.contains('叫什麼') ||
        normalized.contains('叫甚麼') ||
        normalized.contains('名字') ||
        normalized.contains('貴姓') ||
        normalized.contains("what'syourname") ||
        normalized.contains('whatsyourname') ||
        normalized.contains('yourname');
  }

  static const Set<GameStage> _midGameStages = {
    GameStage.premise,
    GameStage.qualification,
    GameStage.narrative,
  };

  static const Map<String, CoachActionType> _hintActionTypeMap = {
    'softInvite': CoachActionType.softInvite,
    'lowerPressureReply': CoachActionType.lowerPressureReply,
    'extendTopicStoryFrame': CoachActionType.extendTopicStoryFrame,
    'emotionalResonance': CoachActionType.emotionalResonance,
    'rightSizeReply': CoachActionType.rightSizeReply,
    'playfulReply': CoachActionType.playfulReply,
    'pausePursuit': CoachActionType.pausePursuit,
    'preferenceSignal': CoachActionType.preferenceSignal,
    'fitCheck': CoachActionType.fitCheck,
  };

  static String _avoidLabelForActionType(CoachActionType actionType) {
    switch (actionType) {
      case CoachActionType.softInvite:
        return '邀約提醒';
      case CoachActionType.lowerPressureReply:
      case CoachActionType.pausePursuit:
        return '先不要';
      case CoachActionType.rightSizeReply:
        return '精簡提醒';
      case CoachActionType.emotionalResonance:
        return '回應提醒';
      case CoachActionType.playfulReply:
        return '尺度提醒';
      case CoachActionType.extendTopicStoryFrame:
      case CoachActionType.preferenceSignal:
      case CoachActionType.fitCheck:
        return '節奏提醒';
    }
  }

  static const List<String> _concreteTopicKeywords = [
    '追劇',
    '看劇',
    '影集',
    '電影',
    'Netflix',
    'netflix',
    'YouTube',
    'youtube',
    '動漫',
    '動畫',
    '漫畫',
    '小說',
    '音樂',
    '演唱會',
    '遊戲',
    '手遊',
    '健身',
    '運動',
    '爬山',
    '咖啡',
    '餐廳',
    '甜點',
    '酒吧',
    '旅行',
    '旅遊',
    '逛街',
    '展覽',
    '在家',
    '做飯',
    '煮飯',
    '寵物',
    '貓',
    '狗',
  ];

  static String _latestPartnerMessageContent(List<Message> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (!message.isFromMe) {
        return message.content.trim();
      }
    }
    return '';
  }

  static bool _hasConcreteTopicHook({
    required List<Message> messages,
    required GameStageInfo gameStage,
    required FinalRecommendation finalRecommendation,
  }) {
    final latestPartnerMessage = _latestPartnerMessageContent(messages);
    if (latestPartnerMessage.length < 4) return false;

    final haystack = [
      latestPartnerMessage,
      gameStage.nextStep,
      finalRecommendation.content,
      finalRecommendation.reason,
    ].join(' ');
    return _concreteTopicKeywords.any(haystack.contains);
  }

  static String _compactTopic(String raw) {
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 16) return normalized;
    return '${normalized.substring(0, 16)}...';
  }

  static CoachActionCardData evaluate({
    required int heatScore,
    required GameStageInfo gameStage,
    required FinalRecommendation finalRecommendation,
    required List<Message> messages,
    required List<PracticeGoal> practiceGoals,
    required bool isDataQualityFlagged,
    CoachActionHint? coachActionHint,
    PsychologyAnalysis? psychology,
  }) {
    final card = _select(
      heatScore: heatScore,
      gameStage: gameStage,
      finalRecommendation: finalRecommendation,
      messages: messages,
      practiceGoals: practiceGoals,
      isDataQualityFlagged: isDataQualityFlagged,
      coachActionHint: coachActionHint,
      psychology: psychology,
    );
    return _filterSuggestedLine(card, heatScore);
  }

  static CoachActionCardData _select({
    required int heatScore,
    required GameStageInfo gameStage,
    required FinalRecommendation finalRecommendation,
    required List<Message> messages,
    required List<PracticeGoal> practiceGoals,
    required bool isDataQualityFlagged,
    CoachActionHint? coachActionHint,
    PsychologyAnalysis? psychology,
  }) {
    if (isDataQualityFlagged) {
      return _selectFlaggedSafeSet(
        heatScore: heatScore,
        finalRecommendation: finalRecommendation,
        messages: messages,
        psychology: psychology,
      );
    }
    if (heatScore > AppConstants.hotMax &&
        _hasMeetingGameplaySignal(gameStage, finalRecommendation)) {
      return _buildSoftInvite(
        heatScore: heatScore,
        finalRecommendation: finalRecommendation,
      );
    }
    if (heatScore <= AppConstants.coldMax) {
      if (_payloadSuggestsMeeting(gameStage.nextStep)) {
        return _buildPausePursuit(heatScore: heatScore);
      }
      // tie-breaker: reduceAnxiety practice goal → keep on pausePursuit even
      // without a meeting-keyword nextStep, since the user already opted in
      // to "step back from pressure".
      if (practiceGoals.contains(PracticeGoal.reduceAnxiety)) {
        return _buildPausePursuit(heatScore: heatScore);
      }
      return _buildLowerPressureReply(
        heatScore: heatScore,
        finalRecommendation: finalRecommendation,
        flaggedPath: false,
      );
    }
    if (_userOverextendedReply(messages)) {
      return _buildRightSizeReply(
        heatScore: heatScore,
        finalRecommendation: finalRecommendation,
      );
    }
    final challengeSignal = psychology?.shitTest != null;
    final emotionSignal = _hasEmotionSignal(psychology);
    if (challengeSignal || emotionSignal) {
      return _buildEmotionalResonance(
        heatScore: heatScore,
        finalRecommendation: finalRecommendation,
        challengeSignal: challengeSignal,
      );
    }
    final aiHintCard = _buildFromCoachActionHint(coachActionHint);
    if (aiHintCard != null) {
      return aiHintCard;
    }
    if (heatScore <= AppConstants.hotMax &&
        _hasConcreteTopicHook(
          messages: messages,
          gameStage: gameStage,
          finalRecommendation: finalRecommendation,
        )) {
      return _buildConcreteTopicExtension(
        heatScore: heatScore,
        latestPartnerMessage: _latestPartnerMessageContent(messages),
      );
    }
    if (heatScore <= AppConstants.hotMax &&
        _midGameStages.contains(gameStage.current)) {
      if (practiceGoals.contains(PracticeGoal.humorousReply)) {
        return _buildPlayfulReply(
          heatScore: heatScore,
          finalRecommendation: finalRecommendation,
        );
      }
      if (practiceGoals.contains(PracticeGoal.explainLess)) {
        return _buildPreferenceSignal(heatScore: heatScore);
      }
      return _buildExtendTopicStoryFrame(
        heatScore: heatScore,
        finalRecommendation: finalRecommendation,
      );
    }
    return _buildFitCheck(
      heatScore: heatScore,
      isDataQualityFlagged: isDataQualityFlagged,
    );
  }

  // Flagged partners are restricted to a safe set: no 邀約推進 / no 故事框架展開 /
  // no humour goal / no preferenceSignal — practiceGoals is ignored entirely.
  static CoachActionCardData _selectFlaggedSafeSet({
    required int heatScore,
    required FinalRecommendation finalRecommendation,
    required List<Message> messages,
    PsychologyAnalysis? psychology,
  }) {
    if (_userOverextendedReply(messages)) {
      return _buildRightSizeReply(
        heatScore: heatScore,
        finalRecommendation: finalRecommendation,
      );
    }
    final challengeSignal = psychology?.shitTest != null;
    final emotionSignal = _hasEmotionSignal(psychology);
    if (challengeSignal || emotionSignal) {
      return _buildEmotionalResonance(
        heatScore: heatScore,
        finalRecommendation: finalRecommendation,
        challengeSignal: challengeSignal,
      );
    }
    if (heatScore <= AppConstants.coldMax) {
      return _buildLowerPressureReply(
        heatScore: heatScore,
        finalRecommendation: finalRecommendation,
        flaggedPath: true,
      );
    }
    return _buildFitCheck(
      heatScore: heatScore,
      isDataQualityFlagged: true,
    );
  }

  // Below the veryHot floor, any candidate suggestedLine that smells like a
  // meeting nudge is dropped — defensive against upstream prompt drift.
  static CoachActionCardData _filterSuggestedLine(
    CoachActionCardData card,
    int heatScore,
  ) {
    final line = card.suggestedLine;
    if (line == null) return card;
    if (heatScore > AppConstants.hotMax) return card;
    if (!_payloadSuggestsMeeting(line)) return card;
    return CoachActionCardData(
      actionLabel: card.actionLabel,
      whyNow: card.whyNow,
      task: card.task,
      avoid: card.avoid,
      avoidLabel: card.avoidLabel,
      suggestedLine: null,
      learningLink: card.learningLink,
    );
  }

  static CoachActionCardData _buildSoftInvite({
    required int heatScore,
    required FinalRecommendation finalRecommendation,
  }) {
    final candidate = finalRecommendation.content.trim();
    return CoachActionCardData(
      actionLabel: '模糊邀約',
      whyNow: '對方這次的投入度 $heatScore，且有見面訊號，可以給具體選項',
      task: '拋一個低門檻邀約，給具體時間和場景',
      avoid: '別要對方立刻決定',
      avoidLabel: _avoidLabelForActionType(CoachActionType.softInvite),
      suggestedLine: candidate.isEmpty ? null : candidate,
      learningLink: LearningLinkResolver.resolve(CoachActionType.softInvite),
    );
  }

  static CoachActionCardData _buildLowerPressureReply({
    required int heatScore,
    required FinalRecommendation finalRecommendation,
    required bool flaggedPath,
  }) {
    final candidate = finalRecommendation.content.trim();
    final whyNow = flaggedPath
        ? '這位對象目前資料還不完整，先放慢一拍別追問'
        : '對方這次的投入度 $heatScore，先接住這輪訊號，不要追問結果';
    return CoachActionCardData(
      actionLabel: '降低壓力',
      whyNow: whyNow,
      task: '這次只回一句，把追問留到下次',
      avoid: '別連發三題、不要追問結果',
      avoidLabel: _avoidLabelForActionType(CoachActionType.lowerPressureReply),
      suggestedLine: candidate.isEmpty ? null : candidate,
      learningLink:
          LearningLinkResolver.resolve(CoachActionType.lowerPressureReply),
    );
  }

  static CoachActionCardData _buildPlayfulReply({
    required int heatScore,
    required FinalRecommendation finalRecommendation,
  }) {
    final candidate = finalRecommendation.content.trim();
    return CoachActionCardData(
      actionLabel: '輕鬆幽默',
      whyNow: '對方這次的投入度 $heatScore，可以丟一個 playful 卡點維持張力',
      task: '拋一個 playful 卡點，留半步空白',
      avoid: '別讓玩笑變嘲弄',
      avoidLabel: _avoidLabelForActionType(CoachActionType.playfulReply),
      suggestedLine: candidate.isEmpty ? null : candidate,
      learningLink: LearningLinkResolver.resolve(CoachActionType.playfulReply),
    );
  }

  static CoachActionCardData _buildPausePursuit({required int heatScore}) {
    return CoachActionCardData(
      actionLabel: '暫停追問',
      whyNow: '對方這次的投入度 $heatScore，這時推進反而容易把話聊死',
      task: '今天先不主動再傳，明天觀察她有沒有開新話題',
      avoid: '別連發訊息追問結果',
      avoidLabel: _avoidLabelForActionType(CoachActionType.pausePursuit),
      suggestedLine: null,
      learningLink: LearningLinkResolver.resolve(CoachActionType.pausePursuit),
    );
  }

  static CoachActionCardData? _buildFromCoachActionHint(
    CoachActionHint? hint,
  ) {
    if (hint == null || !hint.isUsable) return null;

    final catchablePoint = hint.catchablePoint.trim();
    final read = hint.read.trim();
    final actionType = _hintActionTypeMap[hint.actionType.trim()] ??
        CoachActionType.extendTopicStoryFrame;

    return CoachActionCardData(
      actionLabel: '可接球點',
      whyNow: '她丟出的球：$catchablePoint。$read',
      task: hint.microMove.trim(),
      avoid: hint.avoid.trim(),
      avoidLabel: _avoidLabelForActionType(actionType),
      suggestedLine: null,
      learningLink: LearningLinkResolver.resolve(actionType),
    );
  }

  static CoachActionCardData _buildConcreteTopicExtension({
    required int heatScore,
    required String latestPartnerMessage,
  }) {
    final topic = _compactTopic(latestPartnerMessage);
    final whyNow = topic.isEmpty
        ? '對方這次的投入度 $heatScore，她有丟出可延展的生活話題，先接住內容再觀察'
        : '對方這次的投入度 $heatScore，她丟出「$topic」這種生活話題，先接住內容再觀察';
    return CoachActionCardData(
      actionLabel: '接住生活話題',
      whyNow: whyNow,
      task: '先接她的內容，再補一個你的感受或低壓小問題',
      avoid: '別只連問清單題，也別急著判斷她冷或熱',
      avoidLabel:
          _avoidLabelForActionType(CoachActionType.extendTopicStoryFrame),
      suggestedLine: null,
      learningLink:
          LearningLinkResolver.resolve(CoachActionType.extendTopicStoryFrame),
    );
  }

  static CoachActionCardData _buildExtendTopicStoryFrame({
    required int heatScore,
    required FinalRecommendation finalRecommendation,
  }) {
    final candidate = finalRecommendation.content.trim();
    return CoachActionCardData(
      actionLabel: '故事框架',
      whyNow: '對方這次的投入度 $heatScore，可以用故事框架往下展開',
      task: '用「場景 + 觀點/情緒 + 開放式提問」這個框架延展話題',
      avoid: '別只丟一個開放式問句',
      avoidLabel:
          _avoidLabelForActionType(CoachActionType.extendTopicStoryFrame),
      suggestedLine: candidate.isEmpty ? null : candidate,
      learningLink:
          LearningLinkResolver.resolve(CoachActionType.extendTopicStoryFrame),
    );
  }

  static CoachActionCardData _buildPreferenceSignal({required int heatScore}) {
    return CoachActionCardData(
      actionLabel: '輕量表達偏好',
      whyNow: '對方這次的投入度 $heatScore，可以輕鬆露出自己的偏好',
      task: '講一個自己的小喜好或觀點，不問問題',
      avoid: '別把這當解釋自己',
      avoidLabel: _avoidLabelForActionType(CoachActionType.preferenceSignal),
      suggestedLine: null,
      learningLink:
          LearningLinkResolver.resolve(CoachActionType.preferenceSignal),
    );
  }

  static CoachActionCardData _buildRightSizeReply({
    required int heatScore,
    required FinalRecommendation finalRecommendation,
  }) {
    final candidate = finalRecommendation.content.trim();
    return CoachActionCardData(
      actionLabel: '回得剛剛好',
      whyNow: '對方這次的投入度 $heatScore，下一句先精簡一點，讓對方更容易接球',
      task: '先抓對方上一句的份量，控制在 1.8 倍內再延伸',
      avoid: '別一次塞太多細節',
      avoidLabel: _avoidLabelForActionType(CoachActionType.rightSizeReply),
      suggestedLine: candidate.isEmpty ? null : candidate,
      learningLink:
          LearningLinkResolver.resolve(CoachActionType.rightSizeReply),
    );
  }

  static CoachActionCardData _buildEmotionalResonance({
    required int heatScore,
    required FinalRecommendation finalRecommendation,
    required bool challengeSignal,
  }) {
    final candidate = finalRecommendation.content.trim();
    final whyNow = challengeSignal
        ? '對方這次的投入度 $heatScore，她丟的是互動測試，不是要你解釋；先穩住語氣'
        : '對方這次的投入度 $heatScore，這次有明確情緒訊號，先讓她覺得被理解';
    return CoachActionCardData(
      actionLabel: challengeSignal ? '接住試探球' : '情緒共鳴',
      whyNow: whyNow,
      task: challengeSignal ? '先輕鬆承接，再把球自然丟回去' : '先命名她的感受，再用一句低壓提問延伸',
      avoid: challengeSignal ? '別急著自證、道歉或反擊' : '別急著給建議或講道理',
      avoidLabel: _avoidLabelForActionType(CoachActionType.emotionalResonance),
      suggestedLine: candidate.isEmpty ? null : candidate,
      learningLink:
          LearningLinkResolver.resolve(CoachActionType.emotionalResonance),
    );
  }

  static CoachActionCardData _buildFitCheck({
    required int heatScore,
    required bool isDataQualityFlagged,
  }) {
    // When the partner profile is flagged, avoid any phrasing that implies
    // long-term knowledge of the person — fall back to "this interaction only".
    final whyNow = isDataQualityFlagged
        ? '這位對象目前資料還不完整，先用這次互動的訊號來判斷'
        : '對方這次的投入度 $heatScore，訊號還輕；先看她願不願意把話接回來';
    return CoachActionCardData(
      actionLabel: '互動品質觀察',
      whyNow: whyNow,
      task: '回一個低壓小球，觀察她會不會補細節',
      avoid: '不要把短回覆直接解讀成冷或熱',
      avoidLabel: _avoidLabelForActionType(CoachActionType.fitCheck),
      suggestedLine: null,
      learningLink: LearningLinkResolver.resolve(CoachActionType.fitCheck),
    );
  }
}
