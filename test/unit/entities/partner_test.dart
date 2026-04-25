import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_entity');
    Hive.registerAdapter(PartnerAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
  });

  group('Partner Hive round-trip', () {
    test('serializes and deserializes all fields', () async {
      final box = await Hive.openBox<Partner>('partner_rt_test');
      addTearDown(() async => box.deleteFromDisk());

      final now = DateTime(2026, 4, 25, 18, 30);
      final p = Partner(
        id: 'p-abc',
        name: '糖糖',
        avatarPath: '/tmp/avatar.png',
        createdAt: now,
        updatedAt: now,
        ownerUserId: 'user-1',
        customNote: '永春附近',
      );
      await box.put(p.id, p);

      final read = box.get(p.id)!;
      expect(read.id, 'p-abc');
      expect(read.name, '糖糖');
      expect(read.avatarPath, '/tmp/avatar.png');
      expect(read.createdAt, now);
      expect(read.updatedAt, now);
      expect(read.ownerUserId, 'user-1');
      expect(read.customNote, '永春附近');
    });
  });
}
