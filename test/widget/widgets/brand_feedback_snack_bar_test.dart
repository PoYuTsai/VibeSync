import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/shared/widgets/brand/brand_feedback_snack_bar.dart';

void main() {
  testWidgets('brand feedback snackbar uses a white floating surface',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBrandFeedbackSnackBar(
                context,
                title: '已加入目前對話，共 14 則訊息',
                detail: '最後一則是她說，可以直接接著分析。',
                actionLabel: '捲到加入位置',
                onAction: () {},
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.behavior, SnackBarBehavior.floating);
    expect(snackBar.backgroundColor, Colors.white.withValues(alpha: 0.96));
    expect(snackBar.elevation, 0);
    expect(snackBar.shape, isA<RoundedRectangleBorder>());

    final title = tester.widget<Text>(find.text('已加入目前對話，共 14 則訊息'));
    expect(title.style?.color, AppColors.glassTextPrimary);

    final detail = tester.widget<Text>(find.text('最後一則是她說，可以直接接著分析。'));
    expect(detail.style?.color, AppColors.glassTextSecondary);

    final action = tester
        .widget<SnackBarAction>(find.widgetWithText(SnackBarAction, '捲到加入位置'));
    expect(action.textColor, AppColors.ctaEnd);
  });
}
