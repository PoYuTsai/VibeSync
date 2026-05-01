import 'coach_action_type.dart';

/// actionType 對映「現有 20 篇文章」的 articleId（exact match only）。
/// 回傳 `null` 時 CoachActionCard 隱藏「看教學」CTA（無 fallback 分類頁）。
class LearningLinkResolver {
  const LearningLinkResolver._();

  static const Map<CoachActionType, String?> _table = {
    CoachActionType.softInvite: null,
    CoachActionType.lowerPressureReply: '10',
    CoachActionType.extendTopicStoryFrame: '14',
    CoachActionType.emotionalResonance: '11',
    CoachActionType.rightSizeReply: '12',
    CoachActionType.playfulReply: '3',
    CoachActionType.pausePursuit: null,
    CoachActionType.preferenceSignal: '2',
    CoachActionType.fitCheck: '18',
  };

  static String? resolve(CoachActionType type) => _table[type];
}
