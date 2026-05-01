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
      userProfileRepositoryProvider
          .overrideWithValue(_ProfileRepo(globalProfile)),
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

  group('Task 16 — PracticeGoals section', () {
    testWidgets(
        'placeholder hint shows 沿用全域：X、Y when partner goals empty AND global has goals',
        (tester) async {
      final global = UserProfile.create(
        practiceGoals: const [
          PracticeGoal.softInvite,
          PracticeGoal.reduceAnxiety,
        ],
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      await tester.pumpWidget(
        _harness(partnerId: 'p1', partner: _alice(), globalProfile: global),
      );
      await tester.pumpAndSettle();
      expect(find.text('（沿用全域：自然邀約、降低焦慮）'), findsOneWidget);
    });

    testWidgets(
        'placeholder hint shows 尚未設定 when both partner AND global goals empty',
        (tester) async {
      await tester.pumpWidget(
        _harness(partnerId: 'p1', partner: _alice()),
      );
      await tester.pumpAndSettle();
      // Two sections (style + goals) both render 尚未設定 — verify ≥2.
      expect(find.text('（尚未設定）'), findsAtLeastNWidgets(2));
    });

    testWidgets('tapping a goal chip adds it; tapping again removes it',
        (tester) async {
      await tester.pumpWidget(
        _harness(partnerId: 'p1', partner: _alice()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, '自然邀約'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '自然邀約'))
            .selected,
        isTrue,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, '自然邀約'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '自然邀約'))
            .selected,
        isFalse,
      );
    });

    testWidgets('selecting a 4th goal is rejected with a snackbar',
        (tester) async {
      // Surface big enough to expose snackbar in the same frame.
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _harness(partnerId: 'p1', partner: _alice()),
      );
      await tester.pumpAndSettle();

      for (final label in const ['自然邀約', '降低焦慮', '幽默回覆']) {
        await tester.tap(find.widgetWithText(ChoiceChip, label));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(ChoiceChip, '培養親近'));
      await tester.pumpAndSettle();

      expect(find.text('最多選 3 個'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '培養親近'))
            .selected,
        isFalse,
      );
    });

    testWidgets('沿用全域 reset link visible only when goals.isNotEmpty',
        (tester) async {
      await tester.pumpWidget(
        _harness(partnerId: 'p1', partner: _alice()),
      );
      await tester.pumpAndSettle();

      // No goals → no reset (and no style override → also no reset there).
      expect(find.text('沿用全域'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, '自然邀約'));
      await tester.pumpAndSettle();
      // Goals reset link appears (style still null → only one reset link).
      expect(find.text('沿用全域'), findsOneWidget);
    });

    testWidgets('tapping goals reset link clears goals back to empty',
        (tester) async {
      final initial = PartnerStyleOverride.create(
        partnerId: 'p1',
        practiceGoals: const [
          PracticeGoal.softInvite,
          PracticeGoal.reduceAnxiety,
        ],
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      await tester.pumpWidget(_harness(
        partnerId: 'p1',
        partner: _alice(),
        override: initial,
      ));
      await tester.pumpAndSettle();

      expect(find.text('沿用全域'), findsOneWidget);
      await tester.tap(find.text('沿用全域'));
      await tester.pumpAndSettle();

      expect(find.text('沿用全域'), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '自然邀約'))
            .selected,
        isFalse,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '降低焦慮'))
            .selected,
        isFalse,
      );
    });
  });

  group('Task 17 — Notes section', () {
    Finder notesField() => find.byKey(const Key('partner-style-notes-field'));

    testWidgets(
        'placeholder hint shows 沿用全域：<text> when partner notes null AND global notes set',
        (tester) async {
      final global = UserProfile.create(
        notes: '我慢熟，避免太快邀約',
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      await tester.pumpWidget(
        _harness(partnerId: 'p1', partner: _alice(), globalProfile: global),
      );
      await tester.pumpAndSettle();
      expect(find.text('（沿用全域：我慢熟，避免太快邀約）'), findsOneWidget);
    });

    testWidgets('typing in notes makes the reset link appear', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _harness(partnerId: 'p1', partner: _alice()),
      );
      await tester.pumpAndSettle();

      expect(find.text('沿用全域'), findsNothing);
      await tester.enterText(notesField(), '對 Alice 多用幽默');
      await tester.pumpAndSettle();
      expect(find.text('沿用全域'), findsOneWidget);
    });

    testWidgets('tapping notes reset clears the TextField + reset link',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final initial = PartnerStyleOverride.create(
        partnerId: 'p1',
        notes: '對 Alice 多用幽默',
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      await tester.pumpWidget(_harness(
        partnerId: 'p1',
        partner: _alice(),
        override: initial,
      ));
      await tester.pumpAndSettle();

      expect(find.text('對 Alice 多用幽默'), findsOneWidget);
      expect(find.text('沿用全域'), findsOneWidget);

      await tester.tap(find.text('沿用全域'));
      await tester.pumpAndSettle();

      expect(find.text('對 Alice 多用幽默'), findsNothing);
      expect(find.text('沿用全域'), findsNothing);
      final tf = tester.widget<TextField>(notesField());
      expect(tf.controller?.text ?? '', isEmpty);
    });
  });

  group('Task 18 — auto-save on back + reset-all', () {
    testWidgets('back gesture saves the draft override via notifier',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _StyleRepo();
      // Use a router so we can drive system back via Navigator.maybePop.
      await tester.pumpWidget(ProviderScope(
        overrides: [
          partnerStyleRepositoryProvider.overrideWithValue(repo),
          partnerByIdProvider('p1').overrideWith((_) => _alice()),
          userProfileRepositoryProvider.overrideWithValue(_ProfileRepo(null)),
          authUserProfileScopeProvider
              .overrideWith((ref) => Stream.value(_ProfileRepo._uid)),
        ],
        child: const MaterialApp(
          home: PartnerStyleEditScreen(partnerId: 'p1'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, '幽默'));
      await tester.pumpAndSettle();

      // Trigger system back — PopScope should save before letting it pop.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(repo.byPartner['p1']?.interactionStyle, InteractionStyle.humorous);
    });

    testWidgets('完成 button saves the draft override via notifier',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _StyleRepo();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          partnerStyleRepositoryProvider.overrideWithValue(repo),
          partnerByIdProvider('p1').overrideWith((_) => _alice()),
          userProfileRepositoryProvider.overrideWithValue(_ProfileRepo(null)),
          authUserProfileScopeProvider
              .overrideWith((ref) => Stream.value(_ProfileRepo._uid)),
        ],
        child: const MaterialApp(
          home: PartnerStyleEditScreen(partnerId: 'p1'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, '幽默'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(repo.byPartner['p1']?.interactionStyle, InteractionStyle.humorous);
    });

    testWidgets(
        'back with empty draft cascades to repo.delete (no leftover row)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final initial = PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.humorous,
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      final repo = _StyleRepo({'p1': initial});
      await tester.pumpWidget(ProviderScope(
        overrides: [
          partnerStyleRepositoryProvider.overrideWithValue(repo),
          partnerByIdProvider('p1').overrideWith((_) => _alice()),
          userProfileRepositoryProvider.overrideWithValue(_ProfileRepo(null)),
          authUserProfileScopeProvider
              .overrideWith((ref) => Stream.value(_ProfileRepo._uid)),
        ],
        child: const MaterialApp(
          home: PartnerStyleEditScreen(partnerId: 'p1'),
        ),
      ));
      await tester.pumpAndSettle();

      // Reset the only field set.
      await tester.tap(find.text('沿用全域'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(repo.byPartner.containsKey('p1'), isFalse);
    });

    testWidgets('清除這個對象的自訂風格 link opens confirm dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _harness(partnerId: 'p1', partner: _alice()),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('清除這個對象的自訂風格'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除這個對象的自訂風格'));
      await tester.pumpAndSettle();

      expect(find.text('清除這個對象的自訂風格？'), findsOneWidget);
      expect(find.text('確認清除'), findsOneWidget); // dialog button
      expect(
        find.textContaining('清空對 Alice 的自訂風格'),
        findsOneWidget,
      );
    });

    testWidgets('清除這個對象的自訂風格 confirm wipes repo row and closes screen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final initial = PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.humorous,
        practiceGoals: const [PracticeGoal.softInvite],
        notes: 'something',
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      final repo = _StyleRepo({'p1': initial});
      await tester.pumpWidget(ProviderScope(
        overrides: [
          partnerStyleRepositoryProvider.overrideWithValue(repo),
          partnerByIdProvider('p1').overrideWith((_) => _alice()),
          userProfileRepositoryProvider.overrideWithValue(_ProfileRepo(null)),
          authUserProfileScopeProvider
              .overrideWith((ref) => Stream.value(_ProfileRepo._uid)),
        ],
        child: const MaterialApp(
          home: PartnerStyleEditScreen(partnerId: 'p1'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('清除這個對象的自訂風格'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除這個對象的自訂風格'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認清除'));
      await tester.pumpAndSettle();

      expect(repo.byPartner.containsKey('p1'), isFalse);
    });
  });
}
