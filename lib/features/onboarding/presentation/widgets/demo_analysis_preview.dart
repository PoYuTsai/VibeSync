// lib/features/onboarding/presentation/widgets/demo_analysis_preview.dart
//
// 2026-08-01 轉化診斷 Tier 1-1：把 DemoConversation 的零 API 示範分析
// 接進 onboarding，讓前三頁「用演的」而不是「用講的」。
// 只讀 DemoConversation 的資料，不依賴 analysis 的結果 UI——onboarding
// 的示範卡是靜態櫥窗，不需要跟著真實分析畫面演進。
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/demo_conversation.dart';

const _styleOrder = ['extend', 'resonate', 'tease', 'humor', 'coldRead'];
const _styleLabels = {
  'extend': '延展',
  'resonate': '共鳴',
  'tease': '調情',
  'humor': '幽默',
  'coldRead': '冷讀',
};

/// 第 2 頁「即時看懂她的訊號」：三則對話泡泡＋投入度分數條＋心理解讀。
class DemoSignalPreview extends StatelessWidget {
  const DemoSignalPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final result = DemoConversation.demoResult;
    return _DemoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final msg in DemoConversation.messages) ...[
            Align(
              alignment: msg.isFromMe
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
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
              Text(
                '投入度',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary
                      .withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Stack(
                      children: [
                        Container(
                            color: Colors.white.withValues(alpha: 0.10)),
                        FractionallySizedBox(
                          widthFactor: result.enthusiasmScore / 100,
                          child: Container(color: AppColors.ctaStart),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${result.enthusiasmScore}',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.ctaStart,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                result.enthusiasmLevel.label,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.ctaStart,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result.psychology.subtext,
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

/// 第 3 頁「五種風格」：五句示範回覆，教練推薦那句標亮。
class DemoStylesPreview extends StatelessWidget {
  const DemoStylesPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final result = DemoConversation.demoResult;
    final recommendedKey = result.finalRecommendation.pick;
    return _DemoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final key in _styleOrder)
            _StyleRow(
              label: _styleLabels[key]!,
              reply: result.replies[key]!,
              recommended: key == recommendedKey,
            ),
        ],
      ),
    );
  }
}

class _StyleRow extends StatelessWidget {
  const _StyleRow({
    required this.label,
    required this.reply,
    required this.recommended,
  });

  final String label;
  final String reply;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: recommended
            ? AppColors.ctaStart.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: recommended
            ? Border.all(color: AppColors.ctaStart.withValues(alpha: 0.60))
            : null,
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
          if (recommended) ...[
            const SizedBox(width: 8),
            Text(
              '教練推薦',
              style: AppTypography.caption.copyWith(
                color: AppColors.ctaStart,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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
