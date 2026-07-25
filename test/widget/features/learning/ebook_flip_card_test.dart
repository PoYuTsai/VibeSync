// test/widget/features/learning/ebook_flip_card_test.dart
//
// 翻卡：翻面、reduced motion、semantics、大字級不裁字。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_flip_card.dart';

import '../../../helpers/ebook_test_content.dart';

/// 用 setSurfaceSize 真的把畫面縮到指定寬度，MediaQueryData.size 單獨改不會
/// 影響 layout 約束。
Future<void> pumpHost(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
  double textScale = 1.0,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(textScale),
        ),
        child: widget!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the front face first and flips to the analysis',
      (tester) async {
    await pumpHost(tester, EbookFlipCard(block: buildTestFlipCard()));

    expect(find.text('表面問題'), findsOneWidget);
    expect(find.text('點一下看解析'), findsOneWidget);
    expect(find.text('真正的瓶頸'), findsNothing);

    await tester.tap(find.text('表面問題'));
    await tester.pumpAndSettle();

    expect(find.text('真正的瓶頸'), findsOneWidget);
    expect(find.text('先修最前面的瓶頸。'), findsOneWidget);
    expect(find.text('點一下返回情境'), findsOneWidget);
    expect(find.text('表面問題'), findsNothing);
  });

  testWidgets('flips back to the scenario', (tester) async {
    await pumpHost(tester, EbookFlipCard(block: buildTestFlipCard()));

    await tester.tap(find.text('表面問題'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('真正的瓶頸'));
    await tester.pumpAndSettle();

    expect(find.text('表面問題'), findsOneWidget);
    expect(find.text('真正的瓶頸'), findsNothing);
  });

  testWidgets('reduced motion switches immediately without animating',
      (tester) async {
    await pumpHost(
      tester,
      EbookFlipCard(block: buildTestFlipCard()),
      disableAnimations: true,
    );

    await tester.tap(find.text('表面問題'));
    // 只 pump 一帧：reduced motion 下翻面必須已經完成，不留中間態。
    await tester.pump();

    expect(find.text('真正的瓶頸'), findsOneWidget);
    expect(find.text('表面問題'), findsNothing);

    // 再等動畫也不會改變結果（沒有旋轉動畫在跑）。
    await tester.pumpAndSettle();
    expect(find.text('真正的瓶頸'), findsOneWidget);
  });

  testWidgets('exposes a semantics label describing the next action',
      (tester) async {
    await pumpHost(tester, EbookFlipCard(block: buildTestFlipCard()));

    expect(
      find.bySemanticsLabel(RegExp('點兩下顯示解析')),
      findsOneWidget,
    );

    await tester.tap(find.text('表面問題'));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(RegExp('點兩下返回情境')),
      findsOneWidget,
    );
  });

  testWidgets('no overflow at 2.0 text scale on a 320px wide screen',
      (tester) async {
    await pumpHost(
      tester,
      EbookFlipCard(block: buildTestFlipCard()),
      textScale: 2.0,
      size: const Size(320, 900),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('表面問題'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
