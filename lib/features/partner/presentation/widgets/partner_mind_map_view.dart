import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/mindmap/mind_map_models.dart';

/// 作戰板渲染層：BuchheimWalker 樹狀佈局 + 平移縮放 + 雙擊重置視圖。
/// 「下一步」枝橘色加重（作戰板定位），其餘 glass 語彙。
///
/// graph / byId 仍在 build() 每次重建，parent（provider）rebuild 換新
/// map 時不會殘留舊 graph（不變量，勿移進 State）。節點數 ≤ ~20，
/// 重建成本可忽略。State 只持有縮放/重置兩個 controller。
class PartnerMindMapView extends StatefulWidget {
  final PartnerMindMap map;

  /// 「下一步」葉節點單擊 callback（決策 3：只有 nextStep 葉節點可點），
  /// 帶出節點文字供 Coach 1:1 預填。null = 不可點（無可導航對話）。
  /// 與背景雙擊重置並存：單擊有 ~300ms 競技場裁決延遲，已知可接受。
  final void Function(String label)? onNextStepTap;

  const PartnerMindMapView({super.key, required this.map, this.onNextStepTap});

  @override
  State<PartnerMindMapView> createState() => _PartnerMindMapViewState();
}

class _PartnerMindMapViewState extends State<PartnerMindMapView>
    with SingleTickerProviderStateMixin {
  final _transformController = TransformationController();
  late final AnimationController _resetController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  Animation<Matrix4>? _resetAnimation;

  @override
  void initState() {
    super.initState();
    _transformController.value = _homeMatrix();
    // TransformationController 不是 Animation，逐 frame 回寫是官方標準作法。
    _resetController.addListener(() {
      final animation = _resetAnimation;
      if (animation != null) {
        _transformController.value = animation.value;
      }
    });
  }

  @override
  void dispose() {
    _resetController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  Matrix4 _homeMatrix() => Matrix4.diagonal3Values(0.78, 0.78, 1.0)
    ..setTranslationRaw(-86.0, 6.0, 0);

  bool _isSameMatrix(Matrix4 a, Matrix4 b) {
    for (var i = 0; i < 16; i++) {
      if ((a.storage[i] - b.storage[i]).abs() > 0.0001) return false;
    }
    return true;
  }

  /// 雙擊任意處：平滑動畫回舒服的初始縮放視圖。
  void _resetView() {
    final home = _homeMatrix();
    if (_isSameMatrix(_transformController.value, home)) return;
    _resetAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: home,
    ).animate(
      CurvedAnimation(parent: _resetController, curve: Curves.easeOutCubic),
    );
    _resetController.forward(from: 0);
  }

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
    _addNode(graph, byId, widget.map.root, null);
    final config = BuchheimWalkerConfiguration()
      ..siblingSeparation = 26
      ..levelSeparation = 54
      ..subtreeSeparation = 36
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_LEFT_RIGHT;

    // InteractiveViewer 無內建 double-tap API，外層 GestureDetector 偵測。
    // nextStep 葉節點 chip 可單擊（其餘節點不可），單擊與雙擊同場競技、
    // 由 arena 以 double-tap timeout 裁決。
    return GestureDetector(
      onDoubleTap: _resetView,
      child: InteractiveViewer(
        transformationController: _transformController,
        // 重置動畫中用戶開始新手勢 → 動畫讓位，避免互搶 transform。
        onInteractionStart: (_) => _resetController.stop(),
        constrained: false,
        boundaryMargin: const EdgeInsets.all(100),
        minScale: 0.4,
        maxScale: 2.0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 72, 88),
          child: GraphView(
            graph: graph,
            algorithm:
                BuchheimWalkerAlgorithm(config, TreeEdgeRenderer(config)),
            paint: Paint()
              ..color = AppColors.primaryLight.withValues(alpha: 0.36)
              ..strokeWidth = 1.6
              ..style = PaintingStyle.stroke,
            builder: (Node node) {
              // 不變量：graph 與 byId 來自同一棵樹、builder 保證 id 唯一
              // （mind_map_builder_test 已覆蓋），lookup 必命中。
              final data = byId[node.key!.value as String]!;
              // 決策 3：只有 nextStep「葉」節點可點（父標籤「下一步」有
              // children，不帶 callback）。
              final isNextStepLeaf = data.branch == MindMapBranch.nextStep &&
                  data.children.isEmpty;
              final onTap = isNextStepLeaf && widget.onNextStepTap != null
                  ? () => widget.onNextStepTap!(data.label)
                  : null;
              return _MindMapNodeChip(node: data, onTap: onTap);
            },
          ),
        ),
      ),
    );
  }
}

