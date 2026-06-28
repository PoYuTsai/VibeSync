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

      expect(find.text('Message Booster'), findsOneWidget);
      expect(find.text('預覽即將推出的一次性加購包。'), findsOneWidget);
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

    testWidgets('shows coming soon notice and CTA', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('加購包即將推出，敬請期待。'), findsOneWidget);
      expect(find.text('Coming Soon'), findsOneWidget);
    });

    testWidgets('can preview different package', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Tap on large package
      await tester.tap(find.text('300 則'));
      await tester.pumpAndSettle();

      // The sheet remains a preview while booster purchase is coming soon.
      expect(find.text('Coming Soon'), findsOneWidget);
    });

    testWidgets('tapping coming soon button closes sheet', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Coming Soon'));
      await tester.pumpAndSettle();

      // Sheet should be closed
      expect(find.text('Message Booster'), findsNothing);
      expect(find.text('加購包即將推出，目前請先使用訂閱方案。'), findsOneWidget);
    });
  });

  group('showBoosterPurchaseSheet', () {
    testWidgets('returns null when coming soon CTA is tapped', (tester) async {
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

      // Select large and tap the disabled purchase preview CTA.
      await tester.tap(find.text('300 則'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Coming Soon'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('returns null when dismissed', (tester) async {
      BoosterPackage? result =
          BoosterPackage.small; // Set to non-null initially

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

      // Dismiss by dragging down.
      await tester.fling(
          find.text('Message Booster'), const Offset(0, 400), 500);
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });
}
