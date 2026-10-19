import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
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
  testWidgets('有資料 → 顯示標題 + 階段 pill + 可接話題 preview，點擊觸發 onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerMindMapEntryCard(
            map: _fullMap(), onTap: () => tapped = true),
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
      root: MindMapNode(id: 'root', label: 'Vivi', branch: MindMapBranch.root),
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
  group('v3 的燈號＋短狀態（Bruce 2026-10-19 路線二）', () {
    testWidgets('有階段的 v3：階段旁邊一顆燈號＋短狀態', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PartnerMindMapEntryCard(
            map: PartnerMindMap(
              hasAnalysisData: true,
              root: const MindMapNode(
                id: 'root',
                label: '小安',
                branch: MindMapBranch.root,
                children: [
                  MindMapNode(
                    id: 'stage',
                    label: '目前互動重點',
                    branch: MindMapBranch.stage,
                    children: [
                      MindMapNode(
                        id: 'stage-current',
                        label: '建立男女感',
                        branch: MindMapBranch.stage,
                      ),
                    ],
                  ),
                ],
              ),
              latestGuideV3Signals: const PartnerGuideV3Signals(
                decision: GuideV3Decision.hold,
                light: GuideV3Light.yellow,
              ),
            ),
            onTap: () {},
          ),
        ),
      ));
      expect(find.text('建立男女感'), findsOneWidget);
      final chip = find.byKey(const ValueKey('mind-map-entry-v3-status'));
      expect(
          find.descendant(of: chip, matching: find.text('黃燈')), findsOneWidget);
      expect(find.descendant(of: chip, matching: find.text('先等她')),
          findsOneWidget);
    });

    testWidgets('改版前沒有階段的 v3：只有燈號＋短狀態，不是空白', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PartnerMindMapEntryCard(
            map: const PartnerMindMap(
              hasAnalysisData: true,
              root: MindMapNode(
                id: 'root',
                label: '小安',
                branch: MindMapBranch.root,
              ),
              latestGuideV3Signals: PartnerGuideV3Signals(
                decision: GuideV3Decision.send,
                light: GuideV3Light.green,
              ),
            ),
            onTap: () {},
          ),
        ),
      ));
      expect(find.text('輪到你回'), findsOneWidget);
      expect(find.textContaining('解鎖'), findsNothing);
    });

    testWidgets('v2 對象沒有燈號訊號：照舊只有階段', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PartnerMindMapEntryCard(map: _fullMap(), onTap: () {}),
        ),
      ));
      expect(
          find.byKey(const ValueKey('mind-map-entry-v3-status')), findsNothing);
      expect(find.text('💫 建立男女感'), findsOneWidget);
    });
  });
}
