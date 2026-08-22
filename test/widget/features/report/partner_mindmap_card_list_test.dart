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
}
