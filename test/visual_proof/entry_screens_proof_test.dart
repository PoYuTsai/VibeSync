// Visual proof for the low-risk entry screens migrated onto BrandKit (Task B).
// Renders each screen to a PNG so the暗紫橘統一 can be eyeballed against the
// shipped 關於我/作戰板 reference.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/add_partner_screen.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/screens/partner_style_edit_screen.dart';

import 'proof_support.dart';

class _StyleRepo implements PartnerStyleRepository {
  _StyleRepo([Map<String, PartnerStyleOverride>? seed]) : byPartner = {...?seed};
  final Map<String, PartnerStyleOverride> byPartner;
  @override
  Future<PartnerStyleOverride?> load(String p) async => byPartner[p];
  @override
  Future<void> save(PartnerStyleOverride o) async => byPartner[o.partnerId] = o;
  @override
  Future<void> delete(String p) async => byPartner.remove(p);
  @override
  Future<void> clearAll() async => byPartner.clear();
}

class _ProfileRepo implements UserProfileRepository {
  static const uid = 'u-proof';
  final Map<String, UserProfile> byOwner = {};
  @override
  Future<UserProfile?> load(String u) async => byOwner[u];
  @override
  Future<void> save(UserProfile p, String u) async => byOwner[u] = p;
  @override
  Future<void> clear(String u) async => byOwner.remove(u);
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('add partner capture', (tester) async {
    await pumpAndCapture(
      tester,
      child: ProviderScope(
        overrides: [
          authConversationScopeProvider.overrideWith(
            (ref) => Stream.value('u-proof'),
          ),
        ],
        child: const AddPartnerScreen(),
      ),
      outPath: outPath('add_partner.png'),
    );
  });

  testWidgets('partner style edit capture', (tester) async {
    const partnerId = 'p-proof';
    await pumpAndCapture(
      tester,
      size: const Size(390, 1000),
      child: ProviderScope(
        overrides: [
          partnerStyleRepositoryProvider.overrideWithValue(
            _StyleRepo({
              partnerId: PartnerStyleOverride.create(
                partnerId: partnerId,
                interactionStyle: InteractionStyle.gentle,
                secondaryStyle: InteractionStyle.humorous,
                practiceGoals: const [PracticeGoal.softInvite],
                notes: '她喜歡被慢慢靠近',
                updatedAt: DateTime.utc(2026, 6, 1),
              ),
            }),
          ),
          partnerByIdProvider(partnerId).overrideWith(
            (_) => Partner(
              id: partnerId,
              name: 'Nani',
              createdAt: DateTime(2026, 6, 1),
              updatedAt: DateTime(2026, 6, 1),
              ownerUserId: 'u-proof',
            ),
          ),
          userProfileRepositoryProvider.overrideWithValue(_ProfileRepo()),
          authUserProfileScopeProvider.overrideWith(
            (ref) => Stream.value(_ProfileRepo.uid),
          ),
        ],
        child: const PartnerStyleEditScreen(partnerId: partnerId),
      ),
      outPath: outPath('partner_style_edit.png'),
    );
  });
}
