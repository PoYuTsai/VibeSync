import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all formal Flutter logout entry points use the shared boundary', () {
    final supabaseSource = File(
      'lib/core/services/supabase_service.dart',
    ).readAsStringSync();
    final analysisSource = File(
      'lib/features/analysis/presentation/screens/analysis_screen.dart',
    ).readAsStringSync();
    final settingsSource = File(
      'lib/features/subscription/presentation/screens/settings_screen.dart',
    ).readAsStringSync();

    final purgeIndex = supabaseSource.indexOf(
      'KeyboardPrivacyPurgeService.live.purge(',
    );
    final authSignOutIndex = supabaseSource.indexOf(
      'await client.auth.signOut();',
      purgeIndex,
    );
    expect(purgeIndex, greaterThanOrEqualTo(0));
    expect(authSignOutIndex, greaterThan(purgeIndex));

    expect(analysisSource, contains('await SupabaseService.signOut();'));
    expect(
      analysisSource,
      contains('error is KeyboardPrivacyPurgeException ||'),
    );
    expect(
      settingsSource,
      contains('if (error is KeyboardPrivacyPurgeException)'),
    );
    expect(
      settingsSource,
      contains('return SupabaseService.signOut();'),
    );
    expect(
      settingsSource,
      isNot(
        contains(
          '.purge(KeyboardContextPurgeScope.logout)',
        ),
      ),
    );
  });

  test('no feature bypasses SupabaseService with direct auth sign-out', () {
    final featureFiles = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in featureFiles) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('client.auth.signOut(')),
        reason: '${file.path} bypasses the shared keyboard privacy purge',
      );
    }
  });
}
