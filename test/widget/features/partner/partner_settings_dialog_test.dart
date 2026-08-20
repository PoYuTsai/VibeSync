import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/presentation/dialogs/partner_settings_dialog.dart';

// 2026-08-19 Eric 拍板：備註手填關閉、chips-only。鎖四件事：
// 選 chips 存成「、」串接、再點取消、沒動 chips 時舊自由文字原樣保留、
// 動了 chips 舊自由文字被清洗（刻意行為，殺主詞污染源）。
void main() {
  Future<PartnerSettingsResult?> Function() pendingResult = () async => null;

  Future<void> pumpDialog(WidgetTester tester, {String note = ''}) async {
    late Future<PartnerSettingsResult?> resultFuture;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                resultFuture = showDialog<PartnerSettingsResult>(
                  context: context,
                  builder: (_) => PartnerSettingsDialog(
                    initialName: 'Jenny',
                    initialNote: note,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    pendingResult = () => resultFuture;
  }

  Future<PartnerSettingsResult?> save(WidgetTester tester) async {
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    return pendingResult();
  }

  testWidgets('chips 依關係、工作作息、地點距離、穩定生活分組', (tester) async {
    await pumpDialog(tester);

    expect(find.text('關係階段'), findsOneWidget);
    expect(find.text('工作／作息'), findsOneWidget);
    expect(find.text('地點／距離'), findsOneWidget);
    expect(find.text('穩定偏好／生活'), findsOneWidget);
    expect(find.text('工作忙碌'), findsOneWidget);
    expect(find.text('異地'), findsOneWidget);
  });

  testWidgets('選兩個 chips 儲存成「、」串接', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('慢熱'));
    await tester.pump();
    await tester.tap(find.text('剛認識'));
    await tester.pump();

    final result = await save(tester);
    expect(result!.note, '剛認識、慢熱');
  });

  testWidgets('既有片語顯示已選，再點一次取消', (tester) async {
    await pumpDialog(tester, note: '慢熱、剛認識');

    await tester.tap(find.text('慢熱'));
    await tester.pump();

    final result = await save(tester);
    expect(result!.note, '剛認識');
  });

  testWidgets('沒動 chips 時舊自由文字原樣保留（只改名）', (tester) async {
    await pumpDialog(tester, note: '想約出來見面');

    await tester.enterText(find.byType(TextField), 'Amy');
    await tester.pump();

    final result = await save(tester);
    expect(result!.name, 'Amy');
    expect(result.note, '想約出來見面'); // 沒碰 chips，不動舊資料。
  });

  testWidgets('動了 chips 後舊自由文字被清洗', (tester) async {
    await pumpDialog(tester, note: '想約出來見面、慢熱');

    await tester.tap(find.text('剛認識'));
    await tester.pump();

    final result = await save(tester);
    // 舊 chip 片語（慢熱）保留、自由句（想約出來見面）清掉。
    expect(result!.note, '剛認識、慢熱');
  });
}
