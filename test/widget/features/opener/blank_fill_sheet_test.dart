import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/presentation/widgets/blank_fill_sheet.dart';

void main() {
  Future<String?> openSheet(WidgetTester tester, String text) async {
    String? result = 'not-closed';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showBlankFillSheet(context, text: text);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('先選好第一個空格；空格還在時不能複製、會提示還有＿＿沒填', (tester) async {
    await openSheet(tester, '我最近都在＿＿夜跑，妳都跑哪？');
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('blank-fill-field')),
    );
    final selection = field.controller!.selection;
    expect(
      field.controller!.text.substring(selection.start, selection.end),
      '＿＿',
    );
    expect(find.byKey(const ValueKey('blank-fill-blanks-left')), findsOneWidget);
    final copy = tester.widget<FilledButton>(
      find.byKey(const ValueKey('blank-fill-copy')),
    );
    expect(copy.onPressed, isNull);
  });

  testWidgets('填好空格才能複製，回傳去掉頭尾空白的句子', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showBlankFillSheet(
                context,
                text: '我最近都在＿＿夜跑，妳都跑哪？',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('blank-fill-field')),
      ' 我最近都在河濱夜跑，妳都跑哪？ ',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('blank-fill-blanks-left')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('blank-fill-copy')));
    await tester.pumpAndSettle();
    expect(result, '我最近都在河濱夜跑，妳都跑哪？');
  });

  testWidgets('清空也不能複製', (tester) async {
    await openSheet(tester, '我住＿＿附近');
    await tester.enterText(find.byKey(const ValueKey('blank-fill-field')), '  ');
    await tester.pump();
    final copy = tester.widget<FilledButton>(
      find.byKey(const ValueKey('blank-fill-copy')),
    );
    expect(copy.onPressed, isNull);
  });
}
