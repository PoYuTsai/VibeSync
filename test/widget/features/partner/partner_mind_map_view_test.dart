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

  testWidgets('縮放平移後雙擊任意處重置回初始視圖', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PartnerMindMapView(map: _map()))),
    );
    await tester.pumpAndSettle();

    // 直接寫 controller 模擬用戶兩指縮小 + 平移後的卡住狀態。
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final controller = viewer.transformationController!;
    controller.value = Matrix4.translationValues(40, 60, 0)
      ..multiply(Matrix4.diagonal3Values(0.5, 0.5, 1.0));
    await tester.pump();
    expect(controller.value, isNot(equals(Matrix4.identity())));

    // 雙擊 = 兩次 tap，間隔落在 kDoubleTapMinTime 與 kDoubleTapTimeout 之間。
    await tester.tap(find.byType(InteractiveViewer), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(InteractiveViewer), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(controller.value, equals(Matrix4.identity()));
  });

  testWidgets('已在初始視圖時雙擊不觸發動畫（無拋錯、transform 不變）',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PartnerMindMapView(map: _map()))),
    );
    await tester.pumpAndSettle();

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final controller = viewer.transformationController!;

    await tester.tap(find.byType(InteractiveViewer), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(InteractiveViewer), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(controller.value, equals(Matrix4.identity()));
  });

  group('nextStep 葉節點單擊 → onNextStepTap（決策 3：只有葉節點可點）', () {
    testWidgets('單擊葉節點 → callback 收到節點文字', (tester) async {
      String? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PartnerMindMapView(
              map: _map(),
              onNextStepTap: (label) => tapped = label,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('約她週末喝咖啡'));
      // 與背景雙擊偵測並存：單擊要等雙擊 timeout（~300ms）競技場裁決。
      await tester.pump(const Duration(milliseconds: 400));
      expect(tapped, '約她週末喝咖啡');
    });

    testWidgets('「下一步」父標籤節點與其他枝節點不可點', (tester) async {
      String? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PartnerMindMapView(
              map: _map(),
              onNextStepTap: (label) => tapped = label,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('下一步'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('💫 建立男女感'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tapped, isNull);
    });

    testWidgets('callback 為 null（無可導航對話）→ 葉節點點了不 crash、無問教練 affordance',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: PartnerMindMapView(map: _map()))),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('約她週末喝咖啡'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.forum_outlined), findsNothing);
    });

    testWidgets('可點葉節點帶問教練 icon affordance + Semantics button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PartnerMindMapView(map: _map(), onNextStepTap: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
      final semantics = tester.getSemantics(find.text('約她週末喝咖啡'));
      expect(semantics.flagsCollection.isButton, isTrue);
    });
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
