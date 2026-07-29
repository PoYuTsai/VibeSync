// lib/features/analysis/domain/coach/learning_link_resolver.dart
//
// 教練動作卡「看 3 分鐘教學」的深連對照表。
//
// 2026-07-30：目標從舊的學習文章（/article/:id）改成 Dating Knowledge
// Library 的電子書章節。理由是文章是通則型的兩性建議，電子書才是這個
// 產品自己的體系；教練說完結論之後要能一步進到同一套語言的原理。
//
// exact match only：查不到回 null，CoachActionCard 隱藏 CTA。
// 絕不 fallback 到分類頁或隨便一章——連錯章比沒有連結更傷信任。
library;

import '../../../learning/domain/dating_knowledge_links.dart';
import '../../../learning/domain/models/learning_link_target.dart';
import 'coach_action_type.dart';

class LearningLinkResolver {
  const LearningLinkResolver._();

  static const Map<CoachActionType, LearningLinkTarget?> _table = {
    // 模糊邀約 → 種子：「提到具體的東西但不指定時間，讓對方有機會表態，
    // 也有機會不表態」——這就是低壓邀約的定義本身。
    CoachActionType.softInvite: LearningLinkTarget(
      bookId: DatingKnowledgeBooks.meeting,
      chapterId: 'ebook-4-chapter-2',
    ),
    // 降低壓力 → 對話為什麼死，死因一就是查戶口。
    CoachActionType.lowerPressureReply: LearningLinkTarget(
      bookId: DatingKnowledgeBooks.conversation,
      chapterId: 'ebook-2-chapter-2',
    ),
    // 故事框架 → 側面價值：讓生活細節在談別的事情時自然出現。
    CoachActionType.extendTopicStoryFrame: LearningLinkTarget(
      bookId: DatingKnowledgeBooks.conversation,
      chapterId: 'ebook-2-chapter-3',
    ),
    // 情緒共鳴 → 回應性三件事：理解、認可、在乎。
    CoachActionType.emotionalResonance: LearningLinkTarget(
      bookId: DatingKnowledgeBooks.conversation,
      chapterId: 'ebook-2-chapter-3',
    ),
    // 回得剛剛好 → 變數標記法的三燈：對稱但不延伸 vs 主動加碼。
    CoachActionType.rightSizeReply: LearningLinkTarget(
      bookId: DatingKnowledgeBooks.conversation,
      chapterId: 'ebook-2-chapter-1',
    ),
    // 輕鬆幽默 → 情緒、玩笑與訊號讀取（張力型 vs 焦慮型）。
    CoachActionType.playfulReply: LearningLinkTarget(
      bookId: DatingKnowledgeBooks.conversation,
      chapterId: 'ebook-2-chapter-4',
    ),
    // 暫停追問 → 診斷樹：第一層就是「她沒興趣」，最常見也最正確的診斷。
    CoachActionType.pausePursuit: LearningLinkTarget(
      bookId: DatingKnowledgeBooks.rescue,
      chapterId: 'ebook-3-chapter-1',
    ),
    // 輕量表達偏好 → 死因三：你沒有出現在對話裡。
    CoachActionType.preferenceSignal: LearningLinkTarget(
      bookId: DatingKnowledgeBooks.conversation,
      chapterId: 'ebook-2-chapter-2',
    ),
    // 互動品質觀察 → 診斷樹。
    CoachActionType.fitCheck: LearningLinkTarget(
      bookId: DatingKnowledgeBooks.rescue,
      chapterId: 'ebook-3-chapter-1',
    ),
  };

  static LearningLinkTarget? resolve(CoachActionType type) => _table[type];
}
