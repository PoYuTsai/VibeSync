import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/screens/partner_style_edit_screen.dart';

class _StyleRepo implements PartnerStyleRepository {
  _StyleRepo([Map<String, PartnerStyleOverride>? seed])
      : byPartner = {...?seed};
  final Map<String, PartnerStyleOverride> byPartner;
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
  _ProfileRepo(UserProfile? initial) {
    if (initial != null) byOwner[_uid] = initial;
  }
  static const _uid = 'test-user';
  final Map<String, UserProfile> byOwner = {};
  @override
  Future<UserProfile?> load(String uid) async => byOwner[uid];
  @override
  Future<void> save(UserProfile p, String uid) async => byOwner[uid] = p;
  @override
  Future<void> clear(String uid) async => byOwner.remove(uid);
}

Partner _alice() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

Widget _harness({
  required String partnerId,
  Partner? partner,
  PartnerStyleOverride? override,
  UserProfile? globalProfile,
}) {
  return ProviderScope(
    overrides: [
      partnerStyleRepositoryProvider.overrideWithValue(
        _StyleRepo(override == null ? null : {partnerId: override}),
      ),
      partnerByIdProvider(partnerId).overrideWith((_) => partner),
      userProfileRepositoryProvider.overrideWithValue(_ProfileRepo(globalProfile)),
      authUserProfileScopeProvider
          .overrideWith((ref) => Stream.value(_ProfileRepo._uid)),
    ],
    child: MaterialApp(
      home: PartnerStyleEditScreen(partnerId: partnerId),
    ),
  );
}

void main() {
  group('Task 14 — scaffold', () {
    testWidgets('AppBar title shows 我的風格 · {partner.name}', (t) async {
      await t.pumpWidget(_harness(partnerId: 'p1', partner: _alice()));
      await t.pumpAndSettle();
      expect(find.text('我的風格 · Alice'), findsOneWidget);
    });

    testWidgets('AppBar title falls back to 我的風格 when partner is null',
        (t) async {
      await t.pumpWidget(_harness(partnerId: 'ghost', partner: null));
      await t.pumpAndSettle();
      expect(find.text('我的風格'), findsOneWidget);
    });

    testWidgets('renders three section headers (style / goals / notes)',
        (t) async {
      await t.pumpWidget(_harness(partnerId: 'p1', partner: _alice()));
      await t.pumpAndSettle();
      expect(find.text('互動風格'), findsOneWidget);
      expect(find.text('練習目標'), findsOneWidget);
      expect(find.text('備註'), findsOneWidget);
    });
  });

  group('Task 15 — InteractionStyle section', () {
    testWidgets(
        'placeholder hint shows 沿用全域：X when partner null AND global has value',
        (t) async {
      final global = UserProfile.create(
        interactionStyle: InteractionStyle.steady,
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      await t.pumpWidget(
        _harness(partnerId: 'p1', partner: _alice(), globalProfile: global),
      );
      await t.pumpAndSettle();
      expect(find.text('（沿用全域：穩重）'), findsOneWidget);
    });

    testWidgets('placeholder hint shows 尚未設定 when both partner AND global null',
        (t) async {
      await t.pumpWidget(_harness(partnerId: 'p1', partner: _alice()));
      await t.pumpAndSettle();
      expect(find.text('（尚未設定）'), findsAtLeastNWidgets(1));
    });

    testWidgets('selecting a chip updates state to that style', (tester) async {
      await tester.pumpWidget(
        _harness(partnerId: 'p1', partner: _alice()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '幽默'));
      await tester.pumpAndSettle();

      // Selected chip is reflected; placeholder hint disappears.
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '幽默'),
      );
      expect(chip.selected, isTrue);
    });

    testWidgets('沿用全域 reset link visible only when interactionStyle set',
        (tester) async {
      await tester.pumpWidget(
        _harness(partnerId: 'p1', partner: _alice()),
      );
      await tester.pumpAndSettle();

      // No override → no reset link.
      expect(find.text('沿用全域'), findsNothing);

      // Tap chip → reset link appears.
      await tester.tap(find.widgetWithText(ChoiceChip, '幽默'));
      await tester.pumpAndSettle();
      expect(find.text('沿用全域'), findsOneWidget);
    });

    testWidgets('tapping reset link clears interactionStyle back to null',
        (tester) async {
      final initial = PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.humorous,
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      await tester.pumpWidget(_harness(
        partnerId: 'p1',
        partner: _alice(),
        override: initial,
      ));
      await tester.pumpAndSettle();

      // Reset link visible.
      expect(find.text('沿用全域'), findsOneWidget);
      // Selected chip is 幽默.
      var chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '幽默'),
      );
      expect(chip.selected, isTrue);

      await tester.tap(find.text('沿用全域'));
      await tester.pumpAndSettle();

      // After reset, link disappears and chip is no longer selected.
      expect(find.text('沿用全域'), findsNothing);
      chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '幽默'),
      );
      expect(chip.selected, isFalse);
    });
  });
}
