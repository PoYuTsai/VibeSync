import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/liquid_motion_frame.dart';
import '../../../subscription/data/providers/subscription_providers.dart';

const String kPracticeRoomEntryHeroAsset =
    'assets/images/practice_girls/practice_girl_038.jpg';
const double kPracticeRoomEntryHeroBlurSigma = 4.2;
const double kPracticeRoomEntryBeamBorderWidth = 1.6;
const double kPracticeRoomEntryBeamGlowRadius = 10;
const double kPracticeRoomEntryBeamStrength = 0.5;

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

        return Material(
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          _DailyRewardEyebrow(),
                          SizedBox(height: 18),
                          // 入口只留貼邊微光。建立對象卡仍使用較強的共用 preset，
                          // 不跟著這張 Hero 弱化。
                          LiquidMotionFrame(
                            style: LiquidMotionStyle.beam,
                            borderRadius:
                                _PracticeRoomGlassPanel.panelCornerRadius,
                            borderWidth: kPracticeRoomEntryBeamBorderWidth,
                            glowRadius: kPracticeRoomEntryBeamGlowRadius,
                            strength: kPracticeRoomEntryBeamStrength,
                            duration: LiquidBeamEntryPreset.duration,
                            child: _PracticeRoomGlassPanel(),
                          ),
                        ],
                      ),
                    ),
                  ],
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
            const Color(0xFFFFE6C7).withValues(alpha: 0.14),
            Colors.black.withValues(alpha: 0.05),
            Colors.black.withValues(alpha: 0.22),
          ],
        ),
      ),
    );
  }
}

class _PracticeRoomGlassPanel extends StatelessWidget {
  const _PracticeRoomGlassPanel();

  static const double panelCornerRadius = 24;
  static const _panelRadius =
      BorderRadius.all(Radius.circular(panelCornerRadius));

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 348),
      child: ClipRRect(
        borderRadius: _panelRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            key: const ValueKey('practice-room-entry-glass-panel'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
            decoration: BoxDecoration(
              color: const Color(0xFF17112F).withValues(alpha: 0.78),
              borderRadius: _panelRadius,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _PracticeRoomMark(),
                const SizedBox(height: 24),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'AI 實戰練習室',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                          height: 1.08,
                          shadows: [
                            Shadow(
                              color: Color(0xB0000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),
                      _NewBadge(),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '跟陪練女孩直接聊天，\n練你的真實反應。',
                  textAlign: TextAlign.center,
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.34,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.62),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PracticeRoomMark extends StatelessWidget {
  const _PracticeRoomMark();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.ctaStart.withValues(alpha: 0.52),
            blurRadius: 22,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        size: 46,
        color: AppColors.ctaStart,
        shadows: [
          Shadow(
            color: AppColors.ctaStart.withValues(alpha: 0.9),
            blurRadius: 18,
          ),
        ],
      ),
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
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: AppColors.ctaStart.withValues(alpha: 0.48),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Text(
        'NEW',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 19,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ctaStart, AppColors.ctaEnd],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.ctaStart.withValues(alpha: 0.38),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.card_giftcard_rounded,
                size: 15, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              isPremium ? '每日登入解鎖新女孩' : '翻牌解鎖新女孩',
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
