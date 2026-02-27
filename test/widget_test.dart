// This is a basic Flutter widget test.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibesync/app/app.dart';

void main() {
  testWidgets('App should render VibeSync text', (WidgetTester tester) async {
    // Build our app wrapped in ProviderScope and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: App(),
      ),
    );

    // Verify that our app shows VibeSync text.
    expect(find.text('VibeSync'), findsOneWidget);
  });
}
