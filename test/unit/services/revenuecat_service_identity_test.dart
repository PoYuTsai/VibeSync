import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/services/revenuecat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('purchases_flutter');

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
}
