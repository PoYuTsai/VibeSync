import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  late Directory tmp;
  late Box<PartnerStyleOverride> box;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('partner_style_override_hive');
    Hive.init(tmp.path);
    if (!Hive.isAdapterRegistered(PartnerStyleOverrideAdapter().typeId)) {
      Hive.registerAdapter(PartnerStyleOverrideAdapter());
    }
    if (!Hive.isAdapterRegistered(InteractionStyleAdapter().typeId)) {
      Hive.registerAdapter(InteractionStyleAdapter());
    }
    if (!Hive.isAdapterRegistered(PracticeGoalAdapter().typeId)) {
      Hive.registerAdapter(PracticeGoalAdapter());
    }
    box = await Hive.openBox<PartnerStyleOverride>(
      'test_partner_style_overrides_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() async {
    await box.close();
    await tmp.delete(recursive: true);
  });

  test('PartnerStyleOverride survives Hive round-trip', () async {
    final original = PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.humorous,
      practiceGoals: const [
        PracticeGoal.softInvite,
        PracticeGoal.reduceAnxiety,
      ],
      notes: '對方慢熟',
      updatedAt: DateTime.utc(2026, 5, 1, 12, 0),
    );

    await box.put(original.partnerId, original);
    final restored = box.get('p1')!;

    expect(restored.partnerId, 'p1');
    expect(restored.interactionStyle, InteractionStyle.humorous);
    expect(restored.practiceGoals, original.practiceGoals);
    expect(restored.notes, '對方慢熟');
    expect(restored.updatedAt, original.updatedAt);
  });

  test('PartnerStyleOverride with all-null optional fields round-trips', () async {
    final original = PartnerStyleOverride.create(
      partnerId: 'p2',
      updatedAt: DateTime.utc(2026, 5, 1),
    );
    await box.put(original.partnerId, original);
    final restored = box.get('p2')!;

    expect(restored.partnerId, 'p2');
    expect(restored.interactionStyle, isNull);
    expect(restored.practiceGoals, isEmpty);
    expect(restored.notes, isNull);
    expect(restored.updatedAt, original.updatedAt);
  });

  test('typeId is locked at 13 (forward-compat fence)', () {
    expect(PartnerStyleOverrideAdapter().typeId, 13);
  });

  test('style pair (主+副) survives Hive round-trip', () async {
    final original = PartnerStyleOverride.create(
      partnerId: 'p3',
      interactionStyle: InteractionStyle.steady,
      secondaryStyle: InteractionStyle.playful,
      updatedAt: DateTime.utc(2026, 6, 10),
    );

    await box.put(original.partnerId, original);
    final restored = box.get('p3')!;

    expect(restored.interactionStyle, InteractionStyle.steady);
    expect(restored.secondaryStyle, InteractionStyle.playful);
  });

  test('legacy 5-field binary (pre style pair) reads secondaryStyle=null',
      () async {
    // Write with the pre-pair wire format (fields 0..4 only), then re-read
    // with the current generated adapter — zero migration for existing rows.
    Hive.registerAdapter(_LegacyPartnerStyleOverrideAdapter(), override: true);
    final legacyBox = await Hive.openBox<PartnerStyleOverride>(
      'test_partner_style_legacy_${DateTime.now().microsecondsSinceEpoch}',
    );
    await legacyBox.put(
      'p1',
      PartnerStyleOverride(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.direct,
        updatedAt: DateTime.utc(2026, 6, 1),
      ),
    );
    final boxName = legacyBox.name;
    await legacyBox.close();

    Hive.registerAdapter(PartnerStyleOverrideAdapter(), override: true);
    final reopened = await Hive.openBox<PartnerStyleOverride>(boxName);
    final restored = reopened.get('p1')!;

    expect(restored.interactionStyle, InteractionStyle.direct);
    expect(restored.secondaryStyle, isNull);
    await reopened.close();
  });
}

/// The exact `write` shape the generated adapter had before secondaryStyle
/// (@HiveField(5)) was added — used to fabricate authentic legacy rows.
class _LegacyPartnerStyleOverrideAdapter
    extends TypeAdapter<PartnerStyleOverride> {
  @override
  final typeId = 13;

  @override
  PartnerStyleOverride read(BinaryReader reader) =>
      throw UnsupportedError('write-only legacy adapter');

  @override
  void write(BinaryWriter writer, PartnerStyleOverride obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.partnerId)
      ..writeByte(1)
      ..write(obj.interactionStyle)
      ..writeByte(2)
      ..write(obj.practiceGoals)
      ..writeByte(3)
      ..write(obj.notes)
      ..writeByte(4)
      ..write(obj.updatedAt);
  }
}
