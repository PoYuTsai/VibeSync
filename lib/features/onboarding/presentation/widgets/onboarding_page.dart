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
    // 練習室頁主視覺（2026-08-18 Eric 稿）：女孩照圓形拼貼壓暗＋橘色手把
    // 疊中央——「百位女孩」用看的不是用講的。
    if (imagePath == 'practice') return const _PracticeGirlsCollageHero();
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
    // 'practice' 不會走到這裡（_buildHero 特判成拼貼）。
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

/// 女孩照 4×4 圓形拼貼＋暗紫遮罩＋橘色手把 icon（夥伴稿 2026-08-18）。
class _PracticeGirlsCollageHero extends StatelessWidget {
  const _PracticeGirlsCollageHero();

  /// 16 張、取樣間隔 6：橫跨整批 100 張的風格差異，固定不隨機
  /// （onboarding 每次看都一樣，也方便 golden／截圖比對）。
  static final _assets = List.generate(
    16,
    (i) => 'assets/images/practice_girls/'
        'practice_girl_${'${i * 6 + 1}'.padLeft(3, '0')}.jpg',
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: '百位練習室女孩的頭像拼貼',
      child: SizedBox(
        key: const ValueKey('onboarding-practice-collage'),
        width: 220,
        height: 220,
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  for (var row = 0; row < 4; row++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var col = 0; col < 4; col++)
                            Expanded(
                              child: Image.asset(
                                _assets[row * 4 + col],
                                fit: BoxFit.cover,
                                // 每格約 55pt，3x 機種 ≈165px；原圖直接解碼
                                // 16 張會白吃記憶體。
                                cacheWidth: 168,
                                excludeFromSemantics: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              // 壓暗讓橘色手把成為視覺主角，照片退成質感底（夥伴稿的暗度
              // 約在 0.7；要照片更搶眼就調低這個值）。
              ColoredBox(
                color: AppColors.brandInk.withValues(alpha: 0.70),
              ),
              const Center(
                child: Icon(
                  Icons.sports_esports_outlined,
                  size: 84,
                  color: AppColors.ctaStart,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
