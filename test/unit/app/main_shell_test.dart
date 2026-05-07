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
}
