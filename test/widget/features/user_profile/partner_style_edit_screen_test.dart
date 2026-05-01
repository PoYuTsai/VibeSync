import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/presentation/screens/partner_style_edit_screen.dart';

class _Repo implements PartnerStyleRepository {
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
}) {
  return ProviderScope(
    overrides: [
      partnerStyleRepositoryProvider.overrideWithValue(_Repo()),
      partnerByIdProvider(partnerId).overrideWith((_) => partner),
    ],
    child: MaterialApp(
      home: PartnerStyleEditScreen(partnerId: partnerId),
    ),
  );
}

void main() {
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
}
