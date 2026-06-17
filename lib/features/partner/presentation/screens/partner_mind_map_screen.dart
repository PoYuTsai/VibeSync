import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/mindmap/mind_map_builder.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_mind_map_view.dart';
import 'partner_detail_screen.dart';

/// 對象作戰板全螢幕頁。dogfood 期全 tier 免費（決策 A），
/// 送審前 gating 另案（動訂閱區 → Codex 雙審）。
class PartnerMindMapScreen extends ConsumerWidget {
  final String partnerId;

  const PartnerMindMapScreen({super.key, required this.partnerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerByIdProvider(partnerId));

    if (partner == null) {
      return const Scaffold(
        body: Center(child: Text('找不到對象（可能已被合併或刪除）')),
      );
    }

    final aggregate = ref.watch(partnerAggregateProvider(partnerId));
    final conversations = ref.watch(conversationsByPartnerProvider(partnerId));

    final map = buildPartnerMindMap(
      partnerName: partner.name,
      aggregate: aggregate,
      conversations: conversations,
    );

    return _MindMapBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: Text(
            '${partner.name} 的作戰板',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
        ),
        body: Container(
          decoration: BoxDecoration(
            color: AppColors.brandInk.withValues(alpha: 0.34),
          ),
          child: SafeArea(
            child: map.hasAnalysisData
                ? PartnerMindMapView(
                    map: map,
                    // nextStep 葉節點 → 對象頁教練跟進區。文案維持「問教練」
                    // affordance，但目的地改到 partner-level 跟進。
                    onNextStepTap: (label) => context.push(
                      Uri(
                        path: '/partner/$partnerId',
                        queryParameters: {
                          PartnerDetailScreen.focusQueryParam:
                              PartnerDetailScreen.coachFollowUpFocusValue,
                          PartnerDetailScreen.focusActionQueryParam:
                              PartnerDetailScreen
                                  .openCoachInputFocusActionValue,
                        },
                      ).toString(),
                    ),
                  )
                : const _EmptyState(),
          ),
        ),
      ),
    );
  }
}

class _MindMapBackground extends StatelessWidget {
  const _MindMapBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.brandInk,
            AppColors.partnerDetailBgTop,
            AppColors.brandSurface,
          ],
          stops: [0.0, 0.48, 1.0],
        ),
      ),
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.brandSurface.withValues(alpha: 0.94),
                AppColors.brandSurface2.withValues(alpha: 0.90),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.ctaStart, AppColors.brandBlush],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.account_tree_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '完成一次對話分析，解鎖她的作戰板',
                textAlign: TextAlign.center,
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
