// test/widget/widgets/rate_limit_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/widgets/rate_limit_dialog.dart';

void main() {
  group('RateLimitDialog', () {
    testWidgets('shows minute limit message with retry countdown', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RateLimitDialog(
              type: RateLimitType.minute,
              retryAfter: 30,
            ),
          ),
        ),
      );

      expect(find.text('請稍後再試'), findsOneWidget);
      expect(find.text('30 秒後重試'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing); // No upgrade button for minute limit
    });

    testWidgets('shows daily limit message with upgrade button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RateLimitDialog(
              type: RateLimitType.daily,
            ),
          ),
        ),
      );

      expect(find.text('今日額度已用完'), findsOneWidget);
      expect(find.text('升級方案'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
    });

    testWidgets('shows monthly limit message with upgrade button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RateLimitDialog(
              type: RateLimitType.monthly,
            ),
          ),
        ),
      );

      expect(find.text('本月額度已用完'), findsOneWidget);
      expect(find.text('升級方案'), findsOneWidget);
    });

    testWidgets('dismiss button closes dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showRateLimitDialog(
                  context,
                  RateLimitType.daily,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('今日額度已用完'), findsOneWidget);

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();

      expect(find.text('今日額度已用完'), findsNothing);
    });
  });

  group('RateLimitTypeExtension', () {
    test('converts string to RateLimitType', () {
      expect('minute_limit'.toRateLimitType(), RateLimitType.minute);
      expect('daily_limit'.toRateLimitType(), RateLimitType.daily);
      expect('monthly_limit'.toRateLimitType(), RateLimitType.monthly);
      expect('invalid'.toRateLimitType(), isNull);
    });
  });
}
