import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 串流生成進度卡（2026-08-18 呈現精修第 2 包）：server 每完成一段就推一個
/// 真實進度事件，這裡由上而下列出——已完成的打勾、最新一項亮色＋轉圈。
/// 只顯示最後 [maxVisible] 項，避免長生成把卡撐高。
/// 開場白與新話題共用；analysis 的串流摘要卡是另一套（含內容片段），不混用。
class StreamProgressTicker extends StatelessWidget {
  const StreamProgressTicker({
    super.key,
    required this.labels,
    this.maxVisible = 4,
  });

  final List<String> labels;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final visible = labels.length <= maxVisible
        ? labels
        : labels.sublist(labels.length - maxVisible);
    final hiddenCount = labels.length - visible.length;

    return Container(
      key: const ValueKey('stream-progress-ticker'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.coachBackgroundMid.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.coachAccent.withValues(alpha: 0.36),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI 即時生成中',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.coachAccentBright,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hiddenCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '⋯ 已完成 $hiddenCount 步',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.6),
              ),
            ),
          ],
          for (var i = 0; i < visible.length; i++) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (i == visible.length - 1)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.coachAccentBright,
                    ),
                  )
                else
                  const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: AppColors.coachAccent,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    visible[i],
                    style: AppTypography.bodySmall.copyWith(
                      color: i == visible.length - 1
                          ? AppColors.onBackgroundPrimary
                          : AppColors.onBackgroundSecondary,
                      fontWeight: i == visible.length - 1
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
