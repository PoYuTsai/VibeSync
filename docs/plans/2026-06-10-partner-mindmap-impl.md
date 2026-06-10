# 對象作戰板（Partner Mind Map）Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> 設計依據：`docs/plans/2026-06-10-partner-mindmap-design.md`（Eric 拍板 B / C / A）。

**Goal:** 每個對象一張「作戰板」心智圖（根＝對象名，五主枝＝階段/話題深度/興趣/特質/下一步），雙入口（對象詳情頁區塊 + 報告頁底部橫向卡片列），dogfood 期全 tier 免費。

**Architecture:** 純 Dart `buildPartnerMindMap()` 把既有 Hive 快照（`lastAnalysisSnapshotJson` + `PartnerAggregateView`）轉成節點樹，零新 API 呼叫；渲染走 `graphview` package（BuchheimWalker LEFT_RIGHT）+ `InteractiveViewer`；全螢幕頁走 go_router `/partner/:partnerId/mindmap`。

**Tech Stack:** Flutter 3.x / Riverpod / go_router / graphview ^1.5.1（已驗證：2025-10-17 發布、pub points 130/160、月下載 3.5 萬、dart3 相容，**不需退 CustomPaint 自繪**）。

**硬約束:**
- 報告頁動態 bokeh 背景（`lib/shared/widgets/gradient_background.dart`、`main_shell.dart`）**絕不碰**。
- `my_report_screen.dart` 既有三張圖與 Free gating（`_lockedReportCard`）行為不變；新區塊放在 if/else 區塊之外、所有 tier 可見（決策 A）。
- 不做：訂閱 gating、節點編輯、全局總覽圖、AI 即時生成（YAGNI 清單見設計文件）。
- 每 task 一個 commit、繁中 commit message、commit 後立即 push（測試期協議：直接上 main）。

**關鍵既有事實（已查證，不要重查）:**

| 事實 | 位置 |
|---|---|
| `PartnerAggregateView`：`unionInterests`/`unionTraits`（各上限 8）/`unionNotes`/`latestHeat`/`totalRounds`/`totalMessages`/`lastInteraction` | `lib/features/partner/domain/extensions/partner_aggregates.dart:6-34` |
| 快照 = `jsonEncode(result.rawResponse)`，頂層 key：`gameStage{current,status,nextStep}`、`topicDepth{current,suggestion}`、`strategy`、`targetProfile{interests,traits,notes}` | `analysis_screen.dart:1171`、`analysis_models.dart` |
| `GameStage` enum（opening/premise/qualification/narrative/close）有 `.label`/`.emoji`；`GameStageInfo.fromJson` 容 null | `lib/features/analysis/domain/entities/game_stage.dart` |
| `TopicDepthLevel`（event/personal/intimate）有 `.label`/`.emoji`；`TopicDepth.fromJson` 容 null | `analysis_models.dart:5-69` |
| `Conversation.currentGameStage: String?`（fallback 來源）、`lastAnalysisSnapshotJson: String?` | `conversation.dart:38,55` |
| Providers：`partnerByIdProvider`/`partnerAggregateProvider`/`conversationsByPartnerProvider`/`partnerListProvider` | `lib/features/partner/presentation/providers/partner_providers.dart` |
| 詳情頁插入點：`PartnerHeatHeroCard` 之後、對話紀錄之前 | `partner_detail_screen.dart:134-136` |
| 報告頁：`ListView` 內 `if (subscription.isFreeUser) _lockedReportCard …` 區塊，新 section 接在整個 if/else 之後 | `my_report_screen.dart:25-74` |
| 色票：`AppColors.primary`(0xFF6B4EE6)/`ctaStart`(0xFFFF7043)/`ctaEnd`(0xFFFF5722)/`glassWhite`/`glassBorder` | `lib/core/theme/app_colors.dart` |
| Glass 卡片：`GlassmorphicContainer(child, borderRadius, padding)` | `lib/shared/widgets/glassmorphic_container.dart` |
| 路由 push 範式：`context.push('/partner/$partnerId/merge')`；route 定義在 `lib/app/routes.dart`（`/partner/:partnerId` 約 114-118 行） | `routes.dart` |
| 純 Dart 測試範式（Conversation/Partner 直接建構、**不需 Hive init**）：抄 `_partner()`/`_convo()`/`_snapshot()` helpers | `test/unit/entities/partner_aggregates_test.dart:1-58` |
| Widget 測試範式：`ProviderScope(overrides:[…])` + GoRouter stub | `test/widget/features/copy_sweep_snapshot_test.dart` |

