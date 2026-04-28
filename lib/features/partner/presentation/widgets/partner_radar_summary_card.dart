// lib/features/partner/presentation/widgets/partner_radar_summary_card.dart
//
// Renders a 5-dimension radar from the latest conversation's
// `lastAnalysisSnapshotJson`. Reuses `AnalysisResult.fromJson` so dimension
// parsing logic stays in one place. Returns a fallback Card if the
// snapshot is missing, malformed, or has no `dimensions` key.
//
// Post-A2 visual polish (2026-04-28): glass surface alignment only.
// NO new dimensions, NO AI interpretation lines, NO fake per-dim scores
// (per scope lock). Same fallback copy.
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis/domain/entities/analysis_models.dart'
    show AnalysisResult;
import '../../../conversation/domain/entities/conversation.dart';

class PartnerRadarSummaryCard extends StatelessWidget {
  final Conversation? latestConversation;
  const PartnerRadarSummaryCard({super.key, required this.latestConversation});

  @override
  Widget build(BuildContext context) {
    final dims = _parseDimensions(latestConversation);
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
    final labels = const ['熱度', '互動', '深度', '回應', '情感'];
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
                  fontSize: 8,
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Reuse path: `AnalysisResult.fromJson(...).dimensionScores` already returns
  /// `Map<String, int>?` with default-50 per key, parsed by the package-private
  /// `_parseDimensions` inside `analysis_models.dart`. Catching here ensures a
  /// malformed snapshot string degrades to the "尚未分析" fallback rather than
  /// crashing the detail screen.
  static Map<String, int>? _parseDimensions(Conversation? c) {
    final raw = c?.lastAnalysisSnapshotJson;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AnalysisResult.fromJson(json).dimensionScores;
    } catch (_) {
      return null;
    }
  }
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }
}
