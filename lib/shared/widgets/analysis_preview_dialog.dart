// lib/shared/widgets/analysis_preview_dialog.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/services/message_calculator.dart';
import '../../core/services/usage_service.dart';

/// Dialog shown before analysis to preview message count and usage
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
      title: Text('確認分析', style: AppTypography.titleLarge),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Message count
          _buildRow('本次分析', '${preview.messageCount} 則訊息'),
          const SizedBox(height: 12),

          // Monthly usage
          _buildRow(
            '月額度',
            '剩餘 ${usage.monthlyRemaining} / ${usage.monthlyLimit} 則',
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: usage.monthlyPercentage,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(
              usage.monthlyPercentage > 0.8
                  ? AppColors.warning
                  : AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),

          // Daily usage
          _buildRow(
            '今日額度',
            '剩餘 ${usage.dailyRemaining} / ${usage.dailyLimit} 則',
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: usage.dailyPercentage,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(
              usage.dailyPercentage > 0.8
                  ? AppColors.warning
                  : AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),

          // Warnings
          if (preview.exceedsLimit)
            _buildWarning('內容過長，請分批分析 (上限 5,000 字)')
          else if (usage.monthlyRemaining < preview.messageCount)
            _buildWarning('月額度不足，請升級方案')
          else if (usage.dailyRemaining < preview.messageCount)
            _buildWarning('今日額度已用完，明天再試'),

          // After analysis preview
          if (canProceed) ...[
            const SizedBox(height: 8),
            Text(
              '分析後剩餘: 月 ${usage.monthlyRemaining - preview.messageCount} 則 / 日 ${usage.dailyRemaining - preview.messageCount} 則',
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
        if (!canProceed && onUpgrade != null)
          TextButton(
            onPressed: onUpgrade,
            child: Text(
              '升級方案',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ElevatedButton(
          onPressed: canProceed ? onConfirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('確認分析'),
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
        color: AppColors.warning.withAlpha(25), // ~0.1 opacity
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withAlpha(77)), // ~0.3 opacity
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

/// Helper function to show the analysis preview dialog
Future<bool> showAnalysisPreviewDialog({
  required BuildContext context,
  required MessagePreview preview,
  required UsageData usage,
  VoidCallback? onUpgrade,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AnalysisPreviewDialog(
      preview: preview,
      usage: usage,
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
      onUpgrade: onUpgrade,
    ),
  );
  return result ?? false;
}
