import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/glassmorphic_container.dart';
import '../../data/providers/user_profile_providers.dart';
import '../../domain/entities/user_profile.dart';
import '../../../../core/services/app_haptics.dart';

/// 我的報告頂部「關於我」卡片。
///
/// - empty → prominent CTA。
/// - filled → compact summary（僅 render 有值欄位）。
/// - loading → 與完成態同高的骨架，避免報告內容上下跳動。
/// - error → 不阻擋下方報告。
class AboutMeCard extends ConsumerWidget {
  const AboutMeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userProfileControllerProvider);

    return state.when(
      loading: () => const _AboutMeSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (profile) {
        if (profile == null || profile.isEmpty) {
          return _EmptyState(
            onTap: () => context.push('/profile/about-me?source=card'),
          );
        }
        return _FilledState(
          profile: profile,
          onTap: () => context.push('/profile/about-me?source=card'),
        );
      },
    );
  }
}

class _AboutMeSkeleton extends StatelessWidget {
  const _AboutMeSkeleton();

  static void _noop() {}

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      label: '關於我設定載入中',
      child: ExcludeSemantics(
        child: Skeletonizer(
          enabled: true,
          ignorePointers: true,
          effect: reduceMotion
              ? SolidColorEffect(
                  color: AppColors.glassBorder.withValues(alpha: 0.78),
                )
              : ShimmerEffect(
                  baseColor: AppColors.glassBorder.withValues(alpha: 0.72),
                  highlightColor: Colors.white.withValues(alpha: 0.82),
                  duration: const Duration(milliseconds: 1100),
                ),
          child: const _EmptyState(onTap: _noop),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProfileIcon(icon: Icons.tune_rounded),
              const SizedBox(width: 8),
              Text(
                '關於我',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              const _ProfilePill(label: '影響 AI 建議'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '讓教練真的懂你',
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '填一下你卡在哪、想達成什麼，AI 會幫你抓方向、推你一步，不會照你現在的樣子模仿你。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ProfilePill(label: '我現在卡在哪'),
                    _ProfilePill(label: '我想達成什麼'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: AppHaptics.onPress(onTap),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ctaStart,
                  foregroundColor: AppColors.onCta,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                child: const Text('開始設定'),
              ),
            ],
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

    if (profile.stuckPoints.isNotEmpty) {
      lines.add(_summaryLine(
        '卡在哪',
        profile.stuckPoints.map(_stuckPointLabel).join('、'),
      ));
    }
    if (profile.practiceGoals.isNotEmpty) {
      lines.add(_summaryLine(
        '想達成什麼',
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
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProfileIcon(icon: Icons.person_outline_rounded),
              const SizedBox(width: 8),
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
          const SizedBox(height: 12),
          ...lines.expand(
            (w) => [w, const SizedBox(height: 4)],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.ctaStart.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.ctaStart.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: AppColors.ctaStart,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI 會參考這些設定幫你抓方向、推你一步',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.glassTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
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

class _ProfileIcon extends StatelessWidget {
  const _ProfileIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: AppColors.ctaStart),
    );
  }
}

class _ProfilePill extends StatelessWidget {
  const _ProfilePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.glassBorder.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.glassTextSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

String _stuckPointLabel(StuckPoint s) => switch (s) {
      StuckPoint.fadesOut => '聊一聊就冷掉，不知道怎麼接下去',
      StuckPoint.dontKnowHowToAsk => '不知道怎麼開口約',
      StuckPoint.anxiousWontSend => '會緊張、怕講錯話不敢傳',
      StuckPoint.overExplains => '話太多、一直在解釋自己',
      StuckPoint.leftOnRead => '一直被已讀不回',
    };

String _practiceGoalLabel(PracticeGoal g) => switch (g) {
      PracticeGoal.softInvite => '想約得出來',
      PracticeGoal.comfortableChat => '想先能自在聊天，不要那麼緊繃',
      PracticeGoal.humorousReply => '想讓對話更幽默、有來有往',
      PracticeGoal.buildCloseness => '想培養穩定的親近感',
      PracticeGoal.findCompatiblePartner => '想找到聊得來的對象、不設限交往',
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