---

### Task 1: 加入 graphview 依賴

**Files:**
- Modify: `pubspec.yaml`（dependencies 區，`fl_chart: ^0.70.2` 下一行）

**Step 1: 加依賴**

```yaml
  graphview: ^1.5.1
```

**Step 2: 安裝並驗證**

Run: `flutter pub get`
Expected: 成功 resolve，無版本衝突（graphview SDK 約束 `>=2.17 <4.0`，專案 `>=3.6.0`，相容）。

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: 加入 graphview 依賴（對象作戰板渲染）" && git push
```

---

### Task 2: MindMap 模型 + Builder（TDD）

**Files:**
- Create: `lib/features/partner/domain/mindmap/mind_map_models.dart`
- Create: `lib/features/partner/domain/mindmap/mind_map_builder.dart`
- Test: `test/unit/features/partner/mind_map_builder_test.dart`

**Step 1: 寫失敗測試**

抄 `partner_aggregates_test.dart` 的 `_convo()` helper（含 `currentGameStage` 參數），快照 helper 改為含頂層 `gameStage`/`topicDepth`/`strategy`：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/domain/mindmap/mind_map_builder.dart';
import 'package:vibesync/features/partner/domain/mindmap/mind_map_models.dart';

Conversation _convo({
  required String id,
  required DateTime updatedAt,
  String? snapshotJson,
  String? currentGameStage,
}) =>
    Conversation(
      id: id,
      name: 'c-$id',
      messages: const [],
      createdAt: updatedAt,
      updatedAt: updatedAt,
      currentGameStage: currentGameStage,
      lastAnalysisSnapshotJson: snapshotJson,
    );

String _snapshot({
  String stage = 'premise',
  String nextStep = '約她週末喝咖啡',
  String depth = 'personal',
  String strategy = '維持神秘感',
}) =>
    jsonEncode({
      'gameStage': {'current': stage, 'status': 'normal', 'nextStep': nextStep},
      'topicDepth': {'current': depth, 'suggestion': ''},
      'strategy': strategy,
      'targetProfile': {
        'interests': ['爬山', '咖啡'],
        'traits': ['幽默'],
        'notes': <String>[],
      },
    });

PartnerAggregateView _aggregate({
  List<String> interests = const ['爬山', '咖啡'],
  List<String> traits = const ['幽默'],
}) =>
    PartnerAggregateView(
      unionInterests: interests,
      unionTraits: traits,
      unionNotes: null,
      latestHeat: null,
      totalRounds: 0,
      totalMessages: 0,
      lastInteraction: null,
    );

void main() {
  group('buildPartnerMindMap', () {
    test('完整快照 → 根節點 + 五主枝', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot()),
        ],
      );
      expect(map.hasAnalysisData, isTrue);
      expect(map.root.label, 'Vivi');
      final branches = map.root.children.map((n) => n.branch).toList();
      expect(branches, [
        MindMapBranch.stage,
        MindMapBranch.topicDepth,
        MindMapBranch.interests,
        MindMapBranch.traits,
        MindMapBranch.nextStep,
      ]);
      // 階段枝：premise → 建立男女感
      final stage =
          map.root.children.firstWhere((n) => n.branch == MindMapBranch.stage);
      expect(stage.children.single.label, contains('建立男女感'));
      // 話題深度枝：personal → 個人層
      final depth = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.topicDepth);
      expect(depth.children.single.label, contains('個人層'));
      // 興趣/特質枝吃 aggregate
      final interests = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.interests);
      expect(interests.children.map((n) => n.label), ['爬山', '咖啡']);
      // 下一步枝
      final next = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.nextStep);
      expect(next.children.single.label, '約她週末喝咖啡');
    });

    test('取最新一筆可解析快照（依 updatedAt 降冪）', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'old',
              updatedAt: DateTime(2026, 5, 1),
              snapshotJson: _snapshot(stage: 'opening', nextStep: '舊建議')),
          _convo(
              id: 'new',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot(stage: 'close', nextStep: '新建議')),
        ],
      );
      final stage =
          map.root.children.firstWhere((n) => n.branch == MindMapBranch.stage);
      expect(stage.children.single.label, contains('準備邀約'));
    });

    test('nextStep 空字串 → fallback 到 strategy', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot(nextStep: '', strategy: '維持神秘感')),
        ],
      );
      final next = map.root.children
          .firstWhere((n) => n.branch == MindMapBranch.nextStep);
      expect(next.children.single.label, '維持神秘感');
    });

    test('興趣/特質空 → 該枝整枝省略，不產生空枝', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot()),
        ],
      );
      final branches = map.root.children.map((n) => n.branch);
      expect(branches, isNot(contains(MindMapBranch.interests)));
      expect(branches, isNot(contains(MindMapBranch.traits)));
    });

    test('無快照但有 currentGameStage → 退化為僅階段枝、hasAnalysisData true', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(interests: [], traits: []),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              currentGameStage: 'qualification'),
        ],
      );
      expect(map.hasAnalysisData, isTrue);
      final stage =
          map.root.children.firstWhere((n) => n.branch == MindMapBranch.stage);
      expect(stage.children.single.label, contains('互相評估'));
      expect(map.root.children.map((n) => n.branch),
          isNot(contains(MindMapBranch.nextStep)));
    });

    test('完全沒分析過 → hasAnalysisData false、不 crash', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: PartnerAggregateView.empty(),
        conversations: [
          _convo(id: 'c1', updatedAt: DateTime(2026, 6, 1)),
        ],
      );
      expect(map.hasAnalysisData, isFalse);
      expect(map.root.children, isEmpty);
    });

    test('malformed JSON 快照 → 安全跳過，不 crash', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: PartnerAggregateView.empty(),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: '{not json'),
        ],
      );
      expect(map.hasAnalysisData, isFalse);
    });

    test('節點 id 全樹唯一（graphview Node.Id 要求）', () {
      final map = buildPartnerMindMap(
        partnerName: 'Vivi',
        aggregate: _aggregate(),
        conversations: [
          _convo(
              id: 'c1',
              updatedAt: DateTime(2026, 6, 1),
              snapshotJson: _snapshot()),
        ],
      );
      final ids = <String>[];
      void walk(MindMapNode n) {
        ids.add(n.id);
        n.children.forEach(walk);
      }

      walk(map.root);
      expect(ids.toSet().length, ids.length);
    });
  });
}
```

