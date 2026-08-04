import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/opener/data/providers/opener_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_data_quality_state.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

class _FakeUserProfileRepo implements UserProfileRepository {
  final Map<String, UserProfile> byOwner = {};

  @override
  Future<UserProfile?> load(String uid) async => byOwner[uid];

  @override
  Future<void> save(UserProfile profile, String uid) async {
    byOwner[uid] = profile;
  }

  @override
  Future<void> clear(String uid) async => byOwner.remove(uid);
}

// 2026-08-04 拍板：關於我只用來增加 Coach 1:1 對使用者的了解，不再影響開場白
// 的實際輸出內容。openerStyleContextProvider（buildForOpener 的薄封裝）因此
// 恆定回傳 null，不論全域 About Me 或對象風格覆寫設定了什麼。
void main() {
  late Directory tmp;
  late Box<PartnerStyleOverride> box;
  late PartnerStyleRepository styleRepo;
  late _FakeUserProfileRepo userRepo;

  const uid = 'user-a';
  final ts = DateTime.utc(2026, 7, 3);

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
    tmp = await Directory.systemTemp.createTemp('opener_style_context');
    Hive.init(tmp.path);
    box = await Hive.openBox<PartnerStyleOverride>(
      'pso_${DateTime.now().microsecondsSinceEpoch}',
    );
    styleRepo = PartnerStyleRepository(box: box);
    userRepo = _FakeUserProfileRepo();
  });

  tearDown(() async {
    await box.close();
    await tmp.delete(recursive: true);
  });

  ProviderContainer makeContainer({bool partnerFlagged = false}) =>
      ProviderContainer(overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(styleRepo),
        userProfileRepositoryProvider.overrideWithValue(userRepo),
        authUserProfileScopeProvider.overrideWith((ref) => Stream.value(uid)),
        dataQualityFlagProvider.overrideWith(
          (ref, partnerId) => partnerFlagged
              ? DataQualityFlag.flagged(NamePair.canonical('a', 'b'))
              : const DataQualityFlag.unflagged(),
        ),
      ]);

  group('openerStyleContextProvider is permanently off', () {
    test('returns null even with a populated global profile', () async {
      userRepo.byOwner[uid] = UserProfile.create(
        interactionStyle: InteractionStyle.humorous,
        practiceGoals: const [PracticeGoal.findCompatiblePartner],
        topicSeeds: const [TopicSeed.coffee],
        notes: '我慢熟，開場不要太衝',
        updatedAt: ts,
      );
      final c = makeContainer();
      addTearDown(c.dispose);

      expect(
        await c.read(openerStyleContextProvider(null).future),
        isNull,
      );
    });

    test('returns null even with a trusted partner override', () async {
      userRepo.byOwner[uid] = UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        updatedAt: ts,
      );
      await styleRepo.save(PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.direct,
        updatedAt: ts,
      ));
      final c = makeContainer();
      addTearDown(c.dispose);

      expect(
        await c.read(openerStyleContextProvider('p1').future),
        isNull,
      );
    });

    test('returns null when a flagged partner suspends the override too',
        () async {
      userRepo.byOwner[uid] = UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        updatedAt: ts,
      );
      await styleRepo.save(PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.direct,
        updatedAt: ts,
      ));
      final c = makeContainer(partnerFlagged: true);
      addTearDown(c.dispose);

      expect(
        await c.read(openerStyleContextProvider('p1').future),
        isNull,
      );
    });

    test('returns null when nothing is configured', () async {
      final c = makeContainer();
      addTearDown(c.dispose);

      expect(
        await c.read(openerStyleContextProvider(null).future),
        isNull,
      );
    });
  });
}
