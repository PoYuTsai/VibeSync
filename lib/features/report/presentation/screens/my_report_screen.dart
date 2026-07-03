// lib/features/report/presentation/screens/my_report_screen.dart
//
// 2026-06-17 暗紫橘統一 (BrandKit migration): the Free-tier locked card and the
// three fl_chart surfaces (HeatTrendChart / ConversationComparisonChart /
// StageDistributionChart) moved off the light warm-glass GlassmorphicContainer
// onto the shared dark BrandKit surfaces (BrandSurfaceCard + BrandPrimaryButton),
// with chart labels/legends/lines recolored white / onBackgroundSecondary /
// orange for legibility on the dark brand surface. No report gating, provider,
// or navigation behavior changed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../user_profile/presentation/widgets/about_me_card.dart';
import '../../data/providers/report_providers.dart';
import '../widgets/heat_trend_chart.dart';
import '../widgets/conversation_comparison_chart.dart';
import '../widgets/partner_mindmap_card_list.dart';
import '../widgets/stage_distribution_chart.dart';

class MyReportScreen extends ConsumerWidget {
  const MyReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(subscriptionProvider);
    final report = ref.watch(reportDataProvider);
    final isEmpty = report.totalConversations == 0;
    final partners = ref.watch(partnerListProvider);
    // Stage labels 必須在 build 階段 eager 解析：ListView 的 itemBuilder 在
    // layout 階段執行，callback 裡用 ref.watch 會逸出 build contract。
    final stageLabels = {
      for (final p in partners) p.id: _latestStageLabel(ref, p.id),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        const AboutMeCard(),
        const SizedBox(height: 24),
        if (subscription.isFreeUser)
          _lockedReportCard(context)
        else if (isEmpty)
          ..._emptyStateContents()
        else ...[
          Text(
            '我的報告',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.ctaStart,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: AppTypography.headlineLarge.copyWith(
                color: AppColors.onBackgroundPrimary,
              ),
              children: [
                const TextSpan(text: '最近 '),
                TextSpan(
                  text: '七次',
                  style: TextStyle(color: AppColors.ctaStart),
                ),
                const TextSpan(text: ' 的節奏'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          HeatTrendChart(
            trendPoints: report.trendPoints,
            averageScore: report.averageScore,
            scoreDelta: report.scoreDelta,
          ),
          const SizedBox(height: 16),
          ConversationComparisonChart(
            comparisons: report.comparisons,
          ),
          const SizedBox(height: 16),
          StageDistributionChart(
            distributions: report.stageDistributions,
            totalConversations: report.totalConversations,
          ),
        ],
        const SizedBox(height: 32),
        // dogfood 決策 A：作戰板入口全 tier 可見，與上方報告 gating 無關
        PartnerMindMapCardList(
          partners: partners,
          stageLabelOf: (id) => stageLabels[id],
          onTapPartner: (id) => context.push('/partner/$id/mindmap'),
        ),
      ],
    );
  }

  /// 最新階段標籤：conversationsByPartnerProvider 由 repo `listByPartner`
  /// 保證 updatedAt desc，掃到第一個非空 currentGameStage 即最新。
  String? _latestStageLabel(WidgetRef ref, String partnerId) {
    final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
    for (final c in conversations) {
      final raw = c.currentGameStage?.trim();
      if (raw != null && raw.isNotEmpty) {
        final stage = GameStage.fromString(raw);
        return '${stage.emoji} ${stage.label}';
      }
    }
    return null;
  }

  Widget _lockedReportCard(BuildContext context) {
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandIconBadge(icon: Icons.lock_outline, size: 40, iconSize: 22),
          const SizedBox(height: 12),
          Text(
            '我的報告會在 Starter 解鎖',
            style: AppTypography.titleLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '升級後可以看互動雷達圖、歷史趨勢與不同對話的比較，知道自己哪裡正在進步。',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          BrandPrimaryButton(
            label: '查看升級方案',
            icon: Icons.workspace_premium,
            onPressed: () => context.push('/paywall'),
          ),
        ],
      ),
    );
  }

  List<Widget> _emptyStateContents() {
    return [
      const SizedBox(height: 80),
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart,
              size: 64,
              color: AppColors.onBackgroundSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              '還沒有分析數據',
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.onBackgroundPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '開始分析對話後，這裡會顯示你的進展報告',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ];
  }
}
