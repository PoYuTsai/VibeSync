// lib/shared/widgets/score_action_hint.dart
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/analysis/domain/entities/analysis_models.dart';
import '../../features/analysis/domain/entities/enthusiasm_level.dart';
import 'warm_theme_widgets.dart';

class ScoreActionHint extends StatelessWidget {
  final int score;
  final GameStageInfo? gameStage;
  final FinalRecommendation? recommendation;

  const ScoreActionHint({
    super.key,
    required this.score,
    this.gameStage,
    this.recommendation,
  });

  static const _meetingKeywords = [
    '見面',
    '邀約',
    '約她',
    '約他',
    '約出來',
    '約出門',
    '約會',
    '吃飯',
    '喝咖啡',
    '看電影',
    '一起去',
    '碰面',
    '見個面',
  ];

  // Only allow meeting-suggesting payload when we're solidly in veryHot tier;
  // anything below stays defensive even if backend wrongly suggests meeting.
  static int get _meetingHintMinScore => AppConstants.hotMax + 1;

  bool _payloadSuggestsMeeting(String text) =>
      _meetingKeywords.any(text.contains);

  bool get _canSurfaceMeetingHint => score >= _meetingHintMinScore;

  String? _visibleIfSafe(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (!_canSurfaceMeetingHint && _payloadSuggestsMeeting(trimmed)) {
      return null;
    }
    return trimmed;
  }

  String _resolveHeadline() {
    final payload = _visibleIfSafe(gameStage?.nextStep ?? '');
    if (payload != null) {
      return payload;
    }
    return _tierFallback();
  }

  String _tierFallback() {
    final level = EnthusiasmLevel.fromScore(score);
    switch (level) {
      case EnthusiasmLevel.cold:
        return '先觀察對方節奏，鏡像她的字數別主動推進';
      case EnthusiasmLevel.warm:
        return '找一個輕鬆共同點切入，引導她多分享';
      case EnthusiasmLevel.hot:
        return '加一點張力或推拉，但別急著推進';
      case EnthusiasmLevel.veryHot:
        return '準備一個低門檻邀約，給具體時間和場景';
    }
  }

  String? _bodyText() {
    return _visibleIfSafe(recommendation?.reason ?? '');
  }

  String? _exampleText() {
    return _visibleIfSafe(recommendation?.content ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final level = EnthusiasmLevel.fromScore(score);
    final headline = _resolveHeadline();
    final body = _bodyText();
    final example = _exampleText();

    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '下一步',
                style: AppTypography.caption.copyWith(
                  color: AppColors.ctaStart,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(level.emoji, style: const TextStyle(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            headline,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextSecondary,
              ),
            ),
          ],
          if (example != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.ctaStart.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '試試這樣回',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ctaStart,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    example,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.glassTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
