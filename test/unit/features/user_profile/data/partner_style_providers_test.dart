import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
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
    tmp = await Directory.systemTemp.createTemp('partner_style_providers');
    Hive.init(tmp.path);
    box = await Hive.openBox<PartnerStyleOverride>(
      'pso_${DateTime.now().microsecondsSinceEpoch}',
    );
    repo = PartnerStyleRepository(box: box);
  });

  tearDown(() async {
    await box.close();
    await tmp.delete(recursive: true);
  });

  ProviderContainer makeContainer() => ProviderContainer(overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(repo),
      ]);

  final ts = DateTime.utc(2026, 5, 1);

  test('build() returns null when no override exists for partnerId', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final loaded =
        await container.read(partnerStyleOverrideProvider('p1').future);
    expect(loaded, isNull);
  });

  test('build() returns the override when one is already persisted',
      () async {
    await repo.save(PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.humorous,
      updatedAt: ts,
    ));
    final container = makeContainer();
    addTearDown(container.dispose);

    final loaded =
        await container.read(partnerStyleOverrideProvider('p1').future);
    expect(loaded?.interactionStyle, InteractionStyle.humorous);
  });

  test('save() persists and updates state to the new override', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(partnerStyleOverrideProvider('p1').future);

    final override = PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.steady,
      practiceGoals: const [PracticeGoal.softInvite],
      updatedAt: ts,
    );
    await container
        .read(partnerStyleOverrideProvider('p1').notifier)
        .save(override);

    final state = container.read(partnerStyleOverrideProvider('p1'));
    expect(state.value?.interactionStyle, InteractionStyle.steady);
    expect(await repo.load('p1'), isNotNull);
  });

  test('save() with isEmpty override sets state to null and deletes row',
      () async {
    await repo.save(PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.gentle,
      updatedAt: ts,
    ));
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(partnerStyleOverrideProvider('p1').future);

    final empty =
        PartnerStyleOverride.create(partnerId: 'p1', updatedAt: ts);
    await container
        .read(partnerStyleOverrideProvider('p1').notifier)
        .save(empty);

    final state = container.read(partnerStyleOverrideProvider('p1'));
    expect(state.value, isNull);
    expect(await repo.load('p1'), isNull);
  });

  test('clear() deletes row and resets state to null', () async {
    await repo.save(PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.direct,
      updatedAt: ts,
    ));
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(partnerStyleOverrideProvider('p1').future);

    await container
        .read(partnerStyleOverrideProvider('p1').notifier)
        .clear();

    final state = container.read(partnerStyleOverrideProvider('p1'));
    expect(state.value, isNull);
    expect(await repo.load('p1'), isNull);
  });

  test('two partnerIds have isolated state', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(partnerStyleOverrideProvider('p1').future);
    await container.read(partnerStyleOverrideProvider('p2').future);

    await container
        .read(partnerStyleOverrideProvider('p1').notifier)
        .save(PartnerStyleOverride.create(
          partnerId: 'p1',
          interactionStyle: InteractionStyle.humorous,
          updatedAt: ts,
        ));

    final p1 = container.read(partnerStyleOverrideProvider('p1'));
    final p2 = container.read(partnerStyleOverrideProvider('p2'));
    expect(p1.value?.interactionStyle, InteractionStyle.humorous);
    expect(p2.value, isNull);
  });
}
