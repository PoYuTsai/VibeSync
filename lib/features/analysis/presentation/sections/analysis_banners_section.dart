import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/analysis_models.dart';

/// 「正在重新產生完整分析」進度橫幅（升級後刷新回覆選項時顯示）。
class PremiumRefreshBanner extends StatelessWidget {
  const PremiumRefreshBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '正在重新產生完整分析，完成後會更新新版回覆選項。',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.ctaStart,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 冰點放棄建議橫幅（shouldGiveUp）。
class GiveUpAdviceBanner extends StatelessWidget {
  const GiveUpAdviceBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(TablerIcons.alert_triangle,
              size: 20, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '這段互動目前不建議再投入，先保護自己的時間與情緒成本。',
              style: AppTypography.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一致性提醒橫幅。
class ReminderBanner extends StatelessWidget {
  const ReminderBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(TablerIcons.message_circle,
              size: 18, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodyMedium.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Analyze V2 決策卡（Phase 1c）：replyMode none／single 時取代放棄橫幅與
/// 回覆輪播——「先不要回」「資料不夠」「先收尾」三種，和回覆區結構上互斥。
class AnalysisDecisionCard extends StatelessWidget {
  final AnalysisDecisionV2 decision;
  final VoidCallback? onCopyClosingMessage;

  const AnalysisDecisionCard({
    super.key,
    required this.decision,
    this.onCopyClosingMessage,
  });

  static String titleFor(AnalysisDecisionV2 decision) =>
      switch (decision.messageDecision) {
        'need_context' => '資料不夠，先補截圖',
        'acknowledge_and_stop' => '這輪先收尾',
        _ => '這輪先不要回',
      };

  @override
  Widget build(BuildContext context) {
    final closingMessage = decision.closingMessage;
    final isNeedContext = decision.messageDecision == 'need_context';
    final accent = isNeedContext ? AppColors.textSecondary : AppColors.error;
    return Container(
      key: const ValueKey('analysis-decision-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isNeedContext
                    ? TablerIcons.photo_search
                    : TablerIcons.hand_stop,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child:
                    Text(titleFor(decision), style: AppTypography.titleSmall),
              ),
            ],
          ),
          if (decision.reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(decision.reason, style: AppTypography.bodyMedium),
          ],
          if (decision.stopCondition.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              isNeedContext
                  ? '補上後再分析：${decision.stopCondition}'
                  : '等到這時候再回：${decision.stopCondition}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (closingMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(closingMessage, style: AppTypography.bodyMedium),
            ),
            if (onCopyClosingMessage != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onCopyClosingMessage,
                  icon: const Icon(TablerIcons.copy, size: 16),
                  label: const Text('複製收尾句'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
