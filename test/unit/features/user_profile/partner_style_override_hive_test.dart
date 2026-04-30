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
}
