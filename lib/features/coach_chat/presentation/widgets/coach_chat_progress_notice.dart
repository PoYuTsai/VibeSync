import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/services/coach_chat_api_service.dart';

class CoachChatProgressNotice extends StatelessWidget {
  final CoachChatProgressUpdate? update;
  final String? question;

  const CoachChatProgressNotice({
    super.key,
    required this.update,
    this.question,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedQuestion = question?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title(update),
                  key: const ValueKey('coach-chat-progress-title'),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  trimmedQuestion == null || trimmedQuestion.isEmpty
                      ? '教練會先整理，再檢查答案，完成後才顯示正式建議。'
                      : '「$trimmedQuestion」',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.glassTextSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _title(CoachChatProgressUpdate? update) {
    if (update == null) return '正在送出問題';
    if (update.stage == CoachChatProgressStage.generating &&
        (update.attempt ?? 1) > 1) {
      return '答案還不夠完整，正在重新整理';
    }
    return switch (update.stage) {
      CoachChatProgressStage.request => '教練已收到問題',
      CoachChatProgressStage.generating => '教練正在整理建議',
      CoachChatProgressStage.validating => '正在檢查答案是否完整',
      CoachChatProgressStage.retrying => '答案還不夠完整，正在重新整理',
      CoachChatProgressStage.finalizing => '檢查完成，正在準備正式建議',
    };
  }
}
