import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

Partner _partner(String id, {String name = 'A', DateTime? at}) {
  final ts = at ?? DateTime(2026, 4, 28);
  return Partner(
    id: id,
    name: name,
    ownerUserId: 'u1',
    createdAt: ts,
    updatedAt: ts,
  );
}

void main() {
  late Box<Partner> box;
  late PartnerRepository repo;

  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_repo_update');
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(PartnerAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    box = await Hive.openBox<Partner>(
      'partners_update_${DateTime.now().microsecondsSinceEpoch}',
    );
    repo = PartnerRepository(box: box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  test('update persists new name and bumps updatedAt for an existing partner',
      () async {
    final original = _partner('p1', name: 'Alice', at: DateTime(2026, 4, 1));
    await box.put(original.id, original);
    final beforeUpdatedAt = box.get('p1')!.updatedAt;

    final renamed = _partner('p1', name: 'Alicia', at: DateTime(2026, 4, 1));
    await repo.update(renamed);

    final stored = box.get('p1');
    expect(stored, isNotNull);
    expect(stored!.name, 'Alicia');
    expect(stored.updatedAt.isAfter(beforeUpdatedAt), isTrue,
        reason: 'update must bump updatedAt to surface "recently changed" '
            'sort + cache busts');
  });

  test('update throws ArgumentError when partner id is missing', () async {
    final ghost = _partner('ghost', name: 'Ghost');

    expect(() => repo.update(ghost), throwsArgumentError);
  });

  test('update preserves createdAt and other fields', () async {
    final created = DateTime(2026, 1, 1);
    final original = Partner(
      id: 'p1',
      name: 'Alice',
      ownerUserId: 'u1',
      avatarPath: '/avatars/a.png',
      customNote: 'note',
      createdAt: created,
      updatedAt: created,
    );
    await box.put(original.id, original);

    final renamed = Partner(
      id: 'p1',
      name: 'Alicia',
      ownerUserId: 'u1',
      avatarPath: '/avatars/a.png',
      customNote: 'note',
      createdAt: created,
      updatedAt: created,
    );
    await repo.update(renamed);

    final stored = box.get('p1')!;
    expect(stored.createdAt, created,
        reason: 'createdAt is final; update must not silently rewrite it');
    expect(stored.avatarPath, '/avatars/a.png');
    expect(stored.customNote, 'note');
    expect(stored.ownerUserId, 'u1');
  });
}
