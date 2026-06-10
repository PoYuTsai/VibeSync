import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/mindmap/mind_map_models.dart';

/// 作戰板渲染層：BuchheimWalker 樹狀佈局 + 平移縮放。
/// 「下一步」枝橘色加重（作戰板定位），其餘 glass 語彙。
///
/// Stateless：graph / byId 每次 build 重建，parent（provider）rebuild 換新
/// map 時不會殘留舊 graph。節點數 ≤ ~20，重建成本可忽略。
class PartnerMindMapView extends StatelessWidget {
  final PartnerMindMap map;

  const PartnerMindMapView({super.key, required this.map});

  void _addNode(
    Graph graph,
    Map<String, MindMapNode> byId,
    MindMapNode node,
    Node? parent,
  ) {
    final gNode = Node.Id(node.id);
    byId[node.id] = node;
    if (parent == null) {
      graph.addNode(gNode);
    } else {
      graph.addEdge(parent, gNode);
    }
    for (final child in node.children) {
      _addNode(graph, byId, child, gNode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final graph = Graph()..isTree = true;
    final byId = <String, MindMapNode>{};
    _addNode(graph, byId, map.root, null);
    final config = BuchheimWalkerConfiguration()
      ..siblingSeparation = 24
      ..levelSeparation = 48
      ..subtreeSeparation = 32
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_LEFT_RIGHT;

    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(80),
      minScale: 0.4,
      maxScale: 2.0,
      child: GraphView(
        graph: graph,
        algorithm: BuchheimWalkerAlgorithm(config, TreeEdgeRenderer(config)),
        paint: Paint()
          ..color = AppColors.primaryLight.withValues(alpha: 0.45)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke,
        builder: (Node node) {
          // 不變量：graph 與 byId 來自同一棵樹、builder 保證 id 唯一
          // （mind_map_builder_test 已覆蓋），lookup 必命中。
          final data = byId[node.key!.value as String]!;
          return _MindMapNodeChip(node: data);
        },
      ),
    );
  }
}

class _MindMapNodeChip extends StatelessWidget {
  final MindMapNode node;

  const _MindMapNodeChip({required this.node});

  bool get _isRoot => node.branch == MindMapBranch.root;

  bool get _isNextStep => node.branch == MindMapBranch.nextStep;

  @override
  Widget build(BuildContext context) {
    final Gradient? gradient;
    final Color borderColor;
    final Color textColor;
    if (_isRoot) {
      gradient = const LinearGradient(
        colors: [AppColors.primary, AppColors.primaryLight],
      );
      borderColor = AppColors.primaryLight;
      textColor = Colors.white;
    } else if (_isNextStep) {
      gradient = const LinearGradient(
        colors: [AppColors.ctaStart, AppColors.ctaEnd],
      );
      borderColor = AppColors.ctaStart;
      textColor = Colors.white;
    } else {
      gradient = null;
      borderColor = AppColors.glassBorder.withValues(alpha: 0.5);
      textColor = Colors.white.withValues(alpha: 0.92);
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: EdgeInsets.symmetric(
        horizontal: _isRoot ? 20 : 14,
        vertical: _isRoot ? 12 : 8,
      ),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? Colors.white.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(_isRoot ? 18 : 12),
        border: Border.all(color: borderColor, width: _isRoot ? 1.5 : 1),
      ),
      child: Text(
        node.label,
        // 非 root 枝可能是 AI 長句，夾在 maxWidth 200 內最多 3 行截斷。
        maxLines: _isRoot ? null : 3,
        overflow: _isRoot ? null : TextOverflow.ellipsis,
        style: (_isRoot ? AppTypography.titleMedium : AppTypography.bodySmall)
            .copyWith(
          color: textColor,
          fontWeight:
              _isRoot || _isNextStep ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
