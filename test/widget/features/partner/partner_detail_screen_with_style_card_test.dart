// Verifies PartnerStyleEntryCard is mounted on PartnerDetailScreen
// alongside the existing PartnerTraitsCard (Spec 2 Task 12).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_detail_screen.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_traits_card.dart';
import 'package:vibesync/features/user_profile/data/providers/data_quality_flag_provider.dart';
import 'package:vibesync/features/user_profile/data/providers/partner_style_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/presentation/widgets/partner_style_entry_card.dart';

class _FakeStyleRepo implements PartnerStyleRepository {
  final Map<String, PartnerStyleOverride> byPartner = {};
  @override
  Future<PartnerStyleOverride?> load(String partnerId) async =>
      byPartner[partnerId];
  @override
  Future<void> save(PartnerStyleOverride o) async {
    if (o.isEmpty) {
      byPartner.remove(o.partnerId);
    } else {
      byPartner[o.partnerId] = o;
    }
  }

  @override
  Future<void> delete(String partnerId) async => byPartner.remove(partnerId);
  @override
  Future<void> clearAll() async => byPartner.clear();
}

Partner _p() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u1',
    );

void main() {
  testWidgets(
      'PartnerStyleEntryCard appears below PartnerTraitsCard on detail screen',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerByIdProvider('p1').overrideWith((_) => _p()),
        partnerAggregateProvider('p1')
            .overrideWith((_) => PartnerAggregateView.empty()),
        conversationsByPartnerProvider('p1')
            .overrideWith((_) => const <Conversation>[]),
        partnerListProvider.overrideWith((_) => [_p()]),
        partnerStyleRepositoryProvider.overrideWithValue(_FakeStyleRepo()),
        // Spec 3 Task 19 — PartnerDetailScreen now watches dataQualityFlag.
        // Default to unflagged so the banner doesn't render in this test.
        dataQualityFlagProvider('p1')
            .overrideWith((_) => const DataQualityFlag.unflagged()),
      ],
      child: const MaterialApp(home: PartnerDetailScreen(partnerId: 'p1')),
    ));
    await t.pumpAndSettle();

    expect(find.byType(PartnerTraitsCard), findsOneWidget);
    expect(find.byType(PartnerStyleEntryCard), findsOneWidget);
    expect(find.text('我的風格 · 對Alice'), findsOneWidget);
    // Default (no override) renders the 沿用 subtitle.
    expect(find.text('沿用全域預設'), findsOneWidget);

    // Geometric position: style card is BELOW traits card.
    final traitsTop = t.getTopLeft(find.byType(PartnerTraitsCard)).dy;
    final styleTop = t.getTopLeft(find.byType(PartnerStyleEntryCard)).dy;
    expect(styleTop, greaterThan(traitsTop));
  });
}
