import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/app/main_shell.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_list_screen.dart';
import 'package:vibesync/shared/widgets/warm_theme_widgets.dart';

import 'proof_support.dart';

Partner _p(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 4, 20),
      updatedAt: DateTime(2026, 4, 20),
      ownerUserId: 'u-proof',
    );

PartnerAggregateView _agg({
  int? heat,
  List<String> interests = const [],
  List<String> traits = const [],
  int daysAgo = 5,
}) =>
    PartnerAggregateView(
      unionInterests: interests,
      unionTraits: traits,
      unionNotes: null,
      latestHeat: heat,
      totalRounds: heat == null ? 0 : 3,
      totalMessages: 0,
      lastInteraction: DateTime.now().subtract(Duration(days: daysAgo)),
    );

class _PartnerHomeProof extends StatelessWidget {
  const _PartnerHomeProof();

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          centerTitle: true,
          elevation: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('VibeSync', style: AppTypography.headlineMedium),
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 12),
                decoration: const BoxDecoration(
                  color: AppColors.ctaStart,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () {},
            ),
          ],
        ),
        body: const PartnerListScreen(
          bottomPadding: 32.0 + homeFabReservedHeight,
        ),
        floatingActionButton: const HomeFab(),
        bottomNavigationBar: _ProofBottomNav(),
      ),
    );
  }
}

class _ProofBottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.brandInk.withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: const [
            _ProofTab(icon: Icons.home, label: '首頁', selected: true),
            _ProofTab(icon: Icons.bar_chart_outlined, label: '分析'),
            _ProofTab(icon: Icons.menu_book_outlined, label: '學習'),
          ],
        ),
      ),
    );
  }
}

class _ProofTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;

  const _ProofTab({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 54, minHeight: 44),
      padding: EdgeInsets.symmetric(
        horizontal: selected ? 20 : 14,
        vertical: 11,
      ),
      decoration: selected
          ? BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.ctaStart, AppColors.ctaEnd],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.66),
            size: 22,
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('prod partner home', (tester) async {
    final partners = [
      _p('amy', 'Amy'),
      _p('jenny', 'Jenny'),
      _p('joyce', 'Joyce'),
      _p('nina', 'Nina'),
      _p('gigi', 'Gigi'),
      _p('tina', 'Tina'),
    ];

    await pumpAndCapture(
      tester,
      child: ProviderScope(
        overrides: [
          authConversationScopeProvider.overrideWith(
            (_) => Stream.value('u-proof'),
          ),
          partnerListProvider.overrideWith((_) => partners),
          partnerAggregateProvider('amy').overrideWith((_) => _agg()),
          partnerAggregateProvider('jenny').overrideWith((_) => _agg()),
          partnerAggregateProvider('joyce').overrideWith(
            (_) => _agg(
              heat: 68,
              interests: const ['茄汁牛肉飯'],
              traits: const ['喜歡碎碎念'],
            ),
          ),
          partnerAggregateProvider('nina').overrideWith(
            (_) => _agg(
              heat: 82,
              interests: const ['美食'],
              traits: const ['主動分享', '可愛自嘲'],
            ),
          ),
          partnerAggregateProvider('gigi').overrideWith(
            (_) => _agg(
              heat: 85,
              interests: const ['可愛小物'],
              traits: const ['活潑', 'QQ恐龍'],
            ),
          ),
          partnerAggregateProvider('tina').overrideWith(
            (_) => _agg(
              heat: 85,
              interests: const ['健身'],
              traits: const ['主動分享', '瑜伽'],
              daysAgo: 6,
            ),
          ),
          for (final partner in partners)
            conversationsByPartnerProvider(partner.id)
                .overrideWith((_) => const <Conversation>[]),
        ],
        child: const _PartnerHomeProof(),
      ),
      outPath: outPath('prod_partner_home.png'),
    );
  });
}
