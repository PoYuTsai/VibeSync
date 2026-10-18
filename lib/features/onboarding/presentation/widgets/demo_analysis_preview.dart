// lib/features/onboarding/presentation/widgets/demo_analysis_preview.dart
//
// 2026-08-01 轉化診斷 Tier 1-1：把 DemoConversation 的零 API 示範分析
// 接進 onboarding，讓前三頁「用演的」而不是「用講的」。
// 只讀 DemoConversation 的資料，不依賴 analysis 的結果 UI——onboarding
// 的示範卡是靜態櫥窗，不需要跟著真實分析畫面演進。
// 2026-10-17 對話分析 v3：示範改成燈號＋局面判讀、任務卡（新流程沒有熱度、
// 階段、雷達，也不再是五種風格）。
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis/domain/entities/guide_v3_result.dart';
import '../../data/demo_conversation.dart';

Color _lightColor(GuideV3Light light) => switch (light) {
      GuideV3Light.green => AppColors.success,
      GuideV3Light.yellow => AppColors.warning,
      GuideV3Light.red => AppColors.error,
    };

/// 第 2 頁「即時看懂她的訊號」：三則對話泡泡＋燈號＋局面判讀。
class DemoSignalPreview extends StatelessWidget {
  const DemoSignalPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final lightColor = _lightColor(DemoConversation.demoLight);
    return _DemoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final msg in DemoConversation.messages) ...[
            Align(
              alignment:
                  msg.isFromMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: msg.isFromMe
                      ? AppColors.ctaStart.withValues(alpha: 0.28)
                      : Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  msg.content,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: lightColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: lightColor.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: lightColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      DemoConversation.demoLight.label,
                      style: AppTypography.labelMedium.copyWith(
                        color: lightColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '局面判讀',
                style: AppTypography.bodySmall.copyWith(
                  color:
                      AppColors.onBackgroundSecondary.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            DemoConversation.demoJudgment,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 第 3 頁「該回的時候給你 3–5 張回覆」：三張示範任務卡（任務標籤＋句子）。
class DemoCardsPreview extends StatelessWidget {
  const DemoCardsPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return _DemoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final card in DemoConversation.demoCards)
            _CardRow(label: card.task.label, reply: card.text),
        ],
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.label, required this.reply});

  final String label;
  final String reply;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reply,
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 共用外框：暗面卡片＋「示範」角標，明示這是預錄櫥窗不是真實資料。
class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.ctaStart.withValues(alpha: 0.60),
              ),
            ),
            child: Text(
              '示範',
              style: AppTypography.caption.copyWith(
                color: AppColors.ctaStart,
              ),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
