import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/analysis_telemetry.dart';
import '../../domain/services/screenshot_recognition_helper.dart';

/// Debug 限定的量測診斷文案（AnalysisTelemetry 是 domain 實體，
/// 這些純函式供 OCR/分析面板與辨識中診斷盒共用）。

String formatTelemetryBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

String formatTelemetryDuration(Duration? duration) {
  if (duration == null) {
    return '--';
  }

  final seconds = duration.inMilliseconds / 1000;
  return '${seconds.toStringAsFixed(seconds >= 10 ? 0 : 1)} 秒';
}

String? recognizeTelemetryRecognitionSummary(AnalysisTelemetry telemetry) {
  if (telemetry.recognizedClassification == null &&
      telemetry.recognizedSideConfidence == null &&
      telemetry.recognizedMessageCount == null) {
    return null;
  }

  final parts = <String>[
    if (telemetry.recognizedClassification != null)
      '分類 ${ScreenshotRecognitionHelper.classificationLabel(telemetry.recognizedClassification!)}',
    if (telemetry.recognizedSideConfidence != null)
      '方向 ${ScreenshotRecognitionHelper.sideConfidenceLabel(telemetry.recognizedSideConfidence!)}',
    if (telemetry.recognizedMessageCount != null)
      '訊息 ${telemetry.recognizedMessageCount} 則',
    if ((telemetry.uncertainSideCount ?? 0) > 0)
      '待確認 ${telemetry.uncertainSideCount} 則',
  ];

  return parts.isEmpty ? null : parts.join('｜');
}

String? recognizeTelemetryNormalizationSummary(AnalysisTelemetry telemetry) {
  final parts = <String>[
    if ((telemetry.quotedPreviewAttachedCount ?? 0) > 0)
      '引用併回 ${telemetry.quotedPreviewAttachedCount} 次',
    if ((telemetry.quotedPreviewRemovedCount ?? 0) > 0 &&
        (telemetry.quotedPreviewAttachedCount ?? 0) == 0)
      '引用忽略 ${telemetry.quotedPreviewRemovedCount} 次',
    if ((telemetry.continuityAdjustedCount ?? 0) > 0)
      '方向校正 ${telemetry.continuityAdjustedCount} 次',
    if ((telemetry.groupedAdjustedCount ?? 0) > 0)
      '群組校正 ${telemetry.groupedAdjustedCount} 次',
    if ((telemetry.layoutFirstAdjustedCount ?? 0) > 0)
      '版面分群 ${telemetry.layoutFirstAdjustedCount} 次',
    if ((telemetry.overlapRemovedCount ?? 0) > 0)
      '重疊去重 ${telemetry.overlapRemovedCount} 次',
  ];

  return parts.isEmpty ? null : parts.join('｜');
}

String? recognizeTelemetryContextSummary(AnalysisTelemetry telemetry) {
  if (telemetry.contextMode == null &&
      telemetry.truncatedMessageCount == null &&
      telemetry.conversationSummaryUsed == false) {
    return null;
  }

  final modeLabel = telemetry.contextMode == 'opening_plus_recent'
      ? '上下文 開頭+最近'
      : telemetry.contextMode == 'full'
          ? '上下文 全量'
          : null;

  final parts = <String>[
    if (modeLabel != null) modeLabel,
    if ((telemetry.inputMessageCount ?? 0) > 0 &&
        (telemetry.compiledMessageCount ?? 0) > 0)
      '送出 ${telemetry.compiledMessageCount}/${telemetry.inputMessageCount} 則',
    if ((telemetry.truncatedMessageCount ?? 0) > 0)
      '省略 ${telemetry.truncatedMessageCount} 則',
    if (telemetry.conversationSummaryUsed) '含舊摘要',
  ];

  return parts.isEmpty ? null : parts.join('｜');
}

String analysisTelemetryRequestLabel(AnalysisTelemetry telemetry) {
  switch (telemetry.requestType) {
    case 'my_message':
      return '上次「我說」量測';
    case 'optimize_message':
      return '上次優化量測';
    case 'analyze_with_images':
      return '上次帶圖分析量測';
    default:
      return '上次分析量測';
  }
}

String analysisTelemetryTransportSummary(AnalysisTelemetry telemetry) {
  final retrySummary =
      telemetry.retryCount > 0 ? '重試 ${telemetry.retryCount} 次' : null;
  final fallbackSummary = telemetry.fallbackUsed ? '有 fallback' : null;
  final timeoutSummary = telemetry.timeoutDuration != null
      ? '逾時上限 ${formatTelemetryDuration(telemetry.timeoutDuration)}'
      : null;

  final parts = <String>[
    '請求 ${formatTelemetryBytes(telemetry.requestBodyBytes)}',
    '本機準備 ${formatTelemetryDuration(telemetry.payloadPreparationDuration)}',
    '往返 ${formatTelemetryDuration(telemetry.roundTripDuration)}',
    if (retrySummary != null) retrySummary,
    if (fallbackSummary != null) fallbackSummary,
    if (timeoutSummary != null) timeoutSummary,
  ];

  return parts.join('｜');
}

