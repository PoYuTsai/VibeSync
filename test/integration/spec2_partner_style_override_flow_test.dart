// Spec 2 end-to-end widget flow:
//
// 1. Fresh partner → entry card shows "沿用全域預設".
// 2. Tap → edit → set style + goals + notes → back → "已自訂風格".
// 3. Re-enter edit → reset all three → back → "沿用全域預設" again.
//
// Cascade-delete on partner removal and clearAll() account-wide cleanup
// are covered by:
//   - test/unit/repositories/partner_repository_cascade_test.dart
//   - test/unit/services/storage_service_clear_all_test.dart
// so this file focuses on the UI round-trip.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/screens/partner_style_edit_screen.dart';
import 'package:vibesync/features/user_profile/presentation/widgets/partner_style_entry_card.dart';

class _StyleRepo implements PartnerStyleRepository {
  final Map<String, PartnerStyleOverride> byPartner = {};
  @override
  Future<PartnerStyleOverride?> load(String p) async => byPartner[p];
  @override
  Future<void> save(PartnerStyleOverride o) async {
    if (o.isEmpty) {
      byPartner.remove(o.partnerId);
    } else {
      byPartner[o.partnerId] = o;
    }
  }

  @override
  Future<void> delete(String p) async => byPartner.remove(p);
  @override
  Future<void> clearAll() async => byPartner.clear();
}

class _ProfileRepo implements UserProfileRepository {
  _ProfileRepo([this._initial]);
  final UserProfile? _initial;
  static const _uid = 'test-user';
  final Map<String, UserProfile> _byOwner = {};
  @override
  Future<UserProfile?> load(String uid) async =>
      _byOwner[uid] ?? (uid == _uid ? _initial : null);
  @override
  Future<void> save(UserProfile p, String uid) async => _byOwner[uid] = p;
  @override
  Future<void> clear(String uid) async => _byOwner.remove(uid);
}

Partner _alice() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

Widget _app(_StyleRepo styleRepo, {UserProfile? globalProfile}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: PartnerStyleEntryCard(
              partnerId: 'p1',
              partnerName: 'Alice',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/partner/:partnerId/my-style',
        builder: (_, state) => PartnerStyleEditScreen(
          partnerId: state.pathParameters['partnerId']!,
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      partnerStyleRepositoryProvider.overrideWithValue(styleRepo),
      partnerByIdProvider('p1').overrideWith((_) => _alice()),
      userProfileRepositoryProvider
          .overrideWithValue(_ProfileRepo(globalProfile)),
      authUserProfileScopeProvider
          .overrideWith((ref) => Stream.value(_ProfileRepo._uid)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets(
      'edit → save → back → entry card 副標 reflects override and round-trips back to default',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _StyleRepo();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    // Step 1: fresh partner — subtitle 沿用全域預設.
    expect(find.text('沿用全域預設'), findsOneWidget);

    // Step 2: enter edit, set 1 chip + 1 goal + notes, back.
    await tester.tap(find.byType(PartnerStyleEntryCard));
    await tester.pumpAndSettle();
    expect(find.byType(PartnerStyleEditScreen), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '幽默'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '自然邀約'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('partner-style-notes-field')),
      '對 Alice 多用幽默',
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Repo persisted the override (notifier.save was triggered by PopScope).
    expect(repo.byPartner['p1']?.interactionStyle,
        InteractionStyle.humorous);
    expect(repo.byPartner['p1']?.practiceGoals,
        contains(PracticeGoal.softInvite));
    expect(repo.byPartner['p1']?.notes, '對 Alice 多用幽默');

    // Subtitle now reflects override.
    expect(find.text('已自訂風格'), findsOneWidget);
    expect(find.text('沿用全域預設'), findsNothing);

    // Step 3: re-enter, reset all three, back → 沿用全域預設 again.
    await tester.tap(find.byType(PartnerStyleEntryCard));
    await tester.pumpAndSettle();

    // Three reset links — tap them all (style, goals, notes).
    final resets = find.text('沿用全域');
    expect(resets, findsNWidgets(3));
    // Tap repeatedly until none remain (each tap removes one link).
    while (find.text('沿用全域').evaluate().isNotEmpty) {
      await tester.tap(find.text('沿用全域').first);
      await tester.pumpAndSettle();
    }

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // isEmpty cascade-delete — repo row gone.
    expect(repo.byPartner.containsKey('p1'), isFalse);
    expect(find.text('沿用全域預設'), findsOneWidget);
    expect(find.text('已自訂風格'), findsNothing);
  });
}
