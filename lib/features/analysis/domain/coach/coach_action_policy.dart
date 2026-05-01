import '../../../../core/constants/app_constants.dart';
import '../entities/analysis_models.dart';
import '../../../conversation/domain/entities/message.dart';
import '../../../user_profile/domain/entities/user_profile.dart';
import 'coach_action_card_data.dart';
import 'coach_action_type.dart';
import 'learning_link_resolver.dart';

/// Deterministic policy that picks one CoachAction per analysis result.
class CoachActionPolicy {
  const CoachActionPolicy._();

  // Mirror of ScoreActionHint._meetingKeywords. Must stay byte-identical until
  // the legacy widget retires; the regression contract spans both surfaces.
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
      isDataQualityFlagged: isDataQualityFlagged,
    );
    return _filterSuggestedLine(card, heatScore);
  }

  static CoachActionCardData _select({
    required int heatScore,
    required GameStageInfo gameStage,
    required FinalRecommendation finalRecommendation,
    required bool isDataQualityFlagged,
  }) {
    if (heatScore > AppConstants.hotMax) {
      return _buildSoftInvite(
        heatScore: heatScore,
        finalRecommendation: finalRecommendation,
      );
    }
    if (heatScore <= AppConstants.coldMax &&
        _payloadSuggestsMeeting(gameStage.nextStep)) {
      return _buildPausePursuit(heatScore: heatScore);
    }
    return _buildFitCheck(
      heatScore: heatScore,
      isDataQualityFlagged: isDataQualityFlagged,
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
