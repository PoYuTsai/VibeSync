import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vibesync/core/services/revenuecat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('purchases_flutter');

  const targetPackage = Package(
    'essential_monthly',
    PackageType.custom,
    StoreProduct(
      'vibesync_essential:monthly',
      'Essential monthly',
      'Essential monthly',
      1290,
      r'$1290',
      'TWD',
    ),
    PresentedOfferingContext('default', null, null),
  );

  final purchaseResponse = <String, dynamic>{
    'customerInfo': {
      'entitlements': {
        'all': <String, dynamic>{},
        'active': <String, dynamic>{},
        'verification': 'NOT_REQUESTED',
      },
      'allPurchaseDates': <String, dynamic>{},
      'activeSubscriptions': <String>[],
      'allPurchasedProductIdentifiers': <String>[],
      'nonSubscriptionTransactions': <Map<String, dynamic>>[],
      'firstSeen': '2026-08-24T00:00:00.000Z',
      'originalAppUserId': 'android-test-user',
      'allExpirationDates': <String, dynamic>{},
      'requestDate': '2026-08-24T00:00:00.000Z',
      'latestExpirationDate': null,
      'originalPurchaseDate': null,
      'originalApplicationVersion': null,
      'managementURL': null,
    },
    'transaction': {
      'transactionIdentifier': 'transaction-1',
      'productIdentifier': 'vibesync_essential:monthly',
      'purchaseDate': '2026-08-24T00:00:00.000Z',
    },
  };

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    RevenueCatService.debugResetForTesting();
  });

  test('purchase serializes Android replacement product and proration mode',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'setLogLevel':
        case 'setupPurchases':
          return null;
        case 'purchasePackage':
          return purchaseResponse;
      }
      return null;
    });

    RevenueCatService.debugIsAndroidPlatformOverride = true;
    RevenueCatService.debugAndroidPublicSdkKeyOverride = 'goog_test_public_key';
    await RevenueCatService.initialize(appUserId: 'android-test-user');

    await RevenueCatService.purchase(
      targetPackage,
      googleProductChangeInfo: GoogleProductChangeInfo(
        'vibesync_starter',
        prorationMode: GoogleProrationMode.immediateAndChargeProratedPrice,
      ),
    );
    await RevenueCatService.purchase(
      targetPackage,
      googleProductChangeInfo: GoogleProductChangeInfo(
        'vibesync_essential',
        prorationMode: GoogleProrationMode.deferred,
      ),
    );
    await RevenueCatService.purchase(
      targetPackage,
      googleProductChangeInfo: GoogleProductChangeInfo(
        'vibesync_essential',
        prorationMode: GoogleProrationMode.immediateWithoutProration,
      ),
    );

    final purchaseCalls = calls
        .where((call) => call.method == 'purchasePackage')
        .toList(growable: false);
    expect(purchaseCalls, hasLength(3));

    Map<String, dynamic> argsFor(int index) =>
        Map<String, dynamic>.from(purchaseCalls[index].arguments as Map);

    expect(argsFor(0), containsPair('packageIdentifier', 'essential_monthly'));
    expect(
      argsFor(0),
      containsPair('googleOldProductIdentifier', 'vibesync_starter'),
    );
    expect(argsFor(0), containsPair('googleProrationMode', 2));

    expect(
      argsFor(1),
      containsPair('googleOldProductIdentifier', 'vibesync_essential'),
    );
    expect(argsFor(1), containsPair('googleProrationMode', 6));

    expect(
      argsFor(2),
      containsPair('googleOldProductIdentifier', 'vibesync_essential'),
    );
    expect(argsFor(2), containsPair('googleProrationMode', 3));
  });
}