**Step 2: 跑測試確認失敗**

Run: `flutter test test/unit/features/partner/mind_map_builder_test.dart`
Expected: FAIL（`mind_map_builder.dart` 不存在，compile error）。

**Step 3: 最小實作**

`lib/features/partner/domain/mindmap/mind_map_models.dart`：

```dart
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
```

`lib/features/partner/domain/mindmap/mind_map_builder.dart`：

```dart
import 'dart:convert';

import '../../../analysis/domain/entities/analysis_models.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../extensions/partner_aggregates.dart';
import 'mind_map_models.dart';

/// 把對象的既有分析資料組成作戰板節點樹。
///
/// 資料來源（與 partner_aggregates 同一套快照，不打任何新 API）：
/// - 階段 / 話題深度 / 下一步：最新一筆可解析的 lastAnalysisSnapshotJson；
///   階段另有 conversation.currentGameStage 作 fallback。
/// - 興趣 / 特質：PartnerAggregateView 跨對話聚合（已去重、各上限 8）。
PartnerMindMap buildPartnerMindMap({
  required String partnerName,
  required PartnerAggregateView aggregate,
  required List<Conversation> conversations,
}) {
  final descByDate = [...conversations]
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Map<String, dynamic>? snapshot;
  for (final c in descByDate) {
    final raw = c.lastAnalysisSnapshotJson;
    if (raw == null || raw.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        snapshot = decoded;
        break;
      }
    } catch (_) {
      // 與 partner_aggregates._parseSnapshot 同策略：壞快照靜默跳過。
    }
  }

  String? fallbackStageRaw;
  for (final c in descByDate) {
    final raw = c.currentGameStage?.trim();
    if (raw != null && raw.isNotEmpty) {
      fallbackStageRaw = raw;
      break;
    }
  }

  final hasAnalysisData = snapshot != null || fallbackStageRaw != null;
  final branches = <MindMapNode>[];

  if (hasAnalysisData) {
    // 階段枝（hasAnalysisData 成立時必有，全圖至少一條邊）
    final stage = snapshot != null
        ? GameStageInfo.fromJson(
                snapshot['gameStage'] as Map<String, dynamic>?)
            .current
        : GameStage.fromString(fallbackStageRaw!);
    branches.add(MindMapNode(
      id: 'stage',
      label: '關係階段',
      branch: MindMapBranch.stage,
      children: [
        MindMapNode(
          id: 'stage-current',
          label: '${stage.emoji} ${stage.label}',
          branch: MindMapBranch.stage,
        ),
      ],
    ));

    if (snapshot != null) {
      final depth = TopicDepth.fromJson(
              snapshot['topicDepth'] as Map<String, dynamic>?)
          .current;
      branches.add(MindMapNode(
        id: 'depth',
        label: '話題深度',
        branch: MindMapBranch.topicDepth,
        children: [
          MindMapNode(
            id: 'depth-current',
            label: '${depth.emoji} ${depth.label}',
            branch: MindMapBranch.topicDepth,
          ),
        ],
      ));
    }

    if (aggregate.unionInterests.isNotEmpty) {
      branches.add(MindMapNode(
        id: 'interests',
        label: '興趣',
        branch: MindMapBranch.interests,
        children: [
          for (var i = 0; i < aggregate.unionInterests.length; i++)
            MindMapNode(
              id: 'interest-$i',
              label: aggregate.unionInterests[i],
              branch: MindMapBranch.interests,
            ),
        ],
      ));
    }

    if (aggregate.unionTraits.isNotEmpty) {
      branches.add(MindMapNode(
        id: 'traits',
        label: '特質',
        branch: MindMapBranch.traits,
        children: [
          for (var i = 0; i < aggregate.unionTraits.length; i++)
            MindMapNode(
              id: 'trait-$i',
              label: aggregate.unionTraits[i],
              branch: MindMapBranch.traits,
            ),
        ],
      ));
    }

    if (snapshot != null) {
      final stageInfo = GameStageInfo.fromJson(
          snapshot['gameStage'] as Map<String, dynamic>?);
      final strategy = (snapshot['strategy'] as String?)?.trim() ?? '';
      final nextStep =
          stageInfo.nextStep.trim().isNotEmpty ? stageInfo.nextStep.trim() : strategy;
      if (nextStep.isNotEmpty) {
        branches.add(MindMapNode(
          id: 'next',
          label: '下一步',
          branch: MindMapBranch.nextStep,
          children: [
            MindMapNode(
              id: 'next-step',
              label: nextStep,
              branch: MindMapBranch.nextStep,
            ),
          ],
        ));
      }
    }
  }

  return PartnerMindMap(
    root: MindMapNode(
      id: 'root',
      label: partnerName,
      branch: MindMapBranch.root,
      children: branches,
    ),
    hasAnalysisData: hasAnalysisData,
  );
}
```

