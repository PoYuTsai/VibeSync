// lib/features/learning/domain/dating_knowledge_links.dart
//
// Dating Knowledge Library 深連對照表（Coach 1:1 側）。
//
// 定位：analyze-chat 與 Coach 在解說時，讓使用者能從「結論」一步進到
// 「原理」。淺水區給結論，深水區給原理——這是 Game Coach 與一般回話 AI
// 的差別，也是這張表存在的唯一理由。
//
// 硬規則：
//   - 這裡只認 id，不組路徑（見 LearningLinkTarget 的說明）。
//   - key 用各 widget 既有的穩定字串（follow-up 的 wire phase），
//     不另外發明第三套代號。
//   - 表裡查不到就回 null，呼叫端隱藏入口——絕不 fallback 到隨便一章。
//     連錯章比沒有連結更傷「教練真的懂」這件事。
//   - chip phase 改動而忘了同步這張表，由
//     `test/unit/features/learning/dating_knowledge_links_test.dart` 擋下。
//     （2026-07-28 AI 鍵盤事故的教訓：taxonomy 兩邊漂移，測試全綠但功能全壞。）
//
// 2026-08-09：CoachSurface 的五個灰色快捷問句 chip 整組移除，對應的
// coachQuestionTable／forCoachQuestion 一併退場；本表只剩 follow-up 三情境。
//
// 目前只指向終極指引 1–4 冊。新單元「成為獎賞：魅力進階課」上線後，
// 內功層的題目（框架、需求感、獎賞）會改指新單元。
library;

import 'models/learning_link_target.dart';

/// 終極指引各冊 id（與 assets/learning/ebooks/*.json 的 `id` 一致）。
class DatingKnowledgeBooks {
  const DatingKnowledgeBooks._();

  static const bottleneck = 'ebook-1-bottleneck';
  static const conversation = 'ebook-2-conversation';
  static const rescue = 'ebook-3-rescue';
  static const meeting = 'ebook-4-meeting';
}

class DatingKnowledgeLinks {
  const DatingKnowledgeLinks._();

  // ── 對象頁「教練跟進」三情境 chip（key = wire lifecyclePhase）─────────
  static const Map<String, LearningLinkTarget> followUpPhaseTable = {
    // 聊天卡住了 → 三個死因（查戶口／只回事實不回情緒／你沒出現在對話裡）
    'chatStalled': LearningLinkTarget(
      bookId: DatingKnowledgeBooks.conversation,
      chapterId: 'ebook-2-chapter-2',
    ),
    // 想約她出來 → 提案：具體時間＋地點＋理由＋低承諾門檻
    'prepareInvite': LearningLinkTarget(
      bookId: DatingKnowledgeBooks.meeting,
      chapterId: 'ebook-4-chapter-3',
    ),
    // 約完會之後 → 到場之後怎麼接續
    'postDate': LearningLinkTarget(
      bookId: DatingKnowledgeBooks.meeting,
      chapterId: 'ebook-4-chapter-5',
    ),
  };

  /// 查不到回 null，呼叫端隱藏入口。
  static LearningLinkTarget? forFollowUpPhase(String? phase) =>
      phase == null ? null : followUpPhaseTable[phase];
}
