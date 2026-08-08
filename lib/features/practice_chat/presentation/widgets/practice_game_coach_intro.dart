import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Game 局內固定在訊息列表最上方的教練開場泡泡。
/// UI-only：絕不進 state.messages、不進 API payload、不入庫——避免污染
/// AI context 與 session 還原（聊天中 AI 全程是「她」，教練只存在於 UI 層）。
/// 樣式仿教練拆解卡（PracticeDebriefCard）的輕量版。
class PracticeGameCoachIntro extends StatelessWidget {
  const PracticeGameCoachIntro({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('practice-game-coach-intro'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandSurface2.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryLight.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.psychology_alt_outlined,
                size: 16,
                color: AppColors.primaryLight,
              ),
              const SizedBox(width: 6),
              Text(
                '教練',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Game 進行中。每句話問自己——這句在動 價值／框架／情緒／投資 '
            '哪一個？卡住就按提示，我直接給你下一句。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
