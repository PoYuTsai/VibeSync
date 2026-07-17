// This is a basic Flutter widget test.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/app/app.dart';
import 'package:vibesync/core/config/environment.dart';
import 'package:vibesync/core/services/supabase_service.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/follow_up_notification/data/providers/follow_up_notification_service.dart';

import 'features/follow_up_notification/fake_notification_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SupabaseService.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  });

  testWidgets('App should render VibeSync text', (WidgetTester tester) async {
    // Build our app wrapped in ProviderScope with mocked providers
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationsProvider.overrideWithValue([]),
          notificationGatewayProvider.overrideWithValue(
            FakeNotificationGateway(),
          ),
        ],
        child: const App(),
      ),
    );

    // Verify that our app shows VibeSync text.
    expect(find.text('VibeSync'), findsOneWidget);

    // Dispose the app before the splash completes. The splash checks `mounted`
    // after its first delayed callback, so advancing that first timer is enough
    // to let the async sequence exit without entering the Supabase-backed router.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  });
}