**Step 4: 跑測試確認通過**

Run: `flutter test test/unit/features/partner/mind_map_builder_test.dart`
Expected: 8 tests PASS。

**Step 5: Commit**

```bash
git add lib/features/partner/domain/mindmap/ test/unit/features/partner/mind_map_builder_test.dart
git commit -m "feat: 對象作戰板節點樹 builder（快照衍生，零 AI 成本）" && git push
```

---

### Task 3: PartnerMindMapView 渲染 widget

**Files:**
- Create: `lib/features/partner/presentation/widgets/partner_mind_map_view.dart`
- Test: `test/widget/features/partner/partner_mind_map_view_test.dart`

**Step 1: 寫失敗測試**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/domain/mindmap/mind_map_models.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_mind_map_view.dart';

PartnerMindMap _map() => const PartnerMindMap(
      hasAnalysisData: true,
      root: MindMapNode(
        id: 'root',
        label: 'Vivi',
        branch: MindMapBranch.root,
        children: [
          MindMapNode(
            id: 'stage',
            label: '關係階段',
            branch: MindMapBranch.stage,
            children: [
              MindMapNode(
                  id: 'stage-current',
                  label: '💫 建立男女感',
                  branch: MindMapBranch.stage),
            ],
          ),
          MindMapNode(
            id: 'next',
            label: '下一步',
            branch: MindMapBranch.nextStep,
            children: [
              MindMapNode(
                  id: 'next-step',
                  label: '約她週末喝咖啡',
                  branch: MindMapBranch.nextStep),
            ],
          ),
        ],
      ),
    );

void main() {
  testWidgets('渲染根節點與全部枝節點文字', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PartnerMindMapView(map: _map()))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Vivi'), findsOneWidget);
    expect(find.text('關係階段'), findsOneWidget);
    expect(find.text('💫 建立男女感'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('約她週末喝咖啡'), findsOneWidget);
  });
}
```

**Step 2: 跑測試確認失敗**

Run: `flutter test test/widget/features/partner/partner_mind_map_view_test.dart`
Expected: FAIL（widget 不存在）。

**Step 3: 實作**

```dart
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/mindmap/mind_map_models.dart';

