// Visual proof for the low-risk entry screens migrated onto BrandKit (Task B).
// Renders each screen to a PNG so the暗紫橘統一 can be eyeballed against the
// shipped 關於我/作戰板 reference.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/presentation/screens/new_conversation_screen.dart';
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

  // NewConversation needs interaction (expand settings + add a message) to show
  // the segmented buttons + message list, so it uses a manual capture flow
  // rather than the one-shot pumpAndCapture.
  testWidgets('new conversation capture (expanded)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1280));
    final rootKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'AppTC'),
          child: RepaintBoundary(
            key: rootKey,
            child: const ProviderScope(child: NewConversationScreen()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // Type a「her」message into the composer, then expand the analysis
    // settings so the BrandSegmentedButtons render in the capture.
    await tester.enterText(find.byType(TextField).at(1), '你也喜歡爬山嗎？');
    await tester.pump();
    await tester.tap(find.text('這次分析設定（可不改）'));
    await tester.pump(const Duration(milliseconds: 400));

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      (File(outPath('new_conversation.png'))..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
    await tester.binding.setSurfaceSize(null);
  });
}
