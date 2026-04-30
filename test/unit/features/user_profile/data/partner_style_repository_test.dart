import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  late Directory tmp;
  late Box<PartnerStyleOverride> box;
  late PartnerStyleRepository repo;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(PartnerStyleOverrideAdapter().typeId)) {
      Hive.registerAdapter(PartnerStyleOverrideAdapter());
    }
    if (!Hive.isAdapterRegistered(InteractionStyleAdapter().typeId)) {
      Hive.registerAdapter(InteractionStyleAdapter());
    }
    if (!Hive.isAdapterRegistered(PracticeGoalAdapter().typeId)) {
      Hive.registerAdapter(PracticeGoalAdapter());
    }
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('partner_style_repo_test');
    Hive.init(tmp.path);
    box = await Hive.openBox<PartnerStyleOverride>(
      'test_pso_${DateTime.now().microsecondsSinceEpoch}',
    );
    repo = PartnerStyleRepository(box: box);
  });

  tearDown(() async {
    await box.close();
    await tmp.delete(recursive: true);
  });

  final ts = DateTime.utc(2026, 5, 1);

  test('load() returns null when partner has no override', () async {
    expect(await repo.load('p1'), isNull);
  });

  test('save() then load() round-trips for the same partnerId', () async {
    final ov = PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.humorous,
      practiceGoals: const [PracticeGoal.softInvite],
      notes: '慢熟',
      updatedAt: ts,
    );
    await repo.save(ov);
    final loaded = await repo.load('p1');
    expect(loaded?.partnerId, 'p1');
    expect(loaded?.interactionStyle, InteractionStyle.humorous);
    expect(loaded?.practiceGoals, [PracticeGoal.softInvite]);
    expect(loaded?.notes, '慢熟');
  });

  test('save() with isEmpty override deletes the row instead of writing it',
      () async {
    final filled = PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.steady,
      updatedAt: ts,
    );
    await repo.save(filled);
    expect(await repo.load('p1'), isNotNull);

    final empty = PartnerStyleOverride.create(
      partnerId: 'p1',
      updatedAt: ts,
    );
    await repo.save(empty);

    expect(await repo.load('p1'), isNull);
  });

  test('delete() removes the row for that partnerId', () async {
    await repo.save(PartnerStyleOverride.create(
      partnerId: 'p2',
      interactionStyle: InteractionStyle.gentle,
      updatedAt: ts,
    ));
    await repo.delete('p2');
    expect(await repo.load('p2'), isNull);
  });

  test('clearAll() empties the box', () async {
    await repo.save(PartnerStyleOverride.create(
      partnerId: 'p3',
      interactionStyle: InteractionStyle.direct,
      updatedAt: ts,
    ));
    await repo.save(PartnerStyleOverride.create(
      partnerId: 'p4',
      interactionStyle: InteractionStyle.playful,
      updatedAt: ts,
    ));
    await repo.clearAll();
    expect(box.isEmpty, isTrue);
  });

  test('partners do not leak overrides across each other', () async {
    await repo.save(PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.humorous,
      updatedAt: ts,
    ));
    await repo.save(PartnerStyleOverride.create(
      partnerId: 'p2',
      interactionStyle: InteractionStyle.gentle,
      updatedAt: ts,
    ));
    expect((await repo.load('p1'))?.interactionStyle, InteractionStyle.humorous);
    expect((await repo.load('p2'))?.interactionStyle, InteractionStyle.gentle);
  });
}
