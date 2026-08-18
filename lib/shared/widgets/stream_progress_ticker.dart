import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 串流生成狀態列（2026-08-19 v2 精修）：一行「AI 即時生成中 · 目前階段」。
/// v1 的多行打勾清單改由骨架卡承擔「一塊一塊完成」的體感；這行只負責
/// 顯示沒有骨架卡對應的階段（解讀對方資料／先鋒備案／公式…）與活著的訊號。
/// heartbeat 雜訊由呼叫端過濾，不進 [labels]。
class StreamProgressTicker extends StatelessWidget {
  const StreamProgressTicker({
    super.key,
    required this.labels,
  });

  /// 已到達的階段標籤（依序）；只顯示最後一筆。
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('stream-progress-ticker'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.coachBackgroundMid.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.coachAccent.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.coachAccentBright,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI 即時生成中 · ${labels.last}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
