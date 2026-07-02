// lib/features/learning/presentation/screens/learning_screen.dart
//
// 2026-06-17 暗紫橘統一 (BrandKit migration): this list sits inside
// MainShell's animated GradientBackground (dynamic bokeh) so it adds NO
// background of its own. The header text already used brand tokens; the
// free-user daily-read notice now uses the shared BrandInfoNote, and the
// image-card error fallback swaps the OLD glass* fill for a brand-surface
// fill. Card overlays sit on cover photos and stay deliberately dark.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../practice_chat/presentation/screens/practice_collection_screen.dart';
import '../../../practice_chat/presentation/widgets/practice_room_entry_card.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../data/articles_data.dart';
import '../../data/providers/learning_providers.dart';

class LearningScreen extends ConsumerWidget {
  const LearningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(subscriptionProvider);
    final readService = ref.watch(articleReadServiceProvider);

    return CustomScrollView(
      slivers: [
        // 第一屏主視覺：AI 實戰練習室 Hero，依 scroll viewport 高度填滿主要可
        // 視區，讓文章卡落到折線下方（往下滑才看到）。
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final double viewport = constraints.viewportMainAxisExtent;
            // 首屏由 Hero 主導；留約 48px 讓下方「練習專區」標題露頭當下滑提
            // 示。clamp 下限刻意不取大值，避免小機種 Hero 高過 viewport 把底部
            // CTA 推出可視區。
            final double heroHeight = (viewport - 64).clamp(360.0, 760.0);
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SizedBox(
                  height: heroHeight,
                  child: const PracticeRoomEntryCard(),
                ),
              ),
            );
          },
        ),

        // Hero 下方：練習專區 header + 免費閱讀提示（首屏外，往下滑才看到）。
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '練習專區',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.ctaStart,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // 角色圖鑑入口：N 即時反映解鎖數。
                    const PracticeCollectionEntryChip(),
                  ],
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: AppTypography.headlineLarge.copyWith(
                      color: AppColors.onBackgroundPrimary,
                    ),
                    children: [
                      const TextSpan(text: '把技巧練成 '),
                      TextSpan(
                        text: '下一步',
                        style: TextStyle(color: AppColors.ctaStart),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '讀一篇，收成一個今天可以練的動作，再帶回真實對話。',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),

                // Free user daily limit notice
                if (subscription.isFreeUser)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: BrandInfoNote(
                      icon: Icons.info_outline,
                      text: '今日剩餘 ${readService.remainingReads} 篇免費閱讀',
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 2-column image grid
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: articles.length,
            itemBuilder: (context, index) {
              final article = articles[index];
              return GestureDetector(
                onTap: () {
                  if (subscription.isFreeUser) {
                    if (!readService.canReadArticle(article.id)) {
                      context.push('/paywall');
                      return;
                    }
                  }
                  context.push('/article/${article.id}');
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background image
                      Image.asset(
                        article.imagePath,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppColors.brandSurface2
                                .withValues(alpha: 0.6),
                            child: const Center(
                              child: Icon(Icons.article_outlined,
                                  size: 40, color: Colors.white54),
                            ),
                          );
                        },
                      ),

                      // Bottom gradient overlay — deeper for readability.
                      // Positioned.fill（而非 height: double.infinity）：
                      // infinity 會在 debug layout assert 炸掉，fill 才是
                      // 「蓋滿整張卡」的正確寫法，視覺相同。
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.25, 0.6, 1.0],
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.3),
                                Colors.black.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Category pill (top-left)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            article.category,
                            style: AppTypography.caption.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),

                      // Title + read time (bottom) with background frame
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                article.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.titleSmall.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.5),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${article.readTime} · 讀完可練一次',
                                style: AppTypography.caption.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
