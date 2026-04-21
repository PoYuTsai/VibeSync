// lib/features/learning/presentation/screens/learning_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../data/articles_data.dart';

class LearningScreen extends ConsumerWidget {
  const LearningScreen({super.key});

  // 文字用深色版本，背景用淺色版本
  Color _categoryTextColor(String colorName) {
    switch (colorName) {
      case 'yellow':
        return const Color(0xFFB8860B); // dark goldenrod
      case 'coral':
        return const Color(0xFFC62828); // dark red
      case 'pink':
        return const Color(0xFFAD1457); // dark pink
      default:
        return const Color(0xFFC62828);
    }
  }

  Color _categoryBgColor(String colorName) {
    switch (colorName) {
      case 'yellow':
        return const Color(0xFFFFF3CD); // light yellow
      case 'coral':
        return const Color(0xFFFFE0D6); // light coral
      case 'pink':
        return const Color(0xFFFFD6E8); // light pink
      default:
        return const Color(0xFFFFE0D6);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // Header
        Text(
          '學習專區',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.ctaStart,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            style: AppTypography.headlineLarge.copyWith(
              color: AppColors.onBackgroundPrimary,
            ),
            children: [
              const TextSpan(text: '提升你的 '),
              TextSpan(
                text: '溝通力',
                style: TextStyle(color: AppColors.ctaStart),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Article cards
        ...articles.map((article) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => context.push('/article/${article.id}'),
                child: GlassmorphicContainer(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _categoryBgColor(article.categoryColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          article.category,
                          style: AppTypography.bodySmall.copyWith(
                            color: _categoryTextColor(article.categoryColor),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Title
                      Text(
                        article.title,
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.glassTextPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Subtitle
                      Text(
                        article.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.glassTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Source + read time
                      Row(
                        children: [
                          Text(
                            article.source,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.glassTextHint,
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.schedule,
                            size: 13,
                            color: AppColors.glassTextHint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            article.readTime,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.glassTextHint,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }
}
