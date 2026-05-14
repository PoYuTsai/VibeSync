import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';

void main() {
  test('handoff URL drops partnerId when entry was partner-less', () {
    expect(
      OpeningRescueScreen.handoffLocationFor(),
      '/new?source=opener',
    );
    expect(
      OpeningRescueScreen.handoffLocationFor(partnerId: ''),
      '/new?source=opener',
    );
    expect(
      OpeningRescueScreen.handoffLocationFor(partnerId: '   '),
      '/new?source=opener',
    );
  });

  test('handoff URL carries partnerId when bound to a partner', () {
    final location =
        OpeningRescueScreen.handoffLocationFor(partnerId: 'partner-123');
    final uri = Uri.parse(location);
    expect(uri.path, '/new');
    expect(uri.queryParameters['source'], 'opener');
    expect(uri.queryParameters['partnerId'], 'partner-123');
  });
}
