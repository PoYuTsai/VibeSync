// lib/features/onboarding/presentation/widgets/onboarding_page.dart
//
// 2026-06-17 暗紫橘統一 (BrandKit migration): the page icon hero + copy now
// sit on the shared dark brand gradient (driven by OnboardingScreen). The old
// light-purple disc / primary-tinted icon and default (dark-on-light) text
// tokens are swapped for the brand orange icon badge + white/secondary text so
// onboarding matches the shipped 關於我/作戰板 dark surface system.
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class OnboardingPage extends StatelessWidget {
  final String title;
  final String description;
  final String imagePath;

  /// 品牌教練 Sydney 圖 hero；有值時取代罐頭 icon 圓盤（2026-08-01 轉化診斷）。
  final String? heroImageAsset;
  final Widget? customContent;

  const OnboardingPage({
    super.key,
    required this.title,
    required this.description,
    required this.imagePath,
    this.heroImageAsset,
    this.customContent,
  });

  @override
  Widget build(BuildContext context) {
    // 內容放得下時維持垂直置中；放不下（小螢幕或較長的揭露文案）改可捲動，
    // 不讓 Column overflow。
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 示範卡（customContent）在場時就是主視覺，hero 整塊讓位，
          // 否則小螢幕上「hero＋示範卡」疊起來會把重點擠出畫面。
          if (customContent == null) ...[
            _buildHero(),
            const SizedBox(height: 48),
          ],

          // Title
          Text(
            title,
            style: AppTypography.headlineMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Description
          Text(
            description,
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.82),
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

  Widget _buildHero() {
    final asset = heroImageAsset;
    if (asset != null) {
      return Semantics(
        image: true,
        label: 'VibeSync Coach Sydney，欣欣',
        child: Image.asset(
          asset,
          key: const ValueKey('onboarding-hero-image'),
          height: 240,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
      );
    }
    // Brand icon hero (orange gradient disc on the dark brand gradient).
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.ctaStart.withValues(alpha: 0.22),
            AppColors.brandBlush.withValues(alpha: 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Icon(
        _getIcon(),
        size: 80,
        color: AppColors.ctaStart,
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
      case 'practice':
        return Icons.sports_esports_outlined;
      case 'learning':
        return Icons.menu_book_outlined;
      case 'coach':
        return Icons.explore_outlined;
      case 'privacy':
        return Icons.privacy_tip_outlined;
      default:
        return Icons.lightbulb_outline;
    }
  }
}
