import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// 串流內容卡的單一項目 view model。
///
/// wire 型別（AnalysisStreamContent，data 層）→ 顯示項的映射由
/// composition root（AnalysisScreen）完成；本 section 只認展示資料，
/// 維持 provider/repository/network-neutral。
@immutable
class StreamingContentItem {
  const StreamingContentItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

/// 完整分析串流期間的「即時整理中」內容卡。
///
/// 純渲染：標頭（icon 座＋標題＋進度標籤）加逐項內容，最後一項用亮色
/// 強調。無內容時渲染空盒（外層條件已擋，這裡守住被動性）。
class StreamingContentCard extends StatelessWidget {
  const StreamingContentCard({
    super.key,
    required this.progressLabel,
    required this.items,
  });

  final String? progressLabel;
  final List<StreamingContentItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.backgroundGradientMid,
            Color(0xFF3A185B),
            Color(0xFF612C65),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.24),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.ctaStart, AppColors.brandBlush],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '完整分析即時整理中',
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (progressLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        progressLabel!,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.78),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) ...[
            _StreamingContentTile(
              item: items[i],
              isLatest: i == items.length - 1,
            ),
            if (i != items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _StreamingContentTile extends StatelessWidget {
  const _StreamingContentTile({
    required this.item,
    required this.isLatest,
  });

  final StreamingContentItem item;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final accent = isLatest ? AppColors.bokehYellow : AppColors.primaryLight;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isLatest ? 0.14 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: isLatest ? 0.32 : 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.icon,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.body,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.84),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
