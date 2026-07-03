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

  group('openerStyleContextProvider', () {
    // Codex R1 P2：不做任何預熱（settle）——provider 必須自己 await 依賴，
    // cold entry 首發就要拿得到風格；否則「首發 null、重試 resolve」會讓
    // fingerprint 漂移、requestId 換新、server 去重失效（雙扣風險）。
    test('cold read resolves global-only context without pre-warming',
        () async {
      userRepo.byOwner[uid] = UserProfile.create(
        interactionStyle: InteractionStyle.humorous,
        updatedAt: ts,
      );
      final c = makeContainer();
      addTearDown(c.dispose);

      final context =
          (await c.read(openerStyleContextProvider(null).future))!;
      expect(context, contains('Preferred voice: 幽默'));
      expect(context, contains('只用來調整開場白語氣'));
    });

    test('blank partnerId is treated as no partner', () async {
      userRepo.byOwner[uid] = UserProfile.create(
        interactionStyle: InteractionStyle.steady,
        updatedAt: ts,
      );
      final c = makeContainer();
      addTearDown(c.dispose);

      final context =
          (await c.read(openerStyleContextProvider('  ').future))!;
      expect(context, contains('Preferred voice: 穩重'));
    });

    test('trusted partner override wins over global', () async {
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

      final context =
          (await c.read(openerStyleContextProvider('p1').future))!;
      expect(context, contains('Preferred voice: 直接'));
      expect(context, isNot(contains('溫柔')));
    });

    test('flagged partner suspends override, keeps global (Spec 3)', () async {
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

      final context =
          (await c.read(openerStyleContextProvider('p1').future))!;
      expect(context, contains('Preferred voice: 溫柔'));
      expect(context, isNot(contains('直接')));
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
