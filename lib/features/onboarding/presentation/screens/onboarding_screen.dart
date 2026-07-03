// lib/features/onboarding/presentation/screens/onboarding_screen.dart
//
// 2026-06-17 暗紫橘統一 (BrandKit migration): the first-run onboarding flow now
// rides the shared dark brand gradient (BrandPageBackground) instead of the
// bare near-black AppColors.background. The "下一步/開始使用" CTA uses
// BrandPrimaryButton (orange pill), the skip link + page indicators switch to
// white/orange brand tokens, matching the shipped 關於我/作戰板 dark surface
// system. No flow / navigation / OnboardingService logic changed.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/ai_privacy_disclosure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/onboarding_service.dart';
import '../widgets/onboarding_page.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  final _pages = [
    {
      'title': '不知道怎麼回她？',
      'description': '貼上對話或截圖，AI 幫你分析她的心理狀態\n教你最適合的回覆方式',
      'imagePath': 'welcome',
    },
    {
      'title': '即時看懂她的訊號',
      'description': '熱度分析 0-100 一目瞭然\n讀懂她話裡的意思',
      'imagePath': 'analyze',
    },
    {
      'title': '五種風格，選最對的那句',
      'description': '延展、共鳴、調情、幽默、冷讀\n每句都幫你控制字數，不會顯得太黏或太急',
      'imagePath': 'reply',
    },
    // R1-4 App Review 保險：靜態揭露第三方 AI 資料外送；實際同意
    // 仍由各 AI 功能首次使用前的 AiDataSharingConsent 同意閘把關。
    // 文案與設定頁「AI 與你的隱私」共用 AiPrivacyDisclosure（F5-A7）。
    {
      'title': AiPrivacyDisclosure.title,
      'description': AiPrivacyDisclosure.description,
      'imagePath': 'privacy',
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _skipOnboarding() {
    _completeOnboarding();
  }

  Future<void> _completeOnboarding() async {
    await OnboardingService.markCompleted();
    if (mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: _skipOnboarding,
                    child: Text(
                      '略過',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ),
              ),

              // Page content
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (page) {
                    setState(() {
                      _currentPage = page;
                    });
                  },
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return OnboardingPage(
                      title: page['title']!,
                      description: page['description']!,
                      imagePath: page['imagePath']!,
                    );
                  },
                ),
              ),

              // Page indicators
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? AppColors.ctaStart
                            : Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),

              // Next/Start button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: BrandPrimaryButton(
                  label: _currentPage < _pages.length - 1 ? '下一步' : '開始使用',
                  onPressed: _nextPage,
                  verticalPadding: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
