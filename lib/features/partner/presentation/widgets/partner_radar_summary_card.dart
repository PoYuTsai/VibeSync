// lib/features/partner/presentation/widgets/partner_radar_summary_card.dart
//
// Renders a 5-dimension radar from the latest conversation's
// `lastAnalysisSnapshotJson`. Dimension parsing lives in
// `LatestAnalyzedFragment.dimensionScores` (v2 reuses `AnalysisResult.fromJson`;
// v3 reads the relation radar). Returns a fallback Card if the snapshot is
// missing, malformed, or has no `dimensions` key.
//
// Post-A2 visual polish (2026-04-28): glass surface alignment only.
// NO new dimensions, NO AI interpretation lines, NO fake per-dim scores
// (per scope lock). Same fallback copy.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis/domain/services/latest_analyzed_fragment.dart';
import '../../../conversation/domain/entities/conversation.dart';

class PartnerRadarSummaryCard extends StatelessWidget {
  /// 這位對象的對話（順序不拘）。雷達畫最近更新那段；「是不是 v3」看最近分析過的那段
  ///（[LatestAnalyzedFragment]，對象頁同一條規則）。
  final List<Conversation> conversations;
  const PartnerRadarSummaryCard({super.key, required this.conversations});

  @override
  Widget build(BuildContext context) {
    final latest = LatestAnalyzedFragment.of(conversations);
    // 改版前的 v3（任務卡）沒有五維雷達（Eric 2026-10-17）：不顯示，也不說「尚未分析」；
    // v3 帶了雷達就跟 v2 一樣畫（Bruce 2026-10-19 路線二）。
    if (latest?.lacksRadar ?? false) return const SizedBox.shrink();
    // 畫的是最近更新那段：那段還沒分析就照舊說「最新對話尚未分析」。
    final dims =
        latest != null && identical(latest.conversation, _newest(conversations))
            ? latest.dimensionScores
            : null;
    if (dims == null) {
      return _GlassShell(
        child: Text(
          '最新對話尚未分析',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
        ),
      );
    }

    final order = const [
      'heat',
      'engagement',
      'topicDepth',
      'replyWillingness',
      'emotionalConnection',
    ];
    final labels = const ['整體投入', '回覆投入', '深度', '回應', '情感'];
    final values =
        order.map((k) => (dims[k] ?? 50).toDouble()).toList(growable: false);

    return _GlassShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最新對話 5 維',
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.onBackgroundPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: RadarChart(
              RadarChartData(
                radarShape: RadarShape.polygon,
                tickCount: 4,
                dataSets: [
                  RadarDataSet(
                    fillColor: AppColors.primaryLight.withValues(alpha: 0.22),
                    borderColor: AppColors.primaryLight,
                    borderWidth: 2,
                    entryRadius: 3,
                    dataEntries:
                        values.map((v) => RadarEntry(value: v)).toList(),
                  ),
                ],
                titleTextStyle: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                ),
                getTitle: (i, _) =>
                    RadarChartTitle(text: labels[i % labels.length]),
                radarBorderData: BorderSide(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                gridBorderData: BorderSide(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                tickBorderData: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                ticksTextStyle: AppTypography.bodySmall.copyWith(
                  fontSize: 12,
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
            ),
          ),
        ],
      ),
    );
  }

  static Conversation? _newest(List<Conversation> conversations) =>
      conversations.isEmpty
          ? null
          : conversations.reduce(
              (a, b) => b.updatedAt.isAfter(a.updatedAt) ? b : a,
            );
}

/// Shared glass shell used by both the radar render and the fallback path.
class _GlassShell extends StatelessWidget {
  final Widget child;
  const _GlassShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}
