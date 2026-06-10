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
    expect(find.textContaining('約她週末喝咖啡'), findsOneWidget);
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
