import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/presentation/widgets/draft_polish_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  Future<TextEditingController> pumpSheet(
    WidgetTester tester, {
    required DraftPolishRequest onPolish,
    void Function(String polishedText)? onCopy,
    String initialDraft = '',
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController(text: initialDraft);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _wrap(
        DraftPolishSheet(
          draftController: controller,
          onPolish: onPolish,
          onCopy: onCopy ?? (_) {},
          onRefine: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('空草稿送出鈕鎖住；有字才可送，成功後顯示結果與複製鈕', (tester) async {
    final polished = <String>[];
    await pumpSheet(
      tester,
      onPolish: (draft) async {
        polished.add(draft);
        return const OptimizedMessage(
          original: '原稿',
          optimized: '修好的版本',
          reason: '去掉壓迫感',
        );
      },
    );

    final submit = find.byKey(const ValueKey('draft-polish-submit'));
    expect(tester.widget<ElevatedButton>(submit).enabled, isFalse);
    expect(find.byKey(const ValueKey('draft-polish-copy')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('draft-polish-input')),
      '  今天要不要出來？  ',
    );
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    // 送給呼叫端的是 trim 過的草稿。
    expect(polished, ['今天要不要出來？']);
    expect(find.text('修好的版本'), findsOneWidget);
    expect(find.text('💡 去掉壓迫感'), findsOneWidget);
    expect(find.byKey(const ValueKey('draft-polish-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('draft-polish-refine')), findsOneWidget);
  });

  testWidgets('潤飾失敗（回 null）不畫結果，保留草稿可以再送', (tester) async {
    var calls = 0;
    final controller = await pumpSheet(
      tester,
      initialDraft: '第一版草稿',
      onPolish: (_) async {
        calls += 1;
        return null; // 呼叫端已用 snackbar 顯示失敗
      },
    );

    await tester.tap(find.byKey(const ValueKey('draft-polish-submit')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byKey(const ValueKey('draft-polish-result')), findsNothing);
    expect(find.byKey(const ValueKey('draft-polish-copy')), findsNothing);
    // 草稿由呼叫端 controller 持有，失敗不清空。
    expect(controller.text, '第一版草稿');
  });

  testWidgets('複製鈕把目前結果交給呼叫端', (tester) async {
    final copied = <String>[];
    await pumpSheet(
      tester,
      initialDraft: '草稿',
      onPolish: (_) async => const OptimizedMessage(
        original: '草稿',
        optimized: '潤飾結果',
        reason: '',
      ),
      onCopy: copied.add,
    );

    await tester.tap(find.byKey(const ValueKey('draft-polish-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('draft-polish-copy')));

    expect(copied, ['潤飾結果']);
  });
}
