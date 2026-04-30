import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/glassmorphic_container.dart';
import '../../data/providers/user_profile_providers.dart';
import '../../domain/entities/user_profile.dart';

/// 我的報告頂部「關於我」卡片。
///
/// - empty → prominent CTA。
/// - filled → compact summary（僅 render 有值欄位）。
/// - loading / error → `SizedBox.shrink()`，避免報告頁閃爍。
class AboutMeCard extends ConsumerWidget {
  const AboutMeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userProfileControllerProvider);

    return state.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (profile) {
        if (profile == null || profile.isEmpty) {
          return _EmptyState(
            onTap: () => context.push('/profile/about-me'),
          );
        }
        return _FilledState(
          profile: profile,
          onTap: () => context.push('/profile/about-me'),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '關於我',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '讓 VibeSync 更像你的教練',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '花 30 秒填一下，之後 AI 會用更像你的節奏給建議。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ctaStart,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('開始設定'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilledState extends StatelessWidget {
  const _FilledState({required this.profile, required this.onTap});

  final UserProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];

    if (profile.interactionStyle != null) {
      lines.add(_summaryLine(
        '互動風格',
        _interactionStyleLabel(profile.interactionStyle!),
      ));
    }
    if (profile.practiceGoals.isNotEmpty) {
      lines.add(_summaryLine(
        '練習目標',
        profile.practiceGoals.map(_practiceGoalLabel).join('、'),
      ));
    }
    if (profile.topicSeeds.isNotEmpty) {
      lines.add(_summaryLine(
        '常聊話題',
        profile.topicSeeds.map(_topicSeedLabel).join('、'),
      ));
    }
    if (profile.customTopics != null) {
      lines.add(_summaryLine('自訂話題', profile.customTopics!));
    }
    if (profile.notes != null) {
      lines.add(_summaryLine('備註', profile.notes!));
    }

    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '關於我',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ctaStart,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('編輯'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...lines.expand(
            (w) => [w, const SizedBox(height: 4)],
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.glassTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _interactionStyleLabel(InteractionStyle s) => switch (s) {
      InteractionStyle.steady => '穩重',
      InteractionStyle.direct => '直接',
      InteractionStyle.humorous => '幽默',
      InteractionStyle.gentle => '溫柔',
      InteractionStyle.playful => '俏皮',
    };

String _practiceGoalLabel(PracticeGoal g) => switch (g) {
      PracticeGoal.softInvite => '自然邀約',
      PracticeGoal.reduceAnxiety => '降低焦慮',
      PracticeGoal.humorousReply => '幽默回覆',
      PracticeGoal.buildCloseness => '培養親近',
      PracticeGoal.explainLess => '減少解釋',
    };

String _topicSeedLabel(TopicSeed t) => switch (t) {
      TopicSeed.fitness => '健身',
      TopicSeed.travel => '旅行',
      TopicSeed.coffee => '咖啡',
      TopicSeed.music => '音樂',
      TopicSeed.movies => '電影',
      TopicSeed.photography => '攝影',
      TopicSeed.food => '美食',
      TopicSeed.pets => '寵物',
      TopicSeed.reading => '閱讀',
      TopicSeed.workLife => '工作生活',
    };
