/// 作戰板節點樹（pure Dart，渲染層無關）。
/// 由 [buildPartnerMindMap] 從既有分析快照衍生，零 AI 邊際成本。
enum MindMapBranch {
  root,
  stage,
  topicDepth,
  currentSignal,
  confirmedFacts,
  interests,
  traits,
  nextStep,
}

class MindMapNode {
  final String id;
  final String label;
  final MindMapBranch branch;
  final List<MindMapNode> children;

  const MindMapNode({
    required this.id,
    required this.label,
    required this.branch,
    this.children = const [],
  });
}

class PartnerMindMap {
  final MindMapNode root;

  /// false = 該對象從未跑過分析（所有對話都沒有可解析快照、也沒有
  /// currentGameStage）→ UI 顯示「再分析一次解鎖」空狀態。
  final bool hasAnalysisData;

  /// 被消費快照（階段/深度/下一步）來源的對話 id ——即「最近一次有分析的
  /// 對話」。nextStep 節點點擊導向 Coach 1:1 預填用；無可解析快照
  /// （僅 currentGameStage fallback）時為 null → 節點不可點。
  final String? nextStepSourceConversationId;

  /// 作戰板詳情用拆解欄位（決策：圖節點放短標籤，整句/拆解進詳情 panel，
  /// 避免「圖節點 = 詳情頁外層同一句」的重貼感）。
  ///
  /// [relationshipSignal] 關係信號（階段描述衍生）；hasAnalysisData 時必有。
  /// [currentSignal] 最新分析中有足夠信心、且能回查聊天內容的具體可接球點。
  /// [confirmedFacts] 使用者在「關於她」親自勾選的 allowlist chips。
  /// [topics] 可接話題（= 聚合興趣）；無興趣時為空。
  /// [fullNextStep] 下一步行動全文；無可解析快照或無 nextStep 時為 null。
  final String? relationshipSignal;
  final String? currentSignal;
  final List<String> confirmedFacts;
  final List<String> topics;
  final String? fullNextStep;

  const PartnerMindMap({
    required this.root,
    required this.hasAnalysisData,
    this.nextStepSourceConversationId,
    this.relationshipSignal,
    this.currentSignal,
    this.confirmedFacts = const [],
    this.topics = const [],
    this.fullNextStep,
  });
}
