import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/subscription/domain/entities/message_booster.dart';
import 'package:vibesync/features/subscription/presentation/widgets/booster_purchase_sheet.dart';

void main() {
  Widget buildTestWidget() {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showBoosterPurchaseSheet(context);
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );
  }

  group('BoosterPurchaseSheet', () {
    testWidgets('displays title', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('加購訊息包'), findsOneWidget);
      expect(find.text('額度不夠用？立即加購'), findsOneWidget);
    });

    testWidgets('shows all package options', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('50 則'), findsOneWidget);
      expect(find.text('150 則'), findsOneWidget);
      expect(find.text('300 則'), findsOneWidget);
    });

    testWidgets('shows prices for all packages', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('NT\$39'), findsOneWidget);
      expect(find.text('NT\$99'), findsOneWidget);
      expect(find.text('NT\$179'), findsOneWidget);
    });

    testWidgets('shows savings badges for discounted packages', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('省 15%'), findsOneWidget);
      expect(find.text('省 23%'), findsOneWidget);
    });

    testWidgets('medium package is selected by default', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Check purchase button shows medium package
      expect(find.text('購買 150 則 - NT\$99'), findsOneWidget);
    });

    testWidgets('can select different package', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Tap on large package
      await tester.tap(find.text('300 則'));
      await tester.pumpAndSettle();

      // Button should update
      expect(find.text('購買 300 則 - NT\$179'), findsOneWidget);
    });

    testWidgets('tapping purchase button closes sheet', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Tap purchase button
      await tester.tap(find.text('購買 150 則 - NT\$99'));
      await tester.pumpAndSettle();

      // Sheet should be closed
      expect(find.text('加購訊息包'), findsNothing);
    });
  });

  group('showBoosterPurchaseSheet', () {
    testWidgets('returns selected package on purchase', (tester) async {
      BoosterPackage? result;

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showBoosterPurchaseSheet(context);
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Select large and purchase
      await tester.tap(find.text('300 則'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('購買 300 則 - NT\$179'));
      await tester.pumpAndSettle();

      expect(result, BoosterPackage.large);
    });

    testWidgets('returns null when dismissed', (tester) async {
      BoosterPackage? result = BoosterPackage.small; // Set to non-null initially

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showBoosterPurchaseSheet(context);
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Dismiss by tapping outside (drag down)
      await tester.fling(find.text('加購訊息包'), const Offset(0, 400), 500);
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });
}
