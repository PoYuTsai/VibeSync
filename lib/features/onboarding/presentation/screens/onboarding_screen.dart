// lib/features/onboarding/presentation/screens/onboarding_screen.dart
//
// 2026-06-17 暗紫橘統一 (BrandKit migration): the first-run onboarding flow now
// rides the shared dark brand gradient (BrandPageBackground) instead of the
// bare near-black AppColors.background. The "下一步" CTA uses
// BrandPrimaryButton (orange pill), the skip link + page indicators switch to
// white/orange brand tokens, matching the shipped 關於我/作戰板 dark surface
// system.
//
// 2026-07-06 案 3 冷啟動分流：第 5 頁新增 _OnboardingBranchingPage 分流頁
// （有對象 → /partner/new；還沒 → /practice-collection），原「開始使用」
// 完成 CTA 移除，分流頁的動作按鈕在頁內、底部「下一步」隱藏。
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
      'description': '對方這次的投入度 0-100 一目瞭然\n讀懂她這輪話裡的訊號',
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
      // onboarding 不列廠商名（避免誤解練習室女孩＝DeepSeek）；
      // 完整含廠商揭露留在設定頁 AI 隱私頁。
      'description': AiPrivacyDisclosure.onboardingDescription,
      'imagePath': 'privacy',
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // 案 3 冷啟動分流：底部「下一步」只在前 4 頁顯示（分流頁的動作按鈕在
  // 頁內），所以這裡永遠只是翻頁，不再有「開始使用」完成分支。
  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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

  /// 分流頁按鈕：完成 onboarding 後先 go('/') 再 push 目的地，
  /// back 鍵可退回首頁 tab 0，不卡死（設計檔案 3）。
  Future<void> _completeOnboardingTo(String route) async {
    await OnboardingService.markCompleted();
    if (mounted) {
      context.go('/');
      context.push(route);
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
                  // +1：第 5 頁是冷啟動分流頁（案 3）。
                  itemCount: _pages.length + 1,
                  onPageChanged: (page) {
                    setState(() {
                      _currentPage = page;
                    });
                  },
                  itemBuilder: (context, index) {
                    if (index == _pages.length) {
                      return _OnboardingBranchingPage(
                        onHasPartner: () =>
                            _completeOnboardingTo('/partner/new'),
                        onNoPartner: () =>
                            _completeOnboardingTo('/practice-collection'),
                      );
                    }
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
                    _pages.length + 1,
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

              // Next button — hidden on the branching page (its own CTAs
              // live inside the page body).
              if (_currentPage < _pages.length)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: BrandPrimaryButton(
                    label: '下一步',
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

/// 第 5 頁冷啟動分流頁（案 3）：問用戶有沒有正在聊的對象，
/// 直接把「有」導去建對象卡、「還沒」導去練習室圖鑑。
/// 視覺對齊 OnboardingPage 的 icon hero＋標題排版，但 CTA 在頁內。
class _OnboardingBranchingPage extends StatelessWidget {
  const _OnboardingBranchingPage({
    required this.onHasPartner,
    required this.onNoPartner,
  });

  final VoidCallback onHasPartner;
  final VoidCallback onNoPartner;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Brand icon hero — 與 OnboardingPage 同款橘暈圓盤。
                Container(
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
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: const Icon(
                    Icons.forum_outlined,
                    size: 80,
                    color: AppColors.ctaStart,
                  ),
                ),
                const SizedBox(height: 48),
                Text(
                  '你現在有正在聊的對象嗎？',
                  style: AppTypography.headlineMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                BrandPrimaryButton(
                  label: '有，幫我分析對話',
                  onPressed: onHasPartner,
                  verticalPadding: 16,
                ),
                const SizedBox(height: 12),
                BrandSecondaryButton(
                  label: '還沒，先去練習',
                  onPressed: onNoPartner,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
