import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_box');
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(PartnerAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test('Partner box persists across close+reopen', () async {
    final boxName = 'partners_test_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime(2026, 4, 25);

    var box = await Hive.openBox<Partner>(boxName);
    await box.put(
      'p-1',
      Partner(id: 'p-1', name: '糖糖', createdAt: now, updatedAt: now),
    );
    await box.close();

    box = await Hive.openBox<Partner>(boxName);
    expect(box.get('p-1')?.name, '糖糖');
    await box.deleteFromDisk();
  });
}
