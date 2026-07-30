import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:vibesync/features/partner/presentation/widgets/home_coach_presence.dart';
import 'package:vibesync/shared/widgets/warm_theme_widgets.dart';

import 'proof_support.dart';

Partner _partner(String id, String name) => Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 7, 30),
      updatedAt: DateTime(2026, 7, 30),
      ownerUserId: 'u-sydney-proof',
    );

PartnerAggregateView _aggregate({
  required int? heat,
  required List<String> interests,
  required List<String> traits,
}) =>
    PartnerAggregateView(
      unionInterests: interests,
      unionTraits: traits,
      unionNotes: null,
      latestHeat: heat,
      totalRounds: heat == null ? 0 : 3,
      totalMessages: 0,
      lastInteraction: DateTime(2026, 7, 30, 18, 3),
    );

class _SydneyHomeProof extends StatelessWidget {
  const _SydneyHomeProof();

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
          coachPose: HomeCoachPose.tip,
          bottomPadding: 32,
        ),
        floatingActionButton: const HomeFab(),
        bottomNavigationBar: const _BottomNav(),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.brandInk,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.ctaStart, AppColors.ctaEnd],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.home, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text('首頁', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const Icon(Icons.bar_chart_outlined, color: Colors.white70),
              const Icon(Icons.menu_book_outlined, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('Sydney appears below a short partner list', (tester) async {
    final partners = [
      _partner('abby', 'Abby'),
      _partner('candy', 'Candy'),
    ];

    await pumpAndCapture(
      tester,
      child: ProviderScope(
        overrides: [
          authConversationScopeProvider.overrideWith(
            (_) => Stream.value('u-sydney-proof'),
          ),
          partnerListProvider.overrideWith((_) => partners),
          partnerAggregateProvider('abby').overrideWith(
            (_) => _aggregate(
              heat: null,
              interests: const ['攝影'],
              traits: const ['活潑', '蛋白飲'],
            ),
          ),
          partnerAggregateProvider('candy').overrideWith(
            (_) => _aggregate(
              heat: 71,
              interests: const ['備課'],
              traits: const ['餐飲熟人'],
            ),
          ),
          for (final partner in partners)
            conversationsByPartnerProvider(partner.id)
                .overrideWith((_) => const <Conversation>[]),
        ],
        child: const _SydneyHomeProof(),
      ),
      outPath: outPath('sydney_home.png'),
      rasterDecodeWait: const Duration(milliseconds: 100),
    );

    final coachImage = find.byKey(
      const ValueKey('home-coach-pose-tip'),
    );
    expect(find.byType(HomeCoachPresence), findsOneWidget);
    expect(coachImage, findsOneWidget);
    expect(tester.getSize(coachImage).height, greaterThan(300));
    expect(tester.renderObject<RenderImage>(coachImage).image, isNotNull);
  });
}
