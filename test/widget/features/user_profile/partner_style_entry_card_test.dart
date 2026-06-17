import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/widgets/partner_style_entry_card.dart';

class _FakeRepo implements PartnerStyleRepository {
  _FakeRepo([Map<String, PartnerStyleOverride>? seed])
      : byPartner = {...?seed};

  final Map<String, PartnerStyleOverride> byPartner;

  @override
  Future<PartnerStyleOverride?> load(String partnerId) async =>
      byPartner[partnerId];

  @override
  Future<void> save(PartnerStyleOverride override) async {
    if (override.isEmpty) {
      byPartner.remove(override.partnerId);
    } else {
      byPartner[override.partnerId] = override;
    }
  }

  @override
  Future<void> delete(String partnerId) async {
    byPartner.remove(partnerId);
  }

  @override
  Future<void> clearAll() async {
    byPartner.clear();
  }
}

Widget _harness({
  required String partnerId,
  required String partnerName,
  PartnerStyleOverride? override,
}) {
  return ProviderScope(
    overrides: [
      partnerStyleRepositoryProvider.overrideWithValue(
        _FakeRepo(override == null ? null : {partnerId: override}),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
              body: PartnerStyleEntryCard(
                partnerId: partnerId,
                partnerName: partnerName,
              ),
            ),
          ),
          GoRoute(
            path: '/partner/:partnerId/my-style',
            builder: (_, state) => Scaffold(
              body: Text('edit-stub-${state.pathParameters['partnerId']}'),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('shows 沿用全域預設 when override is null', (tester) async {
    await tester.pumpWidget(_harness(partnerId: 'p1', partnerName: '小明'));
    await tester.pumpAndSettle();
    expect(find.text('我的風格 · 對小明'), findsOneWidget);
    expect(find.text('沿用全域預設'), findsOneWidget);
    expect(find.text('已自訂風格'), findsNothing);
  });

  testWidgets('shows 已自訂風格 when override has any value', (tester) async {
    final ov = PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.humorous,
      updatedAt: DateTime.utc(2026, 5, 1),
    );
    await tester.pumpWidget(_harness(
      partnerId: 'p1',
      partnerName: '小明',
      override: ov,
    ));
    await tester.pumpAndSettle();
    expect(find.text('已自訂風格'), findsOneWidget);
    expect(find.text('沿用全域預設'), findsNothing);
  });

  testWidgets('uses dark-surface onBackground tokens', (tester) async {
    await tester.pumpWidget(_harness(partnerId: 'p1', partnerName: '小明'));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('我的風格 · 對小明'));
    final subtitle = tester.widget<Text>(find.text('沿用全域預設'));
    expect(title.style?.color, AppColors.onBackgroundPrimary);
    expect(subtitle.style?.color, AppColors.onBackgroundSecondary);
  });

  testWidgets('tapping card navigates to /partner/:id/my-style',
      (tester) async {
    await tester.pumpWidget(_harness(partnerId: 'p1', partnerName: '小明'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PartnerStyleEntryCard));
    await tester.pumpAndSettle();
    expect(find.text('edit-stub-p1'), findsOneWidget);
  });
}
