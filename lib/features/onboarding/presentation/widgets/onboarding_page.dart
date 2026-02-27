// lib/features/onboarding/presentation/widgets/onboarding_page.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class OnboardingPage extends StatelessWidget {
  final String title;
  final String description;
  final String imagePath;
  final Widget? customContent;

  const OnboardingPage({
    super.key,
    required this.title,
    required this.description,
    required this.imagePath,
    this.customContent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Image placeholder (can be replaced with actual images)
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getIcon(),
              size: 80,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 48),

          // Title
          Text(
            title,
            style: AppTypography.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Description
          Text(
            description,
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),

          // Custom content (e.g., demo conversation)
          if (customContent != null) ...[
            const SizedBox(height: 32),
            customContent!,
          ],
        ],
      ),
    );
  }

  IconData _getIcon() {
    switch (imagePath) {
      case 'welcome':
        return Icons.favorite_border;
      case 'analyze':
        return Icons.psychology_outlined;
      case 'reply':
        return Icons.chat_bubble_outline;
      default:
        return Icons.lightbulb_outline;
    }
  }
}
