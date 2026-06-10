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
