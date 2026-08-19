import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/presentation/dialogs/partner_settings_dialog.dart';

// 2026-08-19 Bruce dogfood：備註快速插入 chips。鎖三件事：
// 點 chip 附加片語（用「、」串接）、同片語不重複塞、已插入 chip 顯示打勾態。
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

  testWidgets('備註已含片語時 chip 呈打勾態且不重複插入', (tester) async {
    await pumpDialog(tester, note: '喜歡潛水、慢熱');

    // 打勾 icon 出現在已插入的 chip 上。
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('慢熱'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, '喜歡潛水、慢熱'); // 沒有變成兩份。
  });
}
