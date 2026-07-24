import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'brand/brand_kit.dart';

/// 公式回覆共用顯示區塊（2026-07-24 公式回覆計畫 §10.1）。
///
/// Opener＝「公式開場」、New Topic＝「公式新話題」共用同一語意：
/// - 每張卡顯示完整 openingLine（可直接傳）＋「為什麼好接」教練註解。
/// - 複製只複製 openingLine（snackbar 語氣由呼叫端沿用該頁既有樣式）。
/// - 空清單時整區不渲染由呼叫端負責（`if (entries.isNotEmpty)`），
///   不留標題／間距；只有一則時只渲染一張，不補空卡。
/// - 垂直自適應高度：不套 opener 固定 220 高橫卡，180/300 cap 內容
///   不會被 ellipsis。
/// - 本案不掛 outcome/reaction bar（拍板）。
class FormulaReplyEntry {
  const FormulaReplyEntry({
    required this.openingLine,
    required this.whyItWorks,
  });

  final String openingLine;
  final String whyItWorks;
}

class FormulaReplySection extends StatelessWidget {
  const FormulaReplySection({
    super.key,
    required this.title,
    required this.entries,
    required this.onCopyOpeningLine,
  });

  static const subtitle = '具體線索＋你的當下反應＋一個好接的開口';

  final String title;
  final List<FormulaReplyEntry> entries;
  final ValueChanged<FormulaReplyEntry> onCopyOpeningLine;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AppTypography.caption.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _FormulaReplyCard(
            key: ValueKey('formula-reply-card-$i'),
            index: i,
            entry: entries[i],
            onCopyOpeningLine: () => onCopyOpeningLine(entries[i]),
          ),
        ],
      ],
    );
  }
}

class _FormulaReplyCard extends StatelessWidget {
  const _FormulaReplyCard({
    super.key,
    required this.index,
    required this.entry,
    required this.onCopyOpeningLine,
  });

  final int index;
  final FormulaReplyEntry entry;
  final VoidCallback onCopyOpeningLine;

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      tone: BrandVisualTone.coach,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 可直接傳的訊息本體（自適應高度，不 ellipsis）。
          Container(
            key: ValueKey('formula-reply-opening-line-$index'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.coachBackgroundMid.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.coachAccent.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '可直接傳',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.openingLine,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onCopyOpeningLine,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('複製'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.ctaStart,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '為什麼好接',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.coachAccentBright.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.whyItWorks,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
