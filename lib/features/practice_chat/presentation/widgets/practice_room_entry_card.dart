import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// 學習 tab 第一屏主視覺：AI 實戰練習室 Hero。
///
/// responsive 滿版 hero——填滿父層給的高度（learning_screen 依 scroll viewport
/// 抓主要可視區），整塊可點進 practice-chat。柔焦情境照背景 + blur/dim overlay
/// + 玻璃膠囊 CTA。背景刻意模糊＝這是第一屏入口主視覺而非抽牌結果，不洩漏候選
/// 對象，保留 locked → 翻牌 → reveal 的儀式感。背景圖載入失敗退回品牌漸層。
class PracticeRoomEntryCard extends StatelessWidget {
  const PracticeRoomEntryCard({super.key});

  static const double _radius = 24;

  /// 被放進無界高度容器時的保底（約 0.72 螢幕高 ≈ 72vh）。一般情況由
  /// learning_screen 依 viewport 給定 bounded 高度，不會走到這。
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
            onTap: () => context.push('/practice-chat'),
            child: SizedBox(
              height: height,
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 柔焦情境照背景；載入失敗退回品牌漸層。
                    Image.asset(
                      'assets/images/practice/practice_hero_bg.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const DecoratedBox(
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

                    // blur + 暗化：上方留柔焦情境、下方加深確保白字與 CTA 可讀。
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.45, 1.0],
                            colors: [
                              Colors.black.withValues(alpha: 0.12),
                              Colors.black.withValues(alpha: 0.32),
                              Colors.black.withValues(alpha: 0.82),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 內容靠底排版：標題 + NEW、副標、玻璃膠囊 CTA。
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // 價值主張 eyebrow：層級高於 CTA（橘漸層發光 pill）。
                          const _DailyRewardEyebrow(),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'AI 實戰練習室',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.headlineLarge.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.45),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const _NewBadge(),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '跟模擬對象直接聊天，練你的真實反應。',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyMedium.copyWith(
                              color: Colors.white.withValues(alpha: 0.90),
                              height: 1.45,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.40),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          const _GlassCapsuleCta(label: '開始練習'),
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

/// 橘色 NEW 標籤。
class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'NEW',
        style: AppTypography.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 價值主張 eyebrow：「每日登入就送新女孩」。橘漸層發光 pill，是 Hero 內
/// 視覺層級最高的元素（高於白色玻璃 CTA），把每日翻牌的核心誘因放到第一眼。
class _DailyRewardEyebrow extends StatelessWidget {
  const _DailyRewardEyebrow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ctaStart, AppColors.ctaEnd],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.ctaStart.withValues(alpha: 0.38),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.card_giftcard_rounded, size: 15, color: Colors.white),
          const SizedBox(width: 7),
          Text(
            '每日登入就送新女孩',
            style: AppTypography.bodySmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// 玻璃膠囊 CTA（白色半透明 pill），疊在模糊背景上呈現玻璃感。第一屏主功能，
/// 視覺層級放大（較大 padding + 字級）。
class _GlassCapsuleCta extends StatelessWidget {
  const _GlassCapsuleCta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
          const SizedBox(width: 9),
          Text(
            label,
            style: AppTypography.titleSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
        ],
      ),
    );
  }
}
