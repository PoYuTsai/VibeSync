import 'package:flutter/material.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// 分析／辨識錯誤卡：訊息、引導文案與動作列（主要動作、強制重新辨識、
/// 次要關閉）。
///
/// 錯誤語意（action 種類、origin、文案推導）全由 screen 決定後以字串與
/// 旗標傳入；[busy] 為分析或辨識進行中，動作一律停用。
class AnalysisErrorCard extends StatelessWidget {
  const AnalysisErrorCard({
    super.key,
    required this.message,
    required this.guidance,
    required this.primaryActionLabel,
    required this.secondaryActionLabel,
    required this.showSecondaryAction,
    required this.showForceReRecognize,
    required this.busy,
    required this.onPrimaryAction,
    required this.onForceReRecognize,
    required this.onDismiss,
  });

  final String message;
  final String? guidance;

  /// null＝沒有主要動作按鈕（錯誤無建議動作）。
  final String? primaryActionLabel;
  final String secondaryActionLabel;
  final bool showSecondaryAction;
  final bool showForceReRecognize;
  final bool busy;
  final VoidCallback onPrimaryAction;
  final VoidCallback onForceReRecognize;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.error),
                ),
              ),
            ],
          ),
          if (guidance != null) ...[
            const SizedBox(height: 10),
            Text(
              guidance!,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (primaryActionLabel != null)
                ElevatedButton(
                  onPressed:
                      AppHaptics.onPress(busy ? null : onPrimaryAction),
                  child: Text(primaryActionLabel!),
                ),
              // 強制重新辨識按鈕（當有之前的圖片可以重試時）
              if (showForceReRecognize)
                OutlinedButton.icon(
                  onPressed: busy ? null : onForceReRecognize,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('強制重新辨識'),
                ),
              if (showSecondaryAction)
                OutlinedButton(
                  onPressed: busy ? null : onDismiss,
                  child: Text(secondaryActionLabel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