/// 作戰板渲染層：BuchheimWalker 樹狀佈局 + 平移縮放。
/// 「下一步」枝橘色加重（作戰板定位），其餘 glass 語彙。
class PartnerMindMapView extends StatefulWidget {
  final PartnerMindMap map;

  const PartnerMindMapView({super.key, required this.map});

  @override
  State<PartnerMindMapView> createState() => _PartnerMindMapViewState();
}

class _PartnerMindMapViewState extends State<PartnerMindMapView> {
  late final Graph _graph;
  late final BuchheimWalkerConfiguration _config;
  final Map<String, MindMapNode> _byId = {};

  @override
  void initState() {
    super.initState();
    _graph = Graph()..isTree = true;
    _config = BuchheimWalkerConfiguration()
      ..siblingSeparation = 24
      ..levelSeparation = 48
      ..subtreeSeparation = 32
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_LEFT_RIGHT;
    _addNode(widget.map.root, null);
  }

  void _addNode(MindMapNode node, Node? parent) {
    final gNode = Node.Id(node.id);
    _byId[node.id] = node;
    if (parent == null) {
      _graph.addNode(gNode);
    } else {
      _graph.addEdge(parent, gNode);
    }
    for (final child in node.children) {
      _addNode(child, gNode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(80),
      minScale: 0.4,
      maxScale: 2.0,
      child: GraphView(
        graph: _graph,
        algorithm: BuchheimWalkerAlgorithm(_config, TreeEdgeRenderer(_config)),
        paint: Paint()
          ..color = AppColors.primaryLight.withValues(alpha: 0.45)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke,
        builder: (Node node) {
          final data = _byId[node.key!.value as String]!;
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
        color: gradient == null
            ? Colors.white.withValues(alpha: 0.08)
            : null,
        borderRadius: BorderRadius.circular(_isRoot ? 18 : 12),
        border: Border.all(color: borderColor, width: _isRoot ? 1.5 : 1),
      ),
      child: Text(
        node.label,
        style: (_isRoot ? AppTypography.titleMedium : AppTypography.bodySmall)
            .copyWith(
          color: textColor,
          fontWeight: _isRoot || _isNextStep ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
```

注意：`graphview` 的 import 路徑是 `package:graphview/GraphView.dart`（大寫，套件歷史造成）。若 `AppTypography.titleMedium`/`bodySmall` 名稱不符，以 `lib/core/theme/app_typography.dart` 實際 getter 為準。

**Step 4: 跑測試確認通過**

Run: `flutter test test/widget/features/partner/partner_mind_map_view_test.dart`
Expected: PASS。

**Step 5: Commit**

```bash
git add lib/features/partner/presentation/widgets/partner_mind_map_view.dart test/widget/features/partner/partner_mind_map_view_test.dart
git commit -m "feat: 作戰板 graphview 渲染層（下一步枝橘色加重）" && git push
```

---

### Task 4: 全螢幕 PartnerMindMapScreen + route

**Files:**
- Create: `lib/features/partner/presentation/screens/partner_mind_map_screen.dart`
- Modify: `lib/app/routes.dart`（`/partner/:partnerId` GoRoute 附近，加同層 route）

**Step 1: 實作 screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/mindmap/mind_map_builder.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_mind_map_view.dart';

/// 對象作戰板全螢幕頁。dogfood 期全 tier 免費（決策 A），
/// 送審前 gating 另案（動訂閱區 → Codex 雙審）。
class PartnerMindMapScreen extends ConsumerWidget {
  final String partnerId;

  const PartnerMindMapScreen({super.key, required this.partnerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerByIdProvider(partnerId));
    final aggregate = ref.watch(partnerAggregateProvider(partnerId));
    final conversations =
        ref.watch(conversationsByPartnerProvider(partnerId));

    final map = buildPartnerMindMap(
      partnerName: partner?.name ?? '對象',
      aggregate: aggregate,
      conversations: conversations,
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '${partner?.name ?? ''} 的作戰板',
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.partnerDetailBgTop,
              AppColors.partnerDetailBgBottom,
            ],
          ),
        ),
        child: SafeArea(
          child: map.hasAnalysisData
              ? PartnerMindMapView(map: map)
              : _EmptyState(),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗺️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              '完成一次對話分析，解鎖她的作戰板',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}
```

（`partnerDetailBgTop`/`partnerDetailBgBottom` 在 `app_colors.dart`；若詳情頁實際用別的漸層常數，照抄 `partner_detail_screen.dart` 的背景用法。）

**Step 2: 加 route**

在 `routes.dart` 的 `/partner/:partnerId` GoRoute 同層（仿 `/partner/:partnerId/merge` 寫法）：

```dart
GoRoute(
  path: '/partner/:partnerId/mindmap',
  builder: (context, state) => PartnerMindMapScreen(
    partnerId: state.pathParameters['partnerId']!,
  ),
),
```

**Step 3: 驗證**

Run: `flutter analyze lib/features/partner lib/app`
Expected: No issues。

**Step 4: Commit**

```bash
git add lib/features/partner/presentation/screens/partner_mind_map_screen.dart lib/app/routes.dart
git commit -m "feat: 對象作戰板全螢幕頁 + /partner/:id/mindmap 路由" && git push
```

---

### Task 5: 詳情頁入口區塊（入口 1）

**Files:**
- Create: `lib/features/partner/presentation/widgets/partner_mind_map_entry_card.dart`
- Modify: `lib/features/partner/presentation/screens/partner_detail_screen.dart`（`PartnerHeatHeroCard` 之後、對話紀錄之前，約 134-136 行）
- Test: `test/widget/features/partner/partner_mind_map_entry_card_test.dart`

**Step 1: 寫失敗測試**

入口卡直接收 `PartnerMindMap` + `onTap`（資料注入，不接 provider，測試免 stub Hive）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/domain/mindmap/mind_map_models.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_mind_map_entry_card.dart';

void main() {
  testWidgets('有資料 → 顯示標題 + 階段/下一步摘要，點擊觸發 onTap', (tester) async {
    var tapped = false;
    const map = PartnerMindMap(
      hasAnalysisData: true,
      root: MindMapNode(
        id: 'root',
        label: 'Vivi',
        branch: MindMapBranch.root,
        children: [
          MindMapNode(
            id: 'stage',
            label: '關係階段',
            branch: MindMapBranch.stage,
            children: [
              MindMapNode(
                  id: 'stage-current',
                  label: '💫 建立男女感',
                  branch: MindMapBranch.stage),
            ],
          ),
          MindMapNode(
            id: 'next',
            label: '下一步',
            branch: MindMapBranch.nextStep,
            children: [
              MindMapNode(
                  id: 'next-step',
                  label: '約她週末喝咖啡',
                  branch: MindMapBranch.nextStep),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerMindMapEntryCard(map: map, onTap: () => tapped = true),
      ),
    ));
    expect(find.text('對象作戰板'), findsOneWidget);
    expect(find.text('💫 建立男女感'), findsOneWidget);
    expect(find.text('約她週末喝咖啡'), findsOneWidget);
    await tester.tap(find.byType(PartnerMindMapEntryCard));
    expect(tapped, isTrue);
  });

  testWidgets('無分析資料 → 顯示解鎖文案，點擊仍可進入', (tester) async {
    var tapped = false;
    const map = PartnerMindMap(
      hasAnalysisData: false,
      root: MindMapNode(
          id: 'root', label: 'Vivi', branch: MindMapBranch.root),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerMindMapEntryCard(map: map, onTap: () => tapped = true),
      ),
    ));
    expect(find.textContaining('解鎖'), findsOneWidget);
    await tester.tap(find.byType(PartnerMindMapEntryCard));
    expect(tapped, isTrue);
  });
}
```

**Step 2: 跑測試確認失敗**

Run: `flutter test test/widget/features/partner/partner_mind_map_entry_card_test.dart`
Expected: FAIL。

**Step 3: 實作入口卡**

視覺對齊詳情頁既有 section（深底 glass）。摘要列：階段 chip + 下一步一行（橘字）；無資料則「完成一次分析，解鎖作戰板」：

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/mindmap/mind_map_models.dart';

/// 詳情頁的作戰板入口卡（入口 1）。摘要 = 階段 + 下一步，點擊進全螢幕圖。
class PartnerMindMapEntryCard extends StatelessWidget {
  final PartnerMindMap map;
  final VoidCallback onTap;

  const PartnerMindMapEntryCard({
    super.key,
    required this.map,
    required this.onTap,
  });

  String? _leafOf(MindMapBranch branch) {
    for (final b in map.root.children) {
      if (b.branch == branch && b.children.isNotEmpty) {
        return b.children.first.label;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final stage = _leafOf(MindMapBranch.stage);
    final nextStep = _leafOf(MindMapBranch.nextStep);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: AppColors.glassBorder.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🗺️', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  '對象作戰板',
                  style: AppTypography.titleSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.6)),
              ],
            ),
            const SizedBox(height: 12),
            if (!map.hasAnalysisData)
              Text(
                '完成一次對話分析，解鎖作戰板',
                style: AppTypography.bodySmall
                    .copyWith(color: Colors.white.withValues(alpha: 0.6)),
              )
            else ...[
              if (stage != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    stage,
                    style: AppTypography.bodySmall.copyWith(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              if (nextStep != null) ...[
                const SizedBox(height: 8),
                Text(
                  '下一步：$nextStep',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                      color: AppColors.ctaStart, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
```

**Step 4: 接進詳情頁**

`partner_detail_screen.dart`，`PartnerHeatHeroCard` 之後（約 134 行後）插入：

```dart
const SizedBox(height: 16),
PartnerMindMapEntryCard(
  map: buildPartnerMindMap(
    partnerName: partner.name,
    aggregate: aggregate,
    conversations: conversations,
  ),
  onTap: () => context.push('/partner/$partnerId/mindmap'),
),
```

（import `mind_map_builder.dart` 與 entry card；`partner`/`aggregate`/`conversations` 變數該 build 方法裡已存在。間距/包裝樣式對齊鄰近區塊既有寫法，若鄰近卡片有統一外距容器就照抄。）

**Step 5: 跑測試 + analyze**

Run: `flutter test test/widget/features/partner/partner_mind_map_entry_card_test.dart && flutter analyze lib/features/partner`
Expected: PASS / No issues。

**Step 6: Commit**

```bash
git add lib/features/partner/presentation/widgets/partner_mind_map_entry_card.dart lib/features/partner/presentation/screens/partner_detail_screen.dart test/widget/features/partner/partner_mind_map_entry_card_test.dart
git commit -m "feat: 對象詳情頁作戰板入口卡（入口 1）" && git push
```

---

### Task 6: 報告頁底部橫向卡片列（入口 2）

**Files:**
- Create: `lib/features/report/presentation/widgets/partner_mindmap_card_list.dart`
- Modify: `lib/features/report/presentation/screens/my_report_screen.dart`
- Test: `test/widget/features/report/partner_mindmap_card_list_test.dart`

**Step 1: 寫失敗測試**

卡片列收 `List<Partner>` + per-partner 階段 label resolver + onTapPartner（資料注入）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/report/presentation/widgets/partner_mindmap_card_list.dart';

Partner _partner(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      ownerUserId: 'u-1',
    );

void main() {
  testWidgets('每個對象一張卡，點擊回傳 partnerId', (tester) async {
    String? tappedId;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerMindMapCardList(
      partners: [_partner('p1', 'Vivi'), _partner('p2', '小美')],
          stageLabelOf: (id) => id == 'p1' ? '💫 建立男女感' : null,
          onTapPartner: (id) => tappedId = id,
        ),
      ),
    ));
    expect(find.text('對象作戰板'), findsOneWidget);
    expect(find.text('Vivi'), findsOneWidget);
    expect(find.text('小美'), findsOneWidget);
    expect(find.text('💫 建立男女感'), findsOneWidget);
    await tester.tap(find.text('Vivi'));
    expect(tappedId, 'p1');
  });

  testWidgets('無對象 → 整個 section 隱藏', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerMindMapCardList(
          partners: const [],
          stageLabelOf: (_) => null,
          onTapPartner: (_) {},
        ),
      ),
    ));
    expect(find.text('對象作戰板'), findsNothing);
  });
}
```

**Step 2: 跑測試確認失敗**

Run: `flutter test test/widget/features/report/partner_mindmap_card_list_test.dart`
Expected: FAIL。

**Step 3: 實作卡片列**

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../partner/domain/entities/partner.dart';

/// 報告頁底部「對象作戰板」橫向卡片列（入口 2，救回報告頁初衷）。
/// dogfood 期全 tier 可見（決策 A），不動既有三張圖與 Free gating。
class PartnerMindMapCardList extends StatelessWidget {
  final List<Partner> partners;
  final String? Function(String partnerId) stageLabelOf;
  final ValueChanged<String> onTapPartner;

  const PartnerMindMapCardList({
    super.key,
    required this.partners,
    required this.stageLabelOf,
    required this.onTapPartner,
  });

  @override
  Widget build(BuildContext context) {
    if (partners.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '對象作戰板',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.ctaStart,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '每個對象的下一步，一張圖看懂',
          style: AppTypography.titleMedium
              .copyWith(color: AppColors.onBackgroundPrimary),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: partners.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final partner = partners[index];
              final stage = stageLabelOf(partner.id);
              return GestureDetector(
                onTap: () => onTapPartner(partner.id),
                child: GlassmorphicContainer(
                  borderRadius: 14,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Text(
                            partner.name,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.glassTextPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.chevron_right,
                              size: 16,
                              color: AppColors.glassTextPrimary
                                  .withValues(alpha: 0.5)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        stage ?? '尚未分析',
                        style: AppTypography.bodySmall.copyWith(
                          color: stage != null
                              ? AppColors.primary
                              : AppColors.glassTextPrimary
                                  .withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
```

