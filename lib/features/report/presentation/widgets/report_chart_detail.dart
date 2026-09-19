// lib/features/report/presentation/widgets/report_chart_detail.dart
//
// 折線圖下方的「所選資料」區：固定位置的文字，不塞進浮動 tooltip（高低端
// 資料點的 tooltip 會被裁掉、大字級會擠不下）。附上一筆／下一筆按鈕，讓
// 不容易點中圓點的人與 VoiceOver 使用者也能查看全部紀錄。
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class ReportChartDetail extends StatelessWidget {
  const ReportChartDetail({
    super.key,
    required this.index,
    required this.count,
    required this.lines,
    required this.onPrevious,
    required this.onNext,
    this.accentColor = AppColors.primaryLight,
  });

  /// 目前所選在視窗中的位置（0 起）。
  final int index;
  final int count;

  /// 逐行顯示的文字；第一行固定是「本圖第 N 筆 · 日期時間」。
  final List<String> lines;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '所選紀錄，${lines.join('，')}',
      child: Container(
        key: const ValueKey('report-chart-detail'),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accentColor.withValues(alpha: 0.22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < lines.length; i++) ...[
                    if (i > 0) const SizedBox(height: 2),
                    Text(
                      lines[i],
                      style: (i == 0
                              ? AppTypography.caption
                              : AppTypography.bodySmall)
                          .copyWith(
                        color: i == 0
                            ? AppColors.onBackgroundSecondary
                                .withValues(alpha: 0.72)
                            : Colors.white,
                        fontWeight: i == 1 ? FontWeight.w700 : null,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _StepButton(
              buttonKey: const ValueKey('report-chart-prev'),
              icon: Icons.chevron_left_rounded,
              tooltip: '上一筆',
              onPressed: onPrevious,
            ),
            _StepButton(
              buttonKey: const ValueKey('report-chart-next'),
              icon: Icons.chevron_right_rounded,
              tooltip: '下一筆',
              onPressed: onNext,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  /// 掛在 IconButton 本身，測試可直接讀 onPressed 判斷停用。
  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return IconButton(
      key: buttonKey,
      onPressed: onPressed,
      tooltip: tooltip,
      // 點擊區 ≥ 44×44（iOS HIG）。
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        size: 24,
        color: enabled
            ? Colors.white.withValues(alpha: 0.88)
            : Colors.white.withValues(alpha: 0.26),
      ),
    );
  }
}
