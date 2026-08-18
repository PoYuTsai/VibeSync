import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../subscription/data/providers/subscription_providers.dart';

const String kPracticeRoomEntryHeroAsset =
    'assets/images/practice_girls/practice_girl_038.jpg';
const double kPracticeRoomEntryHeroBlurSigma = 1.4;

/// 學習 tab 第一屏主視覺：AI 實戰練習室 Hero。
///
/// 填滿 learning_screen 給定的首屏高度；整張卡都可點入圖鑑
/// （practice-collection＝gacha hub，翻牌／進對話都由圖鑑承擔）。
class PracticeRoomEntryCard extends StatelessWidget {
  const PracticeRoomEntryCard({super.key});

  static const double _radius = 24;
  static const double _unboundedFallbackFraction = 0.72;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_radius);
    return LayoutBuilder(
      builder: (context, constraints) {
        final double height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height * _unboundedFallbackFraction;

        return PressableScale(
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,
              onTap: () => context.push('/practice-collection'),
              child: SizedBox(
                height: height,
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const _HeroBackground(),
                      const _WarmReadabilityScrim(),
                      const _HeroCopy(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroBackground extends StatelessWidget {
  const _HeroBackground();

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      key: const ValueKey('practice-room-entry-bg-blur'),
      imageFilter: ImageFilter.blur(
        sigmaX: kPracticeRoomEntryHeroBlurSigma,
        sigmaY: kPracticeRoomEntryHeroBlurSigma,
      ),
      child: Transform.scale(
        scale: 1.035,
        child: Image.asset(
          kPracticeRoomEntryHeroAsset,
          key: const ValueKey('practice-room-entry-bg-image'),
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.06),
          errorBuilder: (context, error, stackTrace) => const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.brandSurface2,
                  AppColors.brandSurface,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WarmReadabilityScrim extends StatelessWidget {
  const _WarmReadabilityScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.42, 1.0],
          colors: [
            Colors.black.withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: 0.62),
          ],
        ),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DailyRewardEyebrow(),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TitleRow(),
                    SizedBox(height: 8),
                    Text(
                      '跟陪練女孩直接聊天，\n練你的真實反應。',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.ctaStart,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.onCta,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: const [
        Text(
          'AI 實戰練習室',
          key: ValueKey('practice-room-entry-title'),
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        _NewBadge(),
      ],
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ctaStart,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'NEW',
        style: TextStyle(
          color: AppColors.onCta,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0,
          height: 1,
        ),
      ),
    );
  }
}

class _DailyRewardEyebrow extends ConsumerWidget {
  const _DailyRewardEyebrow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 批 3：free 每日免費抽已移除，「每日」字樣只對付費 tier 為真。
    final isPremium = ref.watch(subscriptionProvider).isPremium;
    return Row(
      children: [
        const Icon(
          Icons.calendar_today_outlined,
          size: 15,
          color: AppColors.ctaStart,
        ),
        const SizedBox(width: 8),
        Text(
          isPremium ? '每日登入解鎖新女孩' : '翻牌解鎖新女孩',
          style: AppTypography.bodySmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ],
    );
  }
}
