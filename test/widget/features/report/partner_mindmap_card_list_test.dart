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
    expect(find.text('尚未分析'), findsOneWidget);
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
