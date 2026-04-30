import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/services/storage_service.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_storage_pso');
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(InteractionStyleAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(PracticeGoalAdapter());
    }
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(PartnerStyleOverrideAdapter());
    }
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('partner_style_overrides');
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test('partnerStyleOverridesBox getter resolves to opened box keyed by '
      '"partner_style_overrides"', () async {
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');

    final box = StorageService.partnerStyleOverridesBox;

    expect(box, isA<Box<PartnerStyleOverride>>());
    expect(box.isOpen, isTrue);
    expect(box.name, 'partner_style_overrides');
  });

  test('round-trips a PartnerStyleOverride through the named box', () async {
    await Hive.openBox<PartnerStyleOverride>('partner_style_overrides');
    final box = StorageService.partnerStyleOverridesBox;

    await box.put(
      'p1',
      PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.steady,
        updatedAt: DateTime.utc(2026, 5, 1),
      ),
    );

    final restored = box.get('p1');
    expect(restored?.partnerId, 'p1');
    expect(restored?.interactionStyle, InteractionStyle.steady);
  });
}
