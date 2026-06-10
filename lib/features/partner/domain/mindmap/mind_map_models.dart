/// 作戰板節點樹（pure Dart，渲染層無關）。
/// 由 [buildPartnerMindMap] 從既有分析快照衍生，零 AI 邊際成本。
enum MindMapBranch { root, stage, topicDepth, interests, traits, nextStep }

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

  const PartnerMindMap({required this.root, required this.hasAnalysisData});
}
