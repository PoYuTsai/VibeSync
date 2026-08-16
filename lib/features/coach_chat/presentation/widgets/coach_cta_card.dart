import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/coach_head_avatar.dart';
import '../../../../shared/widgets/pressable_scale.dart';

/// 「問教練 Sydney」CTA 卡：對象頁與分析頁共用，只差導去視窗的 onTap。
/// 零 AI 成本、純導航；額度與 consent gate 全在視窗內的 CoachSurface。
class CoachCtaCard extends StatelessWidget {
  const CoachCtaCard({super.key, required this.onTap, this.buttonKey});

  final VoidCallback onTap;

  /// 掛在 InkWell 上供測試定位（各宿主自帶語意化 key）。
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: buttonKey,
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                const CoachHeadAvatar(size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '問教練 Sydney',
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.onBackgroundPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '幫教練釐清不扣額度，正式建議才扣 1 則',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.onBackgroundSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
