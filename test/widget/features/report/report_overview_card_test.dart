import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/widgets/report_overview_card.dart';

Future<void> _pump(
  WidgetTester tester, {
  required double averageScore,
  required int totalConversations,
  List<StageDistribution> stages = const [],
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ReportOverviewCard(
          averageScore: averageScore,
          totalConversations: totalConversations,
          stageDistributions: stages,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('多段對話快照 → 只描述現況，不出現回升／保守／穩定方向', (tester) async {
    // 來源是不同對象的最新快照，前後半平均差不是任何人的時間趨勢。
    await _pump(
      tester,
      averageScore: 61.4,
      totalConversations: 5,
      stages: const [
        StageDistribution(stageName: '破冰', count: 1),
        StageDistribution(stageName: '升溫', count: 3),
        StageDistribution(stageName: '深入', count: 1),
      ],
    );

    expect(find.text('整體摘要'), findsOneWidget);
    expect(find.text(ReportOverviewCard.headline), findsOneWidget);
    expect(find.text(ReportOverviewCard.subline), findsOneWidget);
    expect(find.text('5 個已分析對話'), findsOneWidget);
    expect(find.text('對話平均投入'), findsOneWidget);
    expect(find.text('61'), findsOneWidget); // round()
    expect(find.text('有效對話'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('常見階段'), findsOneWidget);
    expect(find.text('升溫'), findsOneWidget);

    for (final removed in ['回升', '放慢', '穩定', '轉為保守', '前後趨勢']) {
      expect(find.textContaining(removed), findsNothing, reason: removed);
    }
    expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
    expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
    expect(find.byIcon(Icons.trending_flat_rounded), findsNothing);
  });

  testWidgets('只有一段對話 → 不虛構趨勢；「有效對話」數的是對話', (tester) async {
    await _pump(
      tester,
      averageScore: 72,
      totalConversations: 1,
      stages: const [StageDistribution(stageName: '破冰', count: 1)],
    );

    expect(find.text(ReportOverviewCard.headline), findsOneWidget);
    expect(find.text('1 個已分析對話'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.textContaining('基準已建立'), findsNothing);
    expect(find.textContaining('對象'), findsOneWidget); // 只有副標提到「選一位對象」
  });

  testWidgets('無階段資料 → 常見階段顯示破折號，無障礙標籤只讀現況', (tester) async {
    await _pump(tester, averageScore: 0, totalConversations: 0);

    expect(find.text('—'), findsOneWidget);
    final semantics = tester.getSemantics(find.byType(ReportOverviewCard));
    expect(semantics.label, contains('目前的對話概況'));
    expect(semantics.label, contains('共 0 個已分析對話'));
    expect(semantics.label, isNot(contains('回升')));
    expect(semantics.label, isNot(contains('保守')));
  });
}
