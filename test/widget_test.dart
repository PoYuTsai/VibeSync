// This is a basic Flutter widget test.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibesync/app/app.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';

void main() {
  testWidgets('App should render VibeSync text', (WidgetTester tester) async {
    // Build our app wrapped in ProviderScope with mocked providers
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationsProvider.overrideWithValue([]),
        ],
        child: const App(),
      ),
    );

    // Verify that our app shows VibeSync text.
    expect(find.text('VibeSync'), findsOneWidget);
  });
}