String? analysisTelemetryQuotaSummary(AnalysisTelemetry telemetry) {
  final estimatedCount =
      telemetry.estimatedMessageCount ?? telemetry.chargedMessageCount;

  if (telemetry.shouldChargeQuota == true) {
    final chargedCount = telemetry.chargedMessageCount ?? estimatedCount;
    if ((chargedCount ?? 0) > 0) {
      return '本次扣 $chargedCount 則訊息額度';
    }
    return '本次會扣訊息額度';
  }

  if (telemetry.requestType == 'recognize_only' ||
      telemetry.quotaReason == 'recognize_only_free') {
    return '本次純辨識，不扣額度';
  }

  if (telemetry.quotaReason == 'test_account_waived') {
    if ((estimatedCount ?? 0) > 0) {
      return '測試帳號，本次未扣額度（原本會扣 $estimatedCount 則）';
    }
    return '測試帳號，本次未扣額度';
  }

  if (telemetry.shouldChargeQuota == false && (estimatedCount ?? 0) > 0) {
    return '本次未扣額度';
  }

  return null;
}

/// 守門 chip 的展示資料。severity → 顏色/圖示的映射由 screen 完成
/// （守門評估器與 severity 列舉屬 data 層）。
@immutable
class TelemetryGuardrailChipData {
  const TelemetryGuardrailChipData({
    required this.color,
    required this.icon,
    required this.label,
    required this.detail,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String detail;
}

/// 守門 chips＋逐條說明。
class TelemetryGuardrailSection extends StatelessWidget {
  const TelemetryGuardrailSection({super.key, required this.guardrails});

  final List<TelemetryGuardrailChipData> guardrails;

  @override
  Widget build(BuildContext context) {
    if (guardrails.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: guardrails.map((guardrail) {
              final color = guardrail.color;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: color.withValues(alpha: 0.20),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      guardrail.icon,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      guardrail.label,
                      style: AppTypography.bodySmall.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          ...guardrails.map(
            (guardrail) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${guardrail.label}：${guardrail.detail}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「上次 OCR 量測」debug 面板。
class OcrTelemetryPanel extends StatelessWidget {
  const OcrTelemetryPanel({
    super.key,
    required this.telemetry,
    required this.guardrails,
  });

  final AnalysisTelemetry telemetry;
  final List<TelemetryGuardrailChipData> guardrails;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '上次 OCR 量測',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            telemetry.cacheHit
                ? '本次直接使用本機快取結果，未重新送出 OCR 請求'
                : '請求 ${formatTelemetryBytes(telemetry.requestBodyBytes)}｜本機準備 ${formatTelemetryDuration(telemetry.payloadPreparationDuration)}｜往返 ${formatTelemetryDuration(telemetry.roundTripDuration)}',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (analysisTelemetryQuotaSummary(telemetry) != null)
            Text(
              analysisTelemetryQuotaSummary(telemetry)!,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          Text(
            telemetry.cacheHit
                ? '本次使用本機快取，未重新上傳或呼叫 AI'
                : 'AI ${formatTelemetryDuration(telemetry.edgeAiDuration)}｜估計傳輸/排隊 ${formatTelemetryDuration(telemetry.estimatedTransferDuration)}',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (recognizeTelemetryRecognitionSummary(telemetry) != null)
            Text(
              recognizeTelemetryRecognitionSummary(telemetry)!,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          if (recognizeTelemetryNormalizationSummary(telemetry) != null)
            Text(
              recognizeTelemetryNormalizationSummary(telemetry)!,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          if (recognizeTelemetryContextSummary(telemetry) != null)
            Text(
              recognizeTelemetryContextSummary(telemetry)!,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          TelemetryGuardrailSection(guardrails: guardrails),
        ],
      ),
    );
  }
}

/// 「上次分析量測」debug 面板。
class AnalysisTelemetryPanel extends StatelessWidget {
  const AnalysisTelemetryPanel({
    super.key,
    required this.telemetry,
    required this.guardrails,
  });

  final AnalysisTelemetry telemetry;
  final List<TelemetryGuardrailChipData> guardrails;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.info.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            analysisTelemetryRequestLabel(telemetry),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            analysisTelemetryTransportSummary(telemetry),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (analysisTelemetryQuotaSummary(telemetry) != null)
            Text(
              analysisTelemetryQuotaSummary(telemetry)!,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          Text(
            'AI ${formatTelemetryDuration(telemetry.edgeAiDuration)}｜估計傳輸/排隊 ${formatTelemetryDuration(telemetry.estimatedTransferDuration)}',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (recognizeTelemetryContextSummary(telemetry) != null)
            Text(
              recognizeTelemetryContextSummary(telemetry)!,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          TelemetryGuardrailSection(guardrails: guardrails),
        ],
      ),
    );
  }
}
