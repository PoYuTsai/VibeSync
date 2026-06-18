import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/domain/mindmap/mind_map_models.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_mind_map_entry_card.dart';

/// 帶階段 + 興趣/特質 + 下一步全文的完整 map（入口卡只該 preview 興趣/特質，
/// 不該重貼下一步全文）。
PartnerMindMap _fullMap({
  List<String> interests = const ['茶碗蒸', '蛋白質'],
  List<String> traits = const ['幽默'],
  String nextStep = '約她這週末去看那個她提過的攝影展，順勢帶到展後喝咖啡',
}) =>
    PartnerMindMap(
      hasAnalysisData: true,
      root: MindMapNode(
        id: 'root',
        label: 'Vivi',
        branch: MindMapBranch.root,
        children: [
          const MindMapNode(
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
            id: 'interests',
            label: '興趣',
            branch: MindMapBranch.interests,
            children: [
              for (var i = 0; i < interests.length; i++)
                MindMapNode(
                    id: 'interest-$i',
                    label: interests[i],
                    branch: MindMapBranch.interests),
            ],
          ),
          MindMapNode(
            id: 'traits',
            label: '特質',
            branch: MindMapBranch.traits,
            children: [
              for (var i = 0; i < traits.length; i++)
                MindMapNode(
                    id: 'trait-$i',
                    label: traits[i],
                    branch: MindMapBranch.traits),
            ],
          ),
          MindMapNode(
            id: 'next',
            label: '下一步',
            branch: MindMapBranch.nextStep,
            children: [
              MindMapNode(
                  id: 'next-step',
                  label: nextStep,
                  branch: MindMapBranch.nextStep),
            ],
          ),
        ],
      ),
    );

void main() {
  testWidgets('有資料 → 顯示標題 + 階段 pill + 可接話題 preview，點擊觸發 onTap',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerMindMapEntryCard(map: _fullMap(), onTap: () => tapped = true),
      ),
    ));
    expect(find.text('對象作戰板'), findsOneWidget);
    expect(find.text('💫 建立男女感'), findsOneWidget);
    // 興趣前兩項串成可接話題 preview。
    expect(find.text('可接話題：茶碗蒸 / 蛋白質'), findsOneWidget);
    await tester.tap(find.byType(PartnerMindMapEntryCard));
    expect(tapped, isTrue);
  });

  testWidgets('入口卡不重貼下一步全文（IA 去重）', (tester) async {
    const fullNextStep = '約她這週末去看那個她提過的攝影展，順勢帶到展後喝咖啡';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerMindMapEntryCard(
          map: _fullMap(nextStep: fullNextStep),
          onTap: () {},
        ),
      ),
    ));
    expect(find.textContaining(fullNextStep), findsNothing,
        reason: '完整下一步只屬於下方主卡與作戰板詳情，入口卡只放 preview');
    expect(find.textContaining('下一步：'), findsNothing);
  });

  testWidgets('只有特質沒有興趣 → 退回抓手 preview', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerMindMapEntryCard(
          map: _fullMap(interests: const [], traits: const ['溫柔']),
          onTap: () {},
        ),
      ),
    ));
    expect(find.text('抓手：溫柔'), findsOneWidget);
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
