import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class ScreenshotAddedFeedbackCard extends StatelessWidget {
  final int messageCount;
  final bool lastMessageIsFromMe;
  final String lastMessagePreview;
  final bool isAnalyzing;
  final bool canAnalyzeNow;
  final VoidCallback onShowConversation;
  final VoidCallback onAnalyze;

  const ScreenshotAddedFeedbackCard({
    super.key,
    required this.messageCount,
    required this.lastMessageIsFromMe,
    required this.lastMessagePreview,
    required this.isAnalyzing,
    bool? canAnalyzeNow,
    required this.onShowConversation,
    required this.onAnalyze,
  }) : canAnalyzeNow = canAnalyzeNow ?? !lastMessageIsFromMe;

  String get _countLabel {
    final count = messageCount > 0 ? messageCount : 1;
    return '已從截圖加入 $count 則新訊息';
  }

  String get _speakerLabel => lastMessageIsFromMe ? '我說' : '她說';

  String get _preview {
    final trimmed = lastMessagePreview.trim();
    if (trimmed.length <= 36) {
      return trimmed;
    }
    return '${trimmed.substring(0, 36)}...';
  }

  String get _nextStep {
    if (canAnalyzeNow && lastMessageIsFromMe) {
      return '這批截圖含對方的新回覆，按「分析新增內容」後會分析到她最新回覆；最後一則你說的內容先作紀錄，不預測她下一句。';
    }
    if (lastMessageIsFromMe) {
      return '最後一則是你說。等她回覆後，再補上「她說」，我會用最新來回分析下一步。';
    }
    return '最後一則是她說。按「分析新增內容」後，會開始串流整理下一步與完整分析。';
  }

  Color get _bubbleFill => lastMessageIsFromMe
      ? AppColors.ctaStart.withValues(alpha: 0.14)
      : AppColors.primaryLight.withValues(alpha: 0.18);

  Color get _bubbleBorder => lastMessageIsFromMe
      ? AppColors.ctaEnd.withValues(alpha: 0.46)
      : AppColors.primaryLight.withValues(alpha: 0.52);

  Color get _speakerColor =>
      lastMessageIsFromMe ? AppColors.ctaEnd : AppColors.primaryDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle,
                color: AppColors.ctaStart,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _countLabel,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.glassTextPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: lastMessageIsFromMe
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _bubbleFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _bubbleBorder),
              ),
              child: Column(
                crossAxisAlignment: lastMessageIsFromMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '最新：$_speakerLabel',
                    style: AppTypography.bodySmall.copyWith(
                      color: _speakerColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _preview,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.glassTextPrimary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _nextStep,
            style: AppTypography.caption.copyWith(
              color: AppColors.glassTextSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: onShowConversation,
                icon: const Icon(Icons.keyboard_arrow_up, size: 16),
                label: const Text('看上方對話'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ctaStart,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              if (canAnalyzeNow)
                TextButton.icon(
                  onPressed: isAnalyzing ? null : onAnalyze,
                  icon: const Icon(Icons.auto_graph, size: 16),
                  label: const Text('分析新增內容'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
