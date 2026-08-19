import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/presentation/dialogs/partner_settings_dialog.dart';

// 2026-08-19 Bruce dogfood：備註快速插入 chips。鎖三件事：
// 點 chip 附加片語（用「、」串接）、同片語不重複塞、再點一次移除片語
//（toggle 對標「關於我」chips，Eric 拍板；選中態靠色差字重，無勾勾 icon）。
void main() {
  Future<void> pumpDialog(WidgetTester tester, {String note = ''}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<PartnerSettingsResult>(
                context: context,
                builder: (_) => PartnerSettingsDialog(
                  initialName: 'Jenny',
                  initialNote: note,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('點 chip 把片語塞進備註，第二個用「、」串接', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('慢熱'));
    await tester.pump();
    await tester.tap(find.text('剛認識'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, '慢熱、剛認識');
  });

  testWidgets('已插入的 chip 再點一次會移除片語並清掉頓號', (tester) async {
    await pumpDialog(tester, note: '喜歡潛水、慢熱');

    await tester.tap(find.text('慢熱'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, '喜歡潛水'); // 片語連同「、」一起拔掉。
  });
}