（`GlassmorphicContainer`/`AppTypography`/`onBackgroundPrimary` 名稱以實際檔案為準；若 `GlassmorphicContainer` 不收 `borderRadius`/`padding` 之外的參數就照其建構子。）

**Step 4: 接進報告頁**

`my_report_screen.dart` 的 `ListView` children，整個 `if (subscription.isFreeUser) … else …[…]` 區塊**之後**追加（所有 tier 可見）：

```dart
const SizedBox(height: 32),
Consumer(builder: (context, ref, _) {
  final partners = ref.watch(partnerListProvider);
  return PartnerMindMapCardList(
    partners: partners,
    stageLabelOf: (id) {
      final conversations =
          ref.watch(conversationsByPartnerProvider(id));
      for (final c in conversations) {
        final raw = c.currentGameStage?.trim();
        if (raw != null && raw.isNotEmpty) {
          final stage = GameStage.fromString(raw);
          return '${stage.emoji} ${stage.label}';
        }
      }
      return null;
    },
    onTapPartner: (id) => context.push('/partner/$id/mindmap'),
  );
}),
```

需要的 import：`partner_providers.dart`、`game_stage.dart`、`partner_mindmap_card_list.dart`。
注意 `MyReportScreen` 已是 `ConsumerWidget`，可直接用外層 `ref` 不必包 `Consumer`——以現場程式碼為準，能直接用就直接用。