class _MindMapNodeChip extends StatelessWidget {
  final MindMapNode node;

  /// 非 null = 可點（目前僅 nextStep 葉節點）→ 加問教練 icon affordance。
  final VoidCallback? onTap;

  const _MindMapNodeChip({required this.node, this.onTap});

  bool get _isRoot => node.branch == MindMapBranch.root;

  bool get _isNextStep => node.branch == MindMapBranch.nextStep;

  bool get _isNextStepLeaf => _isNextStep && node.children.isEmpty;

  @override
  Widget build(BuildContext context) {
    final Gradient? gradient;
    final Color borderColor;
    final Color textColor;
    final Color? fillColor;
    final List<BoxShadow> shadows;
    if (_isRoot) {
      gradient = LinearGradient(
        colors: [
          AppColors.brandSurface2.withValues(alpha: 0.98),
          AppColors.brandSurface.withValues(alpha: 0.94),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      fillColor = null;
      borderColor = AppColors.ctaStart.withValues(alpha: 0.62);
      textColor = Colors.white;
      shadows = [
        BoxShadow(
          color: AppColors.ctaStart.withValues(alpha: 0.20),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
    } else if (_isNextStepLeaf) {
      gradient = const LinearGradient(
        colors: [AppColors.ctaStart, AppColors.ctaEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      fillColor = null;
      borderColor = Colors.white.withValues(alpha: 0.18);
      textColor = Colors.white;
      shadows = [
        BoxShadow(
          color: AppColors.ctaStart.withValues(alpha: 0.30),
          blurRadius: 18,
          offset: const Offset(0, 9),
        ),
      ];
    } else if (_isNextStep) {
      gradient = null;
      fillColor = AppColors.ctaStart.withValues(alpha: 0.12);
      borderColor = AppColors.ctaStart.withValues(alpha: 0.55);
      textColor = Colors.white.withValues(alpha: 0.94);
      shadows = [
        BoxShadow(
          color: AppColors.ctaStart.withValues(alpha: 0.12),
          blurRadius: 14,
          offset: const Offset(0, 7),
        ),
      ];
    } else {
      gradient = null;
      fillColor = AppColors.brandSurface.withValues(alpha: 0.90);
      borderColor = Colors.white.withValues(alpha: 0.16);
      textColor = Colors.white.withValues(alpha: 0.88);
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 14,
          offset: const Offset(0, 8),
        ),
      ];
    }

    // 「下一步」是整句教練建議（可達 60+ 字），截斷會讓人覺得話沒說完，
    // 而且葉節點單擊已被「問教練」佔用，沒有第二個看全文的出口 → 不截斷。
    // 其餘枝（興趣/特質）是短語，維持 3 行截斷防爆版。
    final untruncated = _isRoot || _isNextStep;
    final label = Text(
      node.label,
      maxLines: untruncated ? null : 3,
      overflow: untruncated ? null : TextOverflow.ellipsis,
      style: (_isRoot ? AppTypography.titleMedium : AppTypography.bodySmall)
          .copyWith(
        color: textColor,
        fontWeight: _isRoot || _isNextStep ? FontWeight.w800 : FontWeight.w600,
        height: _isNextStepLeaf ? 1.45 : 1.25,
      ),
    );

    final chip = Container(
      // 下一步節點放寬到 260：長句行數收斂（畫布可平移，不會擠版）。
      constraints: BoxConstraints(maxWidth: _isNextStepLeaf ? 240 : 210),
      padding: EdgeInsets.symmetric(
        horizontal: _isRoot ? 20 : (_isNextStepLeaf ? 18 : 14),
        vertical: _isRoot ? 12 : (_isNextStepLeaf ? 12 : 9),
      ),
      decoration: BoxDecoration(
        gradient: gradient,
        color: fillColor,
        borderRadius: BorderRadius.circular(_isRoot ? 18 : 16),
        border: Border.all(color: borderColor, width: _isRoot ? 1.4 : 1),
        boxShadow: shadows,
      ),
      child: onTap == null
          ? label
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: label),
                const SizedBox(width: 6),
                // 問教練 affordance，與 CoachChatCard 標頭同 icon 語彙。
                Icon(Icons.forum_outlined, size: 14, color: textColor),
              ],
            ),
    );

    if (onTap == null) {
      return chip;
    }
    return Semantics(
      button: true,
      label: '問教練：${node.label}',
      child: GestureDetector(onTap: onTap, child: chip),
    );
  }
}
