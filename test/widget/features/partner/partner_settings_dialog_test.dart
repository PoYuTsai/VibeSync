import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/presentation/dialogs/partner_settings_dialog.dart';

// 2026-08-20：關於她只留六類 allowlisted chips。鎖 catalog 呈現、互斥、
// 舊 alias、未操作保留原值，以及一旦操作就清掉舊自由文字／關係狀態。
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

  Future<void> tapChip(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('chips 依六個安全面向分組，沒有關係進度', (tester) async {
    await pumpDialog(tester);

    expect(
      find.text('只選你確定、長期成立的；不確定就不要選。'),
      findsOneWidget,
    );
    expect(find.text('工作／學業'), findsOneWidget);
    expect(find.text('最多選 2 個'), findsOneWidget);
    expect(find.text('最多選 3 個'), findsNWidgets(4));
    expect(find.text('最多選 5 個'), findsOneWidget);
    expect(find.text('地點／距離'), findsOneWidget);
    expect(find.text('作息／生活'), findsOneWidget);
    expect(find.text('個性／互動'), findsOneWidget);
    expect(find.text('聊天偏好'), findsOneWidget);
    expect(find.text('興趣'), findsOneWidget);
    expect(find.text('工作忙碌'), findsOneWidget);
    expect(find.text('不想聊工作'), findsOneWidget);
    expect(find.text('喜歡寵物'), findsOneWidget);
    expect(find.text('關係階段'), findsNothing);
    expect(find.text('剛認識'), findsNothing);
  });

  testWidgets('分類選滿後停用未選 chips，已選 chips 仍可取消', (tester) async {
    await pumpDialog(tester);

    await tapChip(tester, '工作忙碌');
    await tapChip(tester, '輪班工作');

    final disabledInkWell = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('遠端工作'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    final selectedInkWell = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('工作忙碌'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(disabledInkWell.onTap, isNull);
    expect(selectedInkWell.onTap, isNotNull);
  });

  testWidgets('選兩個 chips 儲存成「、」串接', (tester) async {
    await pumpDialog(tester);

    await tapChip(tester, '慢熱');
    await tapChip(tester, '工作忙碌');

    final result = await save(tester);
    expect(result!.note, '工作忙碌、慢熱');
  });

  testWidgets('既有安全 alias 顯示 canonical 已選，再點一次取消', (tester) async {
    await pumpDialog(tester, note: '慢熱、異地');

    await tapChip(tester, '慢熱');

    final result = await save(tester);
    expect(result!.note, '住不同縣市');
  });

  testWidgets('互斥 chips 後選覆蓋前選', (tester) async {
    await pumpDialog(tester);

    await tapChip(tester, '住同縣市');
    await tapChip(tester, '住海外');

    final result = await save(tester);
    expect(result!.note, '住海外');
  });

  testWidgets('沒動 chips 時舊自由文字原樣保留（只改名）', (tester) async {
    await pumpDialog(tester, note: '想約出來見面');

    expect(
      find.text('舊版背景目前不會提供給 AI；重新選擇任一項並儲存後，舊內容會被清除。'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Amy');
    await tester.pump();

    final result = await save(tester);
    expect(result!.name, 'Amy');
    expect(result.note, '想約出來見面'); // 沒碰 chips，不動舊資料。
  });

  testWidgets('動了 chips 後舊自由文字被清洗', (tester) async {
    await pumpDialog(tester, note: '想約出來見面、剛認識、慢熱');

    await tapChip(tester, '喜歡寵物');

    final result = await save(tester);
    // 安全片語保留；自由句與關係狀態都清掉。
    expect(result!.note, '慢熱、喜歡寵物');
  });
}
