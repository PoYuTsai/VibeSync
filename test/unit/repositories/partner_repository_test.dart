import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';

void main() {
  late Box<Partner> box;
  late PartnerRepository repo;

  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_repo');
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(PartnerAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    box = await Hive.openBox<Partner>(
      'partners_repo_${DateTime.now().microsecondsSinceEpoch}',
    );
    repo = PartnerRepository(box: box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  test('upsertIfAbsent inserts new partner', () async {
    final now = DateTime(2026, 4, 25);
    final p = Partner(id: 'p-1', name: '糖糖', createdAt: now, updatedAt: now);

    final wrote = await repo.upsertIfAbsent(p);

    expect(wrote, isTrue);
    expect(box.get('p-1')?.name, '糖糖');
  });

  test('upsertIfAbsent is a no-op when partner already exists', () async {
    final now = DateTime(2026, 4, 25);
    final original = Partner(
        id: 'p-1', name: '糖糖', createdAt: now, updatedAt: now);
    await box.put('p-1', original);

    final wrote = await repo.upsertIfAbsent(
      Partner(id: 'p-1', name: 'OVERWRITE', createdAt: now, updatedAt: now),
    );

    expect(wrote, isFalse);
    expect(box.get('p-1')?.name, '糖糖'); // original preserved
  });

  test('getById returns stored partner or null', () async {
    final now = DateTime(2026, 4, 25);
    await box.put(
        'p-1', Partner(id: 'p-1', name: 'x', createdAt: now, updatedAt: now));
    expect(repo.getById('p-1')?.name, 'x');
    expect(repo.getById('missing'), isNull);
  });
}
