import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app dropped iOS emoji for Tabler icons on 2026-08-17
/// (lib/core/theme/app_icons.dart). The keyboard is the same product on a
/// smaller surface, so it draws the same Tabler glyphs instead of falling back
/// to the system emoji font, and each reply style keeps the glyph the app
/// gives it.
void main() {
  final appIcons = File('lib/core/theme/app_icons.dart');
  final replyStyles = File('ios/VibeSyncKeyboard/KeyboardAPI.swift');

  test('each reply style shows the glyph the app gives it', () {
    final glyphs = {
      for (final match in RegExp(
        r"'(\w+)': TablerIcons\.(\w+),",
      ).allMatches(appIcons.readAsStringSync()))
        match[1]!: match[2]!,
    };
    expect(
      glyphs.keys,
      unorderedEquals(['extend', 'resonate', 'tease', 'humor', 'coldRead']),
    );

    final swift = replyStyles.readAsStringSync();
    final start = swift.indexOf('var icon: KeyboardIcon {');
    expect(start, greaterThanOrEqualTo(0));
    final mapping = swift.substring(start);
    for (final entry in glyphs.entries) {
      // TablerIcons.message_circle is KeyboardIcon.messageCircle.
      final glyph = entry.value.replaceAllMapped(
        RegExp(r'_(\w)'),
        (match) => match[1]!.toUpperCase(),
      );
      expect(
        mapping,
        contains('case .${entry.key}: return .$glyph'),
        reason: entry.key,
      );
    }
  });

  test('the keyboard draws its glyphs instead of system emoji', () {
    // The lint checks the pattern without the unicode flag; with it, \p{…}
    // is a valid property escape.
    // ignore: valid_regexps
    final emoji = RegExp(r'\p{Extended_Pictographic}', unicode: true);
    final sources = Directory('ios/VibeSyncKeyboard')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.swift'))
        .toList();
    expect(sources, isNotEmpty);

    for (final file in sources) {
      final found = emoji
          .allMatches(file.readAsStringSync())
          .map((match) => match[0])
          .toSet();
      expect(found, isEmpty, reason: file.path);
    }
  });
}
