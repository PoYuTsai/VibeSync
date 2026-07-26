// test/widget/features/learning/ebook_stage_funnel_test.dart
//
// 漏斗自我診斷：未選時不出診斷、點選後出診斷與跳章、換選會換診斷、
// 選取狀態不只靠顏色（有「你在這裡」文字）、窄螢幕與大字級都不 overflow。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_stage_funnel.dart';

import '../../../helpers/ebook_test_content.dart';

Future<List<EbookFunnelStage>> pumpFunnel(
  WidgetTester tester, {
  EbookStageFunnelBlock? block,
  double textScale = 1.0,
  Size size = const Size(390, 1400),
}) async {
  final taps = <EbookFunnelStage>[];
  // setSurfaceSize 才會真的改 layout 約束（只改 MediaQueryData.size 不會）。
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: EbookStageFunnelView(
              block: block ?? buildTestStageFunnel(),
              onOpenTarget: taps.add,
            ),
          ),
        ),
      ),
    ),
  );
  return taps;
}

void main() {
  testWidgets('未選任何一層時不顯示診斷，也沒有跳章按鈕', (tester) async {
    await pumpFunnel(tester);

    expect(find.text('你在漏斗的哪一層掉出去？'), findsOneWidget);
    expect(find.text('症狀 0'), findsOneWidget);
    expect(find.text('症狀 2'), findsOneWidget);
    expect(find.text('診斷'), findsNothing);
    expect(find.text('你卡在階段 0'), findsNothing);
    expect(find.text('前往目標 0'), findsNothing);
    expect(find.text(EbookStageFunnelView.youAreHereLabel), findsNothing);
  });

  testWidgets('點一層之後顯示該層診斷與跳章入口', (tester) async {
    await pumpFunnel(tester);

    await tester.tap(find.text('症狀 1'));
    await tester.pumpAndSettle();

    expect(find.text('診斷'), findsOneWidget);
    expect(find.text('你卡在階段 1'), findsOneWidget);
    expect(find.text('判斷內容 1。'), findsOneWidget);
    expect(find.text('前往目標 1'), findsOneWidget);
    // 選取不能只靠顏色表達。
    expect(find.text(EbookStageFunnelView.youAreHereLabel), findsOneWidget);
  });

  testWidgets('換選另一層會換掉診斷，不會兩個診斷同時在', (tester) async {
    await pumpFunnel(tester);

    await tester.tap(find.text('症狀 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('症狀 2'));
    await tester.pumpAndSettle();

    expect(find.text('你卡在階段 0'), findsNothing);
    expect(find.text('你卡在階段 2'), findsOneWidget);
    expect(find.text('診斷'), findsOneWidget);
    expect(find.text(EbookStageFunnelView.youAreHereLabel), findsOneWidget);
  });

  testWidgets('按跳章按鈕才回報目標，只點層不回報', (tester) async {
    final taps = await pumpFunnel(tester);

    await tester.tap(find.text('症狀 2'));
    await tester.pumpAndSettle();
    expect(taps, isEmpty, reason: '只是選一層不該直接跳走');

    await tester.tap(find.text('前往目標 2'));
    await tester.pumpAndSettle();

    expect(taps, hasLength(1));
    expect(taps.single.id, 'funnel-1-s2');
    expect(taps.single.targetChapterId, 'book-1-chapter-2');
  });

  testWidgets('每一層都有可讀的層號與階段名，不只靠寬度差異', (tester) async {
    await pumpFunnel(tester);

    for (var index = 0; index < 3; index++) {
      expect(find.text('$index'), findsOneWidget, reason: '缺層號 $index');
      expect(find.text('階段 · 測試 $index'), findsOneWidget);
    }
  });

  testWidgets('320 寬 + 1.5 倍字級：選取後仍不 overflow', (tester) async {
    await pumpFunnel(
      tester,
      textScale: 1.5,
      size: const Size(320, 2200),
    );

    await tester.tap(find.text('症狀 0'));
    await tester.pumpAndSettle();

    expect(find.text('你卡在階段 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跨書目標也照樣回報，導覽由呼叫端決定', (tester) async {
    final taps = await pumpFunnel(
      tester,
      block: buildTestStageFunnel(
        targetBookId: 'book-2',
        targetChapterId: 'book-2-chapter-1',
        stageCount: 2,
      ),
    );

    await tester.tap(find.text('症狀 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前往目標 1'));
    await tester.pumpAndSettle();

    expect(taps.single.targetBookId, 'book-2');
    expect(taps.single.targetChapterId, 'book-2-chapter-1');
  });
}
