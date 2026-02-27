import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/presentation/screens/paywall_screen.dart';

void main() {
  Widget buildTestWidget() {
    return const ProviderScope(
      child: MaterialApp(home: PaywallScreen()),
    );
  }

  group('PaywallScreen', () {
    testWidgets('displays title', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('升級方案'), findsOneWidget);
      expect(find.text('解鎖完整功能'), findsOneWidget);
    });

    testWidgets('displays subtitle', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('提升你的社交溝通能力'), findsOneWidget);
    });

    testWidgets('shows Starter plan', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Starter'), findsOneWidget);
      expect(find.text('NT\$149/月'), findsOneWidget);
    });

    testWidgets('shows Starter features', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('300 則訊息/月'), findsOneWidget);
      expect(find.text('每日 50 則上限'), findsOneWidget);
      expect(find.text('5 種回覆建議'), findsNWidgets(2)); // Both plans have this
    });

    testWidgets('shows Essential plan with recommended badge', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Essential'), findsOneWidget);
      expect(find.text('NT\$349/月'), findsOneWidget);
      expect(find.text('推薦'), findsOneWidget);
    });

    testWidgets('shows Essential exclusive features', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('1,000 則訊息/月'), findsOneWidget);
      expect(find.text('每日 150 則上限'), findsOneWidget);
      expect(find.text('對話健檢 (獨家)'), findsOneWidget);
      expect(find.text('Sonnet 優先模型'), findsOneWidget);
    });

    testWidgets('Essential is selected by default', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Check for radio button selection
      final essentialRadio = tester.widget<Radio<String>>(
        find.byWidgetPredicate(
          (widget) => widget is Radio<String> && widget.value == 'essential',
        ),
      );
      expect(essentialRadio.groupValue, 'essential');
    });

    testWidgets('can select Starter plan', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Initially Essential is selected
      final starterRadioBefore = tester.widget<Radio<String>>(
        find.byWidgetPredicate(
          (widget) => widget is Radio<String> && widget.value == 'starter',
        ),
      );
      expect(starterRadioBefore.groupValue, 'essential');

      // Tap on Starter card
      await tester.tap(find.text('Starter'));
      await tester.pumpAndSettle();

      // Now Starter should be selected
      final starterRadioAfter = tester.widget<Radio<String>>(
        find.byWidgetPredicate(
          (widget) => widget is Radio<String> && widget.value == 'starter',
        ),
      );
      expect(starterRadioAfter.groupValue, 'starter');
    });

    testWidgets('shows free trial CTA', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('開始 7 天免費試用'), findsOneWidget);
    });

    testWidgets('shows trial terms', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('試用結束後自動扣款，可隨時取消'), findsOneWidget);
    });

    testWidgets('shows legal links', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('使用條款'), findsOneWidget);
      expect(find.text('隱私權政策'), findsOneWidget);
      expect(find.text('恢復購買'), findsOneWidget);
    });

    testWidgets('tapping CTA shows snackbar', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      await tester.tap(find.text('開始 7 天免費試用'));
      await tester.pumpAndSettle();

      expect(find.text('RevenueCat 整合待實作'), findsOneWidget);
    });
  });
}
