// lib/features/partner/presentation/widgets/partner_radar_summary_card.dart
//
// Renders a 5-dimension radar from the latest conversation's
// `lastAnalysisSnapshotJson`. Reuses `AnalysisResult.fromJson` so dimension
// parsing logic stays in one place. Returns a fallback Card if the
// snapshot is missing, malformed, or has no `dimensions` key.
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
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('最新對話尚未分析'),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最新對話 5 維', style: AppTypography.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: RadarChart(
                RadarChartData(
                  radarShape: RadarShape.polygon,
                  tickCount: 4,
                  dataSets: [
                    RadarDataSet(
                      fillColor: AppColors.primary.withValues(alpha: 0.2),
                      borderColor: AppColors.primary,
                      borderWidth: 2,
                      entryRadius: 3,
                      dataEntries:
                          values.map((v) => RadarEntry(value: v)).toList(),
                    ),
                  ],
                  titleTextStyle: AppTypography.bodySmall,
                  getTitle: (i, _) =>
                      RadarChartTitle(text: labels[i % labels.length]),
                  radarBorderData:
                      const BorderSide(color: AppColors.glassBorder),
                  gridBorderData: const BorderSide(color: AppColors.glassBorder),
                  tickBorderData: const BorderSide(color: AppColors.glassBorder),
                  ticksTextStyle:
                      AppTypography.bodySmall.copyWith(fontSize: 8),
                ),
              ),
            ),
          ],
        ),
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
