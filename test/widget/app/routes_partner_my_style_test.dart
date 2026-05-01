// Verifies /partner/:partnerId/my-style route resolves and the
// PartnerStyleEditScreen receives the partnerId path parameter.
//
// Phase 6 will fill in the real edit screen — this test only guards the
// route wiring + stub presence so future edit work can drop in without
// re-adding the route.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/presentation/screens/partner_style_edit_screen.dart';

class _Repo implements PartnerStyleRepository {
  @override
  Future<PartnerStyleOverride?> load(String p) async => null;
  @override
  Future<void> save(PartnerStyleOverride o) async {}
  @override
  Future<void> delete(String p) async {}
  @override
  Future<void> clearAll() async {}
}

void main() {
  testWidgets('/partner/:partnerId/my-style resolves to PartnerStyleEditScreen',
      (t) async {
    final router = GoRouter(
      initialLocation: '/partner/p1/my-style',
      routes: [
        GoRoute(
          path: '/partner/:partnerId/my-style',
          builder: (_, state) => PartnerStyleEditScreen(
            partnerId: state.pathParameters['partnerId']!,
          ),
        ),
      ],
    );

    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerStyleRepositoryProvider.overrideWithValue(_Repo()),
        partnerByIdProvider('p1').overrideWith((_) => Partner(
              id: 'p1',
              name: 'Alice',
              createdAt: DateTime(2026, 4, 20),
              updatedAt: DateTime(2026, 4, 20),
              ownerUserId: 'u1',
            )),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await t.pumpAndSettle();

    expect(find.byType(PartnerStyleEditScreen), findsOneWidget);
    final screen =
        t.widget<PartnerStyleEditScreen>(find.byType(PartnerStyleEditScreen));
    expect(screen.partnerId, 'p1');
  });
}
