// 對象頁「問教練」CTA（2026-08-15 拍板：三入口共用獨立聊天視窗）。
//
// 內嵌 CoachSurface 時代（Phase E Task 6 薄 wrapper）整段退場：三情境
// chip、知識庫連結與 lifecyclePhase 種入都搬進問教練 Sydney 視窗
// （GlobalCoachScreen 鎖定模式）。本 widget 只剩一張 CTA 卡，點了導
// `/coach?partnerId=`——對象已知，視窗不渲染「問誰」。
//
// 額度與 consent gate 全在視窗內的 CoachSurface；這裡純導航，零 AI 成本。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/coach_head_avatar.dart';
import '../../../../shared/widgets/pressable_scale.dart';

class CoachFollowUpSection extends StatelessWidget {
  final String partnerId;

  const CoachFollowUpSection({super.key, required this.partnerId});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: const Key('coach_follow_up_cta'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.push('/coach?partnerId=$partnerId'),
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
                        '釐清免費，正式建議才扣 1 則',
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
