import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/revenuecat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('purchases_flutter');
  final paidCustomerInfo = {
    'originalAppUserId': r'$RCAnonymousID:original',
    'entitlements': {
      'all': {},
      'active': {
        'premium': {
          'identifier': 'premium',
          'isActive': true,
          'willRenew': true,
          'latestPurchaseDate': '2026-06-06T00:00:00.000Z',
          'originalPurchaseDate': '2026-06-01T00:00:00.000Z',
          'productIdentifier': 'vibesync_essential_monthly_v2',
          'isSandbox': true,
          'ownershipType': 'PURCHASED',
          'store': 'APP_STORE',
          'periodType': 'NORMAL',
          'expirationDate': '2026-07-06T00:00:00.000Z',
          'unsubscribeDetectedAt': null,
          'billingIssueDetectedAt': null,
          'productPlanIdentifier': null,
          'verification': 'NOT_REQUESTED',
        },
      },
      'verification': 'NOT_REQUESTED',
    },
    'activeSubscriptions': ['vibesync_essential_monthly_v2'],
    'latestExpirationDate': '2026-07-06T00:00:00.000Z',
    'allExpirationDates': {
      'vibesync_essential_monthly_v2': '2026-07-06T00:00:00.000Z',
    },
    'allPurchasedProductIdentifiers': ['vibesync_essential_monthly_v2'],
    'firstSeen': '2026-06-01T00:00:00.000Z',
    'requestDate': '2026-06-06T00:00:00.000Z',
    'allPurchaseDates': {
      'vibesync_essential_monthly_v2': '2026-06-01T00:00:00.000Z',
    },
    'originalApplicationVersion': '1.0.0',
    'nonSubscriptionTransactions': [],
    'managementURL': 'https://apps.apple.com/account/subscriptions',
  };

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    RevenueCatService.debugResetForTesting();
  });

  test(
    'initializes with Supabase user id and does not create anonymous id on logout',
    () async {
      final calls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      RevenueCatService.debugIsIOSPlatformOverride = true;
      RevenueCatService.debugIosPublicSdkKeyOverride = 'appl_test_public_key';
      await RevenueCatService.initialize(appUserId: 'supabase-user-id');
      await RevenueCatService.logout();

      final setupCall = calls.firstWhere(
        (call) => call.method == 'setupPurchases',
      );
      final setupArgs = Map<String, Object?>.from(
        setupCall.arguments as Map<Object?, Object?>,
      );

      expect(setupArgs['appUserId'], 'supabase-user-id');
      expect(calls.map((call) => call.method), isNot(contains('logOut')));
    },
  );

  test('Android missing goog key does not configure with the iOS key',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    RevenueCatService.debugIsAndroidPlatformOverride = true;
    await RevenueCatService.initialize(appUserId: 'android-user');

    expect(calls.map((call) => call.method), isNot(contains('setupPurchases')));
    expect(RevenueCatService.isInitialized, isFalse);
  });

  test('debug snapshot exposes RevenueCat identity and paid entitlement',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'setupPurchases':
        case 'setLogLevel':
          return null;
        case 'getAppUserID':
          return 'supabase-user-id';
        case 'isAnonymous':
          return false;
        case 'getCustomerInfo':
          return paidCustomerInfo;
      }
      return null;
    });

    RevenueCatService.debugIsIOSPlatformOverride = true;
    RevenueCatService.debugIosPublicSdkKeyOverride = 'appl_test_public_key';
    await RevenueCatService.initialize(appUserId: 'supabase-user-id');

    final snapshot = await RevenueCatService.buildDebugSnapshot();
    final customerInfo = snapshot['customerInfo'] as Map<String, Object?>;

    expect(snapshot['currentAppUserId'], 'supabase-user-id');
    expect(snapshot['isAnonymous'], isFalse);
    expect(customerInfo['tier'], 'essential');
    expect(customerInfo['activeSubscriptions'],
        contains('vibesync_essential_monthly_v2'));
    expect(customerInfo['activeEntitlements'], contains('premium'));
  });

  test('does not read customer info when RevenueCat app user id mismatches',
      () async {
    var getCustomerInfoCalls = 0;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'setupPurchases':
        case 'setLogLevel':
          return null;
        case 'getAppUserID':
          return 'previous-user-id';
        case 'getCustomerInfo':
          getCustomerInfoCalls += 1;
          return paidCustomerInfo;
      }
      return null;
    });

    RevenueCatService.debugIsIOSPlatformOverride = true;
    RevenueCatService.debugIosPublicSdkKeyOverride = 'appl_test_public_key';
    await RevenueCatService.initialize(appUserId: 'current-user-id');

    final customerInfo = await RevenueCatService.getCustomerInfoForAppUserId(
      'current-user-id',
    );

    expect(customerInfo, isNull);
    expect(getCustomerInfoCalls, 0);
  });

  test('startup rescue does not sync purchases when app user id mismatches',
      () async {
    final calls = <String>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'setupPurchases':
        case 'setLogLevel':
          return null;
        case 'getAppUserID':
          return 'previous-user-id';
        case 'getCustomerInfo':
        case 'syncPurchases':
        case 'invalidateCustomerInfoCache':
          fail('must not use stale RevenueCat identity for startup rescue');
      }
      return null;
    });

    RevenueCatService.debugIsIOSPlatformOverride = true;
    RevenueCatService.debugIosPublicSdkKeyOverride = 'appl_test_public_key';
    await RevenueCatService.initialize(appUserId: 'current-user-id');

    final customerInfo =
        await RevenueCatService.syncPurchasesAndRefreshCustomerInfo(
      expectedAppUserId: 'current-user-id',
    );

    expect(customerInfo, isNull);
    expect(calls, isNot(contains('syncPurchases')));
    expect(calls, isNot(contains('getCustomerInfo')));
  });

  test('management URL stays on the authoritative original store', () {
    expect(
      RevenueCatService.validateManagementUrlForStore(
        'https://apps.apple.com/account/subscriptions',
        store: 'app_store',
      ),
      'https://apps.apple.com/account/subscriptions',
    );
    expect(
      RevenueCatService.validateManagementUrlForStore(
        'https://play.google.com/store/account/subscriptions',
        store: 'play_store',
      ),
      'https://play.google.com/store/account/subscriptions',
    );
    expect(
      RevenueCatService.validateManagementUrlForStore(
        'https://play.google.com/store/account/subscriptions',
        store: 'app_store',
      ),
      isNull,
    );
    expect(
      RevenueCatService.validateManagementUrlForStore(
        'https://apps.apple.com/account/subscriptions',
        store: 'play_store',
      ),
      isNull,
    );
    expect(
      RevenueCatService.validateManagementUrlForStore(
        'https://example.invalid/manage',
        store: 'play_store',
      ),
      isNull,
    );
  });
}
