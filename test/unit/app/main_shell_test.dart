import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/app/main_shell.dart';

void main() {
  group('MainShell.tabIndexFromRoute', () {
    test('maps explicit tab query values to shell indexes', () {
      expect(MainShell.tabIndexFromRoute('home'), 0);
      expect(MainShell.tabIndexFromRoute('report'), 1);
      expect(MainShell.tabIndexFromRoute('reports'), 1);
      expect(MainShell.tabIndexFromRoute('learn'), 2);
      expect(MainShell.tabIndexFromRoute('learning'), 2);
    });

    test('falls back to home for empty or unknown values', () {
      expect(MainShell.tabIndexFromRoute(null), 0);
      expect(MainShell.tabIndexFromRoute('unknown'), 0);
    });
  });

  group('MainShell.tabRouteFromIndex', () {
    test('maps shell indexes back to stable route tab query values', () {
      expect(MainShell.tabRouteFromIndex(0), 'home');
      expect(MainShell.tabRouteFromIndex(1), 'report');
      expect(MainShell.tabRouteFromIndex(2), 'learning');
    });

    test('falls back to home for out-of-range values', () {
      expect(MainShell.tabRouteFromIndex(-1), 'home');
      expect(MainShell.tabRouteFromIndex(99), 'home');
    });
  });
}
