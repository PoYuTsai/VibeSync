import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/hive_registrar.g.dart';

/// Regression test for the 2026-08-04 About Me save failure: saving a
/// UserProfile with a non-empty stuckPoints list threw HiveError because
/// StorageService.initialize() registered adapters by hand and missed the
/// newly-added StuckPointAdapter (typeId=27). The fix routes registration
/// through the generated HiveRegistrar so every @HiveType stays covered.
void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_stuck_point_adapter');
    Hive.registerAdapters();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test('UserProfile with non-empty stuckPoints saves and round-trips',
      () async {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final box = await Hive.openBox<UserProfile>('stuck_point_wire_$ts');
    addTearDown(() async => box.deleteFromDisk());

    final profile = UserProfile.create(
      stuckPoints: const [StuckPoint.fadesOut, StuckPoint.leftOnRead],
      updatedAt: DateTime.utc(2026, 8, 4),
    );

    await box.put('me', profile);
    final restored = box.get('me')!;

    expect(restored.stuckPoints, profile.stuckPoints);
  });
}
