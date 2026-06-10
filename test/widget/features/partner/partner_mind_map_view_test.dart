import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/partner/domain/mindmap/mind_map_models.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_mind_map_view.dart';

PartnerMindMap _map({String nextStepLabel = '約她週末喝咖啡'}) => PartnerMindMap(
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
            id: 'next',
            label: '下一步',
            branch: MindMapBranch.nextStep,
            children: [
              MindMapNode(
                  id: 'next-step',
                  label: nextStepLabel,
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

  testWidgets('下一步葉節點 chip 帶 CTA 橘色漸層', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PartnerMindMapView(map: _map()))),
    );
    await tester.pumpAndSettle();

    final container = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('約她週末喝咖啡'),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, [AppColors.ctaStart, AppColors.ctaEnd]);
  });

  testWidgets('parent rebuild 換新 map 時渲染新 graph（不殘留舊節點）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PartnerMindMapView(map: _map()))),
    );
    await tester.pumpAndSettle();
    expect(find.text('約她週末喝咖啡'), findsOneWidget);

    // 同一棵 widget tree、無 key，模擬 provider 觸發的 parent rebuild。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PartnerMindMapView(map: _map(nextStepLabel: '改約看展')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('改約看展'), findsOneWidget);
    expect(find.text('約她週末喝咖啡'), findsNothing);
  });
}