**Step 5: 跑測試 + analyze + 既有報告頁迴歸**

Run: `flutter test test/widget/features/report/ test/widget/features/copy_sweep_snapshot_test.dart && flutter analyze lib/features/report`
Expected: PASS / No issues（設計文件風險 3：報告頁 gating 不得被影響）。

**Step 6: Commit**

```bash
git add lib/features/report/ test/widget/features/report/
git commit -m "feat: 報告頁底部對象作戰板橫向卡片列（入口 2）" && git push
```

---

### Task 7: 全量驗證收尾

**Step 1: 全專案 analyze**

Run: `flutter analyze`
Expected: No issues（既有 stale rot 測試失敗不算，見 queue 記錄：`onboarding_test.dart` demo enthusiasm、`analysis_error_widget_test.dart:135` 為 clean main 既有失敗）。

**Step 2: 跑本 feature 全部測試 + 鄰近迴歸**

Run: `flutter test test/unit/features/partner/mind_map_builder_test.dart test/widget/features/partner/ test/widget/features/report/ test/unit/entities/partner_aggregates_test.dart`
Expected: 全綠。

**Step 3: 收尾報告**

- 測試期協議：不寫 review doc、不開 queue item（純前端、非高風險區——不碰訂閱/quota/auth/analyze-chat/OCR，**不需 Codex 雙審**，但 commit 訊息要清楚）。
- 回報 Eric：作戰板雙入口已 land，等 TestFlight rebuild 後目檢；提醒舊對象（沒跑過新版分析）會看到「完成一次分析解鎖」空狀態，屬預期行為。

**驗收清單（對照設計文件）:**

- [ ] 詳情頁有作戰板入口卡（階段 + 下一步摘要）
- [ ] 報告頁底部有橫向卡片列，Free 用戶也看得到（決策 A），既有三張圖 gating 不變
- [ ] 全螢幕圖：根=對象名、五主枝、下一步橘色加重、可平移縮放
- [ ] 沒分析過的對象 → 空狀態不 crash
- [ ] 動態 bokeh 背景零改動（`git diff` 不含 `gradient_background.dart`、`main_shell.dart`）
