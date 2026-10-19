import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/report/presentation/widgets/partner_mindmap_card_list.dart';

Partner _partner(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      ownerUserId: 'u-1',
    );

String _stageAssetName(WidgetTester tester, String partnerId) {
  final image = tester.widget<Image>(
    find.byKey(ValueKey('partner-stage-image-$partnerId')),
  );
  return (image.image as AssetImage).assetName;
}

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
    expect(find.text('升溫'), findsOneWidget);
    expect(find.text('💫 建立男女感'), findsNothing);
    expect(find.text('尚未分析'), findsOneWidget);
    expect(
      _stageAssetName(tester, 'p1'),
      'assets/images/partner_stage_premise.webp',
    );
    expect(
      _stageAssetName(tester, 'p2'),
      'assets/images/partner_stage_unknown.webp',
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('partner-identity-dot-p1'))),
      const Size.square(9),
    );
    await tester.tap(find.text('Vivi'));
    expect(tappedId, 'p1');
  });

  testWidgets('五階段標籤各自對應 3D 圖像，未知標籤安全降級', (tester) async {
    const labels = <String, String>{
      'opening': '破冰階段',
      'premise': '建立男女感',
      'qualification': '互相評估',
      'narrative': '展現個人魅力',
      'close': '準備邀約',
      'unknown': '無法識別的階段',
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerMindMapCardList(
          partners: labels.keys.map((id) => _partner(id, id)).toList(),
          stageLabelOf: (id) => labels[id],
          onTapPartner: (_) {},
        ),
      ),
    ));

    for (final stage in const [
      'opening',
      'premise',
      'qualification',
      'narrative',
      'close',
    ]) {
      expect(
        _stageAssetName(tester, stage),
        'assets/images/partner_stage_$stage.webp',
      );
    }
    expect(
      _stageAssetName(tester, 'unknown'),
      'assets/images/partner_stage_unknown.webp',
    );
    for (final shortLabel in const [
      '破冰',
      '升溫',
      '深入',
      '連結',
      '邀約',
    ]) {
      expect(find.text(shortLabel), findsOneWidget);
    }
    expect(find.text('無法識別的階段'), findsNothing);
    expect(find.text('尚未分析'), findsOneWidget);
  });

  testWidgets('重新連線保留伴侶文案，仍使用同一顆冰塊', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PartnerMindMapCardList(
          partners: [_partner('reconnect', '伴侶')],
          stageLabelOf: (_) => '重新連線',
          onTapPartner: (_) {},
        ),
      ),
    ));

    expect(find.text('重新連線'), findsOneWidget);
    expect(
      _stageAssetName(tester, 'reconnect'),
      'assets/images/partner_stage_opening.webp',
    );
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
  group('物件加燈號（Bruce 2026-10-19 路線二，B1）', () {
    const green = PartnerGuideV3Signals(
      decision: GuideV3Decision.send,
      light: GuideV3Light.green,
    );
    const yellowHold = PartnerGuideV3Signals(
      decision: GuideV3Decision.hold,
      light: GuideV3Light.yellow,
    );
    const redStop = PartnerGuideV3Signals(
      decision: GuideV3Decision.stop,
      light: GuideV3Light.red,
    );

    Future<void> pump(
      WidgetTester tester, {
      required Map<String, String?> stages,
      required Map<String, PartnerGuideV3Signals?> signals,
    }) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 600,
                child: PartnerMindMapCardList(
                  partners: [
                    for (final id in stages.keys) _partner(id, id),
                  ],
                  stageLabelOf: (id) => stages[id],
                  guideV3SignalsOf: (id) => signals[id],
                  onTapPartner: (_) {},
                ),
              ),
            ),
          ),
        ));

    testWidgets('v3 有階段：3D 物件＋階段，下面一顆小燈＋短狀態；字跟首頁對象卡一樣', (tester) async {
      await pump(
        tester,
        stages: {'an': '建立男女感', 'qing': '互相評估', 'mia': '準備邀約'},
        signals: {'an': green, 'qing': yellowHold, 'mia': redStop},
      );

      expect(
        _stageAssetName(tester, 'an'),
        'assets/images/partner_stage_premise.webp',
      );
      expect(find.text('升溫'), findsOneWidget);
      for (final (id, status) in [
        ('an', '輪到你回'),
        ('qing', '先等她'),
        ('mia', '先停'),
      ]) {
        final row = find.byKey(ValueKey('partner-stage-status-$id'));
        expect(find.descendant(of: row, matching: find.text(status)),
            findsOneWidget,
            reason: id);
      }
      expect(find.text('尚未分析'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('改版前分析、沒有階段的 v3：物件的位置放燈號，不再說尚未分析', (tester) async {
      await pump(
        tester,
        stages: {'an': null, 'never': null},
        signals: {'an': green},
      );

      expect(
          find.byKey(const ValueKey('partner-stage-lamp-an')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('partner-stage-image-an')), findsNothing);
      expect(find.byKey(const ValueKey('partner-stage-status-an')),
          findsOneWidget);
      expect(find.text('輪到你回'), findsOneWidget);
      // 從沒分析過的照舊是問號與尚未分析。
      expect(
        _stageAssetName(tester, 'never'),
        'assets/images/partner_stage_unknown.webp',
      );
      expect(find.text('尚未分析'), findsOneWidget);
    });

    testWidgets('有燈號狀態的那一列才把卡加高；只有 v2 對象時卡片高度照舊', (tester) async {
      double tileHeight(String id) => tester
          .getSize(find
              .ancestor(
                of: find.byKey(ValueKey('partner-identity-dot-$id')),
                matching: find.byType(Container),
              )
              .first)
          .height;

      await pump(
        tester,
        stages: {'v2': '建立男女感'},
        signals: const {},
      );
      expect(tileHeight('v2'), 132);

      await pump(
        tester,
        stages: {'v2': '建立男女感', 'v3': '互相評估'},
        signals: {'v3': yellowHold},
      );
      expect(tileHeight('v2'), 152);
      expect(tileHeight('v3'), 152);
      expect(tester.takeException(), isNull);
    });

    testWidgets('關心沒有短狀態：有階段就照 v2 的樣子，沒有階段只放灰色的燈', (tester) async {
      const care = PartnerGuideV3Signals(decision: GuideV3Decision.care);
      await pump(
        tester,
        stages: {'staged': '建立男女感', 'bare': null},
        signals: {'staged': care, 'bare': care},
      );
      expect(find.byKey(const ValueKey('partner-stage-status-staged')),
          findsNothing);
      expect(find.byKey(const ValueKey('partner-stage-lamp-bare')),
          findsOneWidget);
      expect(find.text('尚未分析'), findsNothing);
    });
  });
}
