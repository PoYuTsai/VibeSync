// lib/features/analysis/presentation/widgets/analysis_usage_summary_line.dart
//
// 實扣顯示常駐行（smoke P2 fix 2026-06-11）。
//
// Bruce smoke：「扣幾則」提示只在分析完成現場以 floating SnackBar 彈一次，
// 之後回看都看不到。本 widget 把「本次分析使用 N 則・剩餘 M 則」常駐在結果區，
// 資料來自 result.rawResponse['usage']——隨 lastAnalysisSnapshotJson 持久化，
// 回看（hydration / _restorePersistedAnalysis）也顯示。SnackBar 保留作即時感知，
// 不再是唯一載體。
//
// 注意：「剩餘 M 則」是快照當下的 monthlyRemaining；回看舊分析時若其後又有
// 扣費，此數字反映的是該次分析完成時的剩餘，不是即時值。

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class AnalysisUsageSummaryLine extends StatelessWidget {
  /// `result.rawResponse['usage']`，型別不保證（持久化 JSON round-trip）。
  final Object? usage;

  const AnalysisUsageSummaryLine({super.key, required this.usage});

  /// 「本次分析使用 N 則・剩餘 M 則」；不該顯示時回 null。
  ///
  /// 與 `_syncSubscriptionUsageFromResult` 的 SnackBar 條件一致：
  /// messagesUsed > 0 且非測試帳號才顯示（recognizeOnly 的 0 扣費不顯示）。
  static String? summaryText(Object? usage) {
    if (usage is! Map) return null;
    if (usage['isTestAccount'] == true) return null;
    final messagesUsed = usage['messagesUsed'];
    if (messagesUsed is! num || messagesUsed <= 0) return null;
    final monthlyRemaining = usage['monthlyRemaining'];
    final remainingSuffix =
        monthlyRemaining is num ? '・剩餘 ${monthlyRemaining.round()} 則' : '';
    return '本次分析使用 ${messagesUsed.round()} 則$remainingSuffix';
  }

  @override
  Widget build(BuildContext context) {
    final text = summaryText(usage);
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 14,
            color: AppColors.textSecondary.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
