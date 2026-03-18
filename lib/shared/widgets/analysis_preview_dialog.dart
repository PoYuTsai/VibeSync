// lib/shared/widgets/analysis_preview_dialog.dart
import 'package:flutter/material.dart';

import '../../core/services/message_calculator.dart';
import '../../core/services/usage_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Dialog shown before analysis to preview billed usage.
class AnalysisPreviewDialog extends StatelessWidget {
  final MessagePreview preview;
  final UsageData usage;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onUpgrade;

  const AnalysisPreviewDialog({
    super.key,
    required this.preview,
    required this.usage,
    required this.onConfirm,
    required this.onCancel,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final canProceed = !preview.exceedsLimit &&
        usage.monthlyRemaining >= preview.messageCount &&
        usage.dailyRemaining >= preview.messageCount;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('開始分析前確認', style: AppTypography.titleLarge),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRow('本次預估扣點', '${preview.messageCount} 則'),
          const SizedBox(height: 12),
          _buildRow('本次分析字數', '${preview.charCount} 字'),
          const SizedBox(height: 12),
          _buildRow(
            '本月剩餘額度',
            '${usage.monthlyRemaining} / ${usage.monthlyLimit} 則',
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: usage.monthlyPercentage,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(
              usage.monthlyPercentage > 0.8
                  ? AppColors.warning
                  : AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          _buildRow(
            '今日剩餘額度',
            '${usage.dailyRemaining} / ${usage.dailyLimit} 則',
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: usage.dailyPercentage,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(
              usage.dailyPercentage > 0.8
                  ? AppColors.warning
                  : AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          if (preview.exceedsLimit)
            _buildWarning('這次分析內容太長，請縮短到 5,000 字內後再試。')
          else if (usage.monthlyRemaining < preview.messageCount)
            _buildWarning('本月剩餘額度不足，請升級方案後再分析。')
          else if (usage.dailyRemaining < preview.messageCount)
            _buildWarning('今日剩餘額度不足，明天再來或先升級方案。'),
          if (canProceed) ...[
            const SizedBox(height: 8),
            Text(
              '分析後預估剩餘：本月 '
              '${usage.monthlyRemaining - preview.messageCount} 則 / 今日 '
              '${usage.dailyRemaining - preview.messageCount} 則',
              style: AppTypography.caption,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('取消'),
        ),
        if (!preview.exceedsLimit && !canProceed && onUpgrade != null)
          TextButton(
            onPressed: onUpgrade,
            child: Text(
              '查看升級方案',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ElevatedButton(
          onPressed: canProceed ? onConfirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('確認開始分析'),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodyMedium),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildWarning(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withAlpha(77)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> showAnalysisPreviewDialog({
  required BuildContext context,
  required MessagePreview preview,
  required UsageData usage,
  VoidCallback? onUpgrade,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AnalysisPreviewDialog(
      preview: preview,
      usage: usage,
      onConfirm: () => Navigator.of(dialogContext).pop(true),
      onCancel: () => Navigator.of(dialogContext).pop(false),
      onUpgrade: onUpgrade,
    ),
  );
  return result ?? false;
}
