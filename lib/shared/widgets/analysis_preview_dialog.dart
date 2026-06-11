// lib/shared/widgets/analysis_preview_dialog.dart
//
// ADR #19 r3 分析前預覽：
// - standard 帶（≤2000 字）：靜態區間文案「依對話複雜度使用 1–10 則」，
//   不報精確值（分析後才顯示 server 實扣）。
// - overcharge 帶（2001~4000 字）：本 dialog 即是「>2000 字確認框」，
//   顯示精確「本次將使用 20 則」。額度檢查先於確認（定案 #4）：額度不足
//   時 caller 已走額度不足路徑，這裡的 canProceed 只是防禦層。
// - reject 帶（4001+）：caller 在呼叫本 dialog 前就擋下，不會進來。
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

  bool get _isOvercharge => preview.band.kind == BillingBandKind.overcharge;

  int get _requiredUnits => preview.band.units ?? 0;

  @override
  Widget build(BuildContext context) {
    // 額度檢查用實際算出的則數（定案 #4），但 standard 帶的 UI 只報區間。
    final canProceed = preview.band.kind != BillingBandKind.reject &&
        usage.monthlyRemaining >= _requiredUnits &&
        usage.dailyRemaining >= _requiredUnits;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        _isOvercharge ? '內容較長，確認後才會扣' : '開始分析前',
        style: AppTypography.titleLarge,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isOvercharge) ...[
            _buildRow('本次將使用', '$_requiredUnits 則'),
            const SizedBox(height: 12),
            _buildRow('新增內容長度', '約 ${preview.billableChars} 字'),
          ] else
            _buildRow('預計使用', '依對話複雜度 1–10 則'),
          const SizedBox(height: 12),
          _buildRow(
            '本月剩餘',
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
            '今日剩餘',
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
          if (usage.monthlyRemaining < _requiredUnits)
            _buildWarning('這個月的分析次數不夠了，升級後再繼續。')
          else if (usage.dailyRemaining < _requiredUnits)
            _buildWarning('今天的分析次數不夠了，明天再來或先升級方案。'),
          const SizedBox(height: 12),
          if (_isOvercharge)
            Text(
              '新增內容超過 2000 字，本次分析會一次使用 20 則。'
              '分批分析（每批 2000 字以內，各 10 則）合計也是 20 則，'
              '不會比較貴；不過內容太長時分批分析的品質通常更好。',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            )
          else ...[
            Text(
              '只有送出完整分析才會扣次數。先讀截圖、不做完整分析，不會扣次數。'
              '分析完成後會顯示實際使用的則數。',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '重新分析會用目前整段對話重新判斷；舊訊息只作為背景，不重複扣額度，這次只計算新增內容。',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
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
          child: Text(_isOvercharge ? '確認使用 $_requiredUnits 則' : '開始分析'),
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
