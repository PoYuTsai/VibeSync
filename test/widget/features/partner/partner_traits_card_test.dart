import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_traits_card.dart';

void main() {
  testWidgets('舊自由文字保留在本機但畫面明示未提供給 AI', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PartnerTraitsCard(
            view: PartnerAggregateView.empty(),
            customNote: '想約出來見面',
          ),
        ),
      ),
    );

    expect(find.text('想約出來見面'), findsNothing);
    expect(
      find.text('有一段舊版背景尚未套用；請到設定重新選擇後再提供給 AI。'),
      findsOneWidget,
    );
  });

  testWidgets('安全 chips 顯示 canonical 值，舊 alias 不外露', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PartnerTraitsCard(
            view: PartnerAggregateView.empty(),
            customNote: '異地、慢熱',
          ),
        ),
      ),
    );

    expect(find.text('你的設定'), findsOneWidget);
    expect(find.text('住不同縣市、慢熱'), findsOneWidget);
    expect(find.text('異地、慢熱'), findsNothing);
  });
}
