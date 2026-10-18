import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/widgets/his_last_message_sheet.dart';

Future<bool?> _open(WidgetTester tester, Future<void> Function() act) async {
  bool? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async =>
              result = await showHisLastMessageSheet(context),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await act();
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('最後一則是你傳的（Eric 2026-10-18）：講先別回只用 1 則、還沒傳的改用幫我修', (tester) async {
    await _open(tester, () async {
      expect(find.text(hisLastMessageSheetTitle), findsOneWidget);
      expect(find.text('教練多半會建議你先等她回，這種結果只用 1 則。'), findsOneWidget);
      expect(
        find.text('還沒傳出去的話：長按這則刪掉再分析，分析完用「幫我修」改它。'),
        findsOneWidget,
      );
      expect(find.text('先不要'), findsOneWidget);
      expect(find.text('還是要分析'), findsOneWidget);
    });
  });

  testWidgets('還是要分析＝true；先不要＝false', (tester) async {
    expect(
      await _open(
        tester,
        () =>
            tester.tap(find.byKey(const ValueKey('his-last-message-proceed'))),
      ),
      isTrue,
    );
    expect(
      await _open(
        tester,
        () => tester.tap(find.byKey(const ValueKey('his-last-message-cancel'))),
      ),
      isFalse,
    );
  });

  testWidgets('點外面關掉也算先不要', (tester) async {
    expect(
      await _open(tester, () => tester.tapAt(const Offset(20, 20))),
      isFalse,
    );
  });
}
