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
/// 「先不要回」另有「下一步」區塊：等待條件、新話題重開入口，以及收合在
/// 「我還是想回」後面的備用句（沒有備用句就展開成通用提醒）。
class AnalysisDecisionCard extends StatefulWidget {
  final AnalysisDecisionV2 decision;
  final VoidCallback? onCopyClosingMessage;

  /// do_not_send：直達這位對象的新話題頁；null（例如歷史紀錄）就不出按鈕。
  final VoidCallback? onStartNewTopic;

  /// do_not_send 的備用句複製；null 就只顯示句子不給複製。
  final VoidCallback? onCopyAgainstAdviceLine;

  const AnalysisDecisionCard({
    super.key,
    required this.decision,
    this.onCopyClosingMessage,
    this.onStartNewTopic,
    this.onCopyAgainstAdviceLine,
  });

  static String titleFor(AnalysisDecisionV2 decision) =>
      switch (decision.messageDecision) {
        AnalysisMessageDecision.needContext => '資料不夠，先補截圖',
        AnalysisMessageDecision.acknowledgeAndStop => '這輪先收尾',
        _ => '這輪先不要回',
      };

  @override
  State<AnalysisDecisionCard> createState() => _AnalysisDecisionCardState();
}

class _AnalysisDecisionCardState extends State<AnalysisDecisionCard> {
  bool _showAgainstAdviceLine = false;

  @override
  void didUpdateWidget(AnalysisDecisionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 換了一輪分析就重新收合，不讓上一輪的「我還是想回」沿用到新結果。
    if (!identical(oldWidget.decision, widget.decision)) {
      _showAgainstAdviceLine = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision = widget.decision;
    final closingMessage = decision.sendableClosingMessage;
    final isNeedContext =
        decision.messageDecision == AnalysisMessageDecision.needContext;
    final isDoNotSend =
        decision.messageDecision == AnalysisMessageDecision.doNotSend;
    final againstAdviceLine = decision.againstAdviceLine;
    final accent = isNeedContext ? AppColors.textSecondary : AppColors.error;
    final secondaryStyle =
        AppTypography.bodySmall.copyWith(color: AppColors.textSecondary);
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
                child: Text(AnalysisDecisionCard.titleFor(decision),
                    style: AppTypography.titleSmall),
              ),
            ],
          ),
          if (decision.reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(decision.reason, style: AppTypography.bodyMedium),
          ],
          if (isDoNotSend) ...[
            const SizedBox(height: 12),
            Text('下一步', style: AppTypography.titleSmall),
            if (decision.stopCondition.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('等到這時候再回：${decision.stopCondition}', style: secondaryStyle),
            ],
            const SizedBox(height: 6),
            Text('她一直沒動靜就別追這條，過幾天用新話題重開。', style: secondaryStyle),
            if (widget.onStartNewTopic != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onStartNewTopic,
                  icon: const Icon(TablerIcons.message_circle, size: 18),
                  label: const Text('用新話題重新開'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (!_showAgainstAdviceLine)
              TextButton(
                onPressed: () => setState(() => _showAgainstAdviceLine = true),
                child: const Text('我還是想回'),
              )
            else if (againstAdviceLine == null)
              Text(
                '教練不建議現在回。真的要回，只傳一句不帶問號、不追問的短句，傳完就停。',
                style: secondaryStyle,
              )
            else ...[
              Text('教練不建議現在回。真的要回，這句壓力最低：', style: secondaryStyle),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(againstAdviceLine, style: AppTypography.bodyMedium),
              ),
              if (widget.onCopyAgainstAdviceLine != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: widget.onCopyAgainstAdviceLine,
                    icon: const Icon(TablerIcons.copy, size: 16),
                    label: const Text('複製這句'),
                  ),
                ),
              ],
            ],
          ] else if (decision.stopCondition.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              isNeedContext
                  ? '補上後再分析：${decision.stopCondition}'
                  : '等到這時候再回：${decision.stopCondition}',
              style: secondaryStyle,
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
            if (widget.onCopyClosingMessage != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: widget.onCopyClosingMessage,
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
