// lib/features/report/presentation/screens/my_report_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../user_profile/presentation/widgets/about_me_card.dart';
import '../../data/providers/report_providers.dart';
import '../widgets/heat_trend_chart.dart';
import '../widgets/conversation_comparison_chart.dart';
import '../widgets/stage_distribution_chart.dart';

class MyReportScreen extends ConsumerWidget {
  const MyReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(reportDataProvider);
    final isEmpty = report.totalConversations == 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        const AboutMeCard(),
        const SizedBox(height: 24),
        if (isEmpty)
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
      ],
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
