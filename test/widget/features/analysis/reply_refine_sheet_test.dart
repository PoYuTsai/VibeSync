import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/widgets/reply_refine_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Finder _quick(String instruction) =>
    find.byKey(ValueKey('reply-refine-quick-$instruction'));

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  Future<void> pumpSheet(
    WidgetTester tester, {
    required ReplyRefineRequest onRefine,
    int? freeRemaining,
    String originalText = '這週要不要一起喝杯咖啡？',
    String? restoredText,
    String? restoredRequestId,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _wrap(
        ReplyRefineSheet(
          originalText: originalText,
          onRefine: onRefine,
          freeRemaining: freeRemaining,
          restoredText: restoredText,
          restoredRequestId: restoredRequestId,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('快捷指令調完會堆一個新版本，並以新版本為下一輪的原句', (tester) async {
    final seenTexts = <String>[];
    await pumpSheet(
      tester,
      freeRemaining: 4,
      onRefine: ({required currentText, required instruction}) async {
        seenTexts.add(currentText);
        return ReplyRefineOutcome(
          refinedText: '調過第 ${seenTexts.length} 次：$instruction',
          freeRemaining: 4 - seenTexts.length,
          requestId: 'req-${seenTexts.length}',
        );
      },
    );

    expect(find.text('今天還有 4 次免費微調。'), findsOneWidget);

    await tester.tap(_quick('短一點'));
    await tester.pumpAndSettle();

    expect(find.text('調過第 1 次：短一點'), findsWidgets);
    expect(find.text('今天還有 3 次免費微調。'), findsOneWidget);
    expect(find.byKey(const ValueKey('reply-refine-version-1')), findsOneWidget);

    // 迭代：第二次要調的是上一輪的結果，不是最初的原句。
    // debounce 用真實時鐘擋連點，所以這裡要真的等過那個窗。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 700)),
    );
    await tester.pumpAndSettle();
    await tester.tap(_quick('白話一點'));
    await tester.pumpAndSettle();

    expect(seenTexts, ['這週要不要一起喝杯咖啡？', '調過第 1 次：短一點']);
  });

  testWidgets('送出中鎖住輸入，連點不會送出第二次', (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    await pumpSheet(
      tester,
      onRefine: ({required currentText, required instruction}) async {
        calls += 1;
        await gate.future;
        return const ReplyRefineOutcome(refinedText: '調過了');
      },
    );

    await tester.tap(_quick('短一點'));
    await tester.pump();
    await tester.tap(_quick('短一點'), warnIfMissed: false);
    await tester.tap(_quick('換個說法'), warnIfMissed: false);
    await tester.pump();

    expect(calls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('調過了'), findsWidgets);
  });

  testWidgets('免費次數用完要在動手前就講清楚接下來會扣', (tester) async {
    await pumpSheet(
      tester,
      freeRemaining: 0,
      onRefine: ({required currentText, required instruction}) async => null,
    );

    expect(find.text('今天的免費次數用完了，接下來每次微調使用 1 則。'), findsOneWidget);
  });

  testWidgets('還沒問過 server 時只講免費上限，不謊報剩餘次數', (tester) async {
    await pumpSheet(
      tester,
      onRefine: ({required currentText, required instruction}) async => null,
    );

    expect(find.text('今天前 $kRefineFreeDailyLimit 次微調免費。'), findsOneWidget);
  });

  testWidgets('失敗只顯示訊息，不得多堆一個版本', (tester) async {
    await pumpSheet(
      tester,
      onRefine: ({required currentText, required instruction}) async {
        throw Exception('boom');
      },
    );

    await tester.tap(_quick('短一點'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reply-refine-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('reply-refine-version-1')), findsNothing);
  });

  testWidgets('自由指令長度上限與 server 對齊', (tester) async {
    await pumpSheet(
      tester,
      onRefine: ({required currentText, required instruction}) async => null,
    );

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('reply-refine-instruction')),
    );
    expect(field.maxLength, kMaxRefineInstructionLength);
  });

  testWidgets('快捷指令不得出現升溫或改變邀約方向的捷徑', (tester) async {
    for (final instruction in kRefineQuickInstructions) {
      expect(instruction.contains('撩'), isFalse);
      expect(instruction.contains('直接'), isFalse);
    }
  });

  testWidgets('接回 24 小時內的上一版：直接從那一版繼續調', (tester) async {
    final seenTexts = <String>[];
    await pumpSheet(
      tester,
      restoredText: '上次調到一半的版本',
      restoredRequestId: 'req-restored',
      onRefine: ({required currentText, required instruction}) async {
        seenTexts.add(currentText);
        return const ReplyRefineOutcome(refinedText: '再調過的');
      },
    );

    // 目前版本卡與版本列都標著同一個標籤。
    expect(find.text('上次調過的'), findsWidgets);
    expect(find.byKey(const ValueKey('reply-refine-version-1')), findsOneWidget);
    await tester.tap(_quick('短一點'));
    await tester.pumpAndSettle();
    expect(seenTexts, ['上次調到一半的版本']);
  });

  testWidgets('暫存的版本和原句一樣時不多堆一層', (tester) async {
    await pumpSheet(
      tester,
      originalText: '原句',
      restoredText: '  原句  ',
      onRefine: ({required currentText, required instruction}) async => null,
    );

    expect(find.byKey(const ValueKey('reply-refine-version-1')), findsNothing);
  });

  testWidgets('採用版本會把選中的那一版與其 requestId 一起帶回去', (tester) async {
    ReplyRefineSheetResult? result;
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showReplyRefineSheet(
                context,
                originalText: '原句',
                onRefine: ({required currentText, required instruction}) async =>
                    const ReplyRefineOutcome(
                  refinedText: '調過的句子',
                  requestId: 'req-1',
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(_quick('短一點'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reply-refine-adopt')));
    await tester.pumpAndSettle();

    expect(result?.adoptedText, '調過的句子');
    expect(result?.isRefined, isTrue);
    expect(result?.requestId, 'req-1');
  });
}
