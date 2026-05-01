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

      final partnerLength = message.content.trim().length;
      if (partnerLength == 0) return false;
      return latestUserReply.content.trim().length > partnerLength * 1.8;
    }
    return false;
  }

  static const Set<GameStage> _midGameStages = {
    GameStage.premise,
    GameStage.qualification,
    GameStage.narrative,
  };

  static CoachActionCardData evaluate({
    required int heatScore,
    required GameStageInfo gameStage,
    required FinalRecommendation finalRecommendation,
    required List<Message> messages,
    required List<PracticeGoal> practiceGoals,
    required bool isDataQualityFlagged,
    PsychologyAnalysis? psychology,
  }) {
    final card = _select(
      heatScore: heatScore,
      gameStage: gameStage,
      finalRecommendation: finalRecommendation,
      messages: messages,
      practiceGoals: practiceGoals,
      isDataQualityFlagged: isDataQualityFlagged,
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
    final strongSubtext = (psychology?.subtext.trim().length ?? 0) >= 8;
    if (challengeSignal || strongSubtext) {
      return _buildEmotionalResonance(
        heatScore: heatScore,
        finalRecommendation: finalRecommendation,
        challengeSignal: challengeSignal,
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
    final strongSubtext = (psychology?.subtext.trim().length ?? 0) >= 8;
    if (challengeSignal || strongSubtext) {
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
      whyNow: '熱度 $heatScore，互動穩定且對方有訊號，可以給具體選項',
      task: '拋一個低門檻邀約，給具體時間和場景',
      avoid: '別要對方立刻決定',
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
    final whyNow =
        flaggedPath ? '這位對象目前資料還不完整，先放慢一拍別追問' : '熱度 $heatScore，先把溫度留住不要追問結果';
    return CoachActionCardData(
      actionLabel: '降低壓力',
      whyNow: whyNow,
      task: '這次只回一句，把追問留到下次',
      avoid: '別連發三題、不要追問結果',
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
      whyNow: '熱度 $heatScore，可以丟一個 playful 卡點維持張力',
      task: '拋一個 playful 卡點，留半步空白',
      avoid: '別讓玩笑變嘲弄',
      suggestedLine: candidate.isEmpty ? null : candidate,
      learningLink: LearningLinkResolver.resolve(CoachActionType.playfulReply),
    );
  }

  static CoachActionCardData _buildPausePursuit({required int heatScore}) {
    return CoachActionCardData(
      actionLabel: '暫停追問',
      whyNow: '熱度 $heatScore，這時推進反而容易把話聊死',
      task: '今天先不主動再傳，明天觀察她有沒有開新話題',
      avoid: '別連發訊息追問結果',
      suggestedLine: null,
      learningLink: LearningLinkResolver.resolve(CoachActionType.pausePursuit),
    );
  }

  static CoachActionCardData _buildExtendTopicStoryFrame({
    required int heatScore,
    required FinalRecommendation finalRecommendation,
  }) {
    final candidate = finalRecommendation.content.trim();
    return CoachActionCardData(
      actionLabel: '故事框架',
      whyNow: '熱度 $heatScore，可以用故事框架往下展開',
      task: '用「場景 + 觀點/情緒 + 開放式提問」這個框架延展話題',
      avoid: '別只丟一個開放式問句',
      suggestedLine: candidate.isEmpty ? null : candidate,
      learningLink:
          LearningLinkResolver.resolve(CoachActionType.extendTopicStoryFrame),
    );
  }

  static CoachActionCardData _buildPreferenceSignal({required int heatScore}) {
    return CoachActionCardData(
      actionLabel: '輕量表達偏好',
      whyNow: '熱度 $heatScore，可以輕鬆露出自己的偏好',
      task: '講一個自己的小喜好或觀點，不問問題',
      avoid: '別把這當解釋自己',
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
      whyNow: '熱度 $heatScore，這次回得有點長，下一句先精簡一點再展開',
      task: '把回覆字數對齊對方上一句的 1.8 倍以內',
      avoid: '別把所有想說的塞進一封',
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
        ? '熱度 $heatScore，她拋了一個試探訊號，先接住情緒比較穩'
        : '熱度 $heatScore，從字裡行間讀到她在傳訊號，先接住再說';
    return CoachActionCardData(
      actionLabel: '情緒共鳴',
      whyNow: whyNow,
      task: '先用一句接住她的情緒，再決定要不要展開',
      avoid: '別急著給建議或解釋',
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
        : '熱度 $heatScore，先別下定論，當作練觀察';
    return CoachActionCardData(
      actionLabel: '互動品質觀察',
      whyNow: whyNow,
      task: '觀察這次的節奏，記下一個感覺',
      avoid: '不要急著貼標籤',
      suggestedLine: null,
      learningLink: LearningLinkResolver.resolve(CoachActionType.fitCheck),
    );
  }
}
