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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/ai_privacy_disclosure.dart';
import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../user_profile/data/providers/user_profile_providers.dart';
import '../../../user_profile/domain/entities/user_profile.dart';
import '../../data/onboarding_service.dart';
import '../widgets/demo_analysis_preview.dart';
import '../widgets/onboarding_page.dart';
import '../widgets/onboarding_questionnaire_page.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Tier 2 批 2：問卷選擇存在 parent state，本頁不寫 Hive，
  // 統一由分流頁的合併種子一次寫入。
  // 2026-08-04 拍板：問卷不再問互動風格（那條線已整條移除，關於我頁也拿掉
  // 對應區塊），只留練習目標。
  List<PracticeGoal> _questionnaireGoals = const [];

  /// 問卷插在賣點頁（含練習室/學習/定位頁，index 0-5）之後、隱私頁之前。
  static const _questionnairePageIndex = 6;

  final _pages = [
    {
      'title': '不知道怎麼回她？',
      'description': '貼上對話或截圖，AI 幫你分析她的心理狀態\n教你最適合的回覆方式',
      'imagePath': 'welcome',
      // 2026-08-01 轉化診斷 Tier 1：第一印象用品牌教練 Sydney，不用罐頭 icon。
      'heroImage': 'assets/images/coach/sydney_greeting.png',
    },
    {
      'title': '即時看懂她的訊號',
      'description': '對方這次的投入度 0-90 一目瞭然\n讀懂她這輪話裡的訊號',
      'imagePath': 'analyze',
    },
    {
      'title': '五種風格，選最對的那句',
      'description': '延展、共鳴、調情、幽默、冷讀\n每句都幫你控制字數，不會顯得太黏或太急',
      'imagePath': 'reply',
    },
    // 練習室＋學習專區（2026-08-18 Eric 指示）：讓「還沒有對象」的用戶
    // 在分流頁之前就知道有地方可以練——接分流「還沒，先去練習」那條路。
    {
      'title': '還沒有對象？先練',
      'description': '百位風格各異的女孩陪你實戰演練\n練完拿一張教練拆解卡，上場不再手抖',
      'imagePath': 'practice',
    },
    {
      'title': '越用越會聊',
      'description': '幽默、EQ、拿回對話重心的社交心法\n文章＋互動測驗，學完直接帶進實戰',
      'imagePath': 'learning',
    },
    // 定位頁（2026-08-18 定位拍板，docs/positioning.md）：功能演示後
    // 把自我介紹從「回這句」抬到品類差異化——教練帶完整段；
    // 記憶不寫「有記憶」，寫成利益句「認得你聊的每一個她」。
    {
      'title': '不只教你回這句',
      'description': '它認得你聊的每一個她——聊到哪、熱度多少、什麼時候該約\n教練帶你從曖昧一路走到約出來',
      'imagePath': 'coach',
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
  void initState() {
    super.initState();
    // 第 0 頁不會觸發 onPageChanged，漏斗第一格要在這裡補
    // （GLM 審查 F5：否則第一頁就跳出的流失測不見）。
    unawaited(
      ref
          .read(funnelTrackerProvider)
          .track('onboarding_page_view', properties: {'page_index': 0}),
    );
  }

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
    unawaited(
      ref
          .read(funnelTrackerProvider)
          .track('onboarding_skip', properties: {'page_index': _currentPage}),
    );
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
  Future<void> _completeOnboardingTo(
    String route, {
    required bool hasPartner,
  }) async {
    unawaited(
      ref.read(funnelTrackerProvider).track(
        'onboarding_branch_answer',
        properties: {'has_partner': hasPartner},
      ),
    );
    unawaited(
      ref.read(funnelTrackerProvider).track(
        'onboarding_questionnaire_submit',
        properties: {
          'goals_count': _questionnaireGoals.length,
        },
      ),
    );
    // onboarding 移到登入前（2026-08-18）：未登入時 profile 沒有 scope 可種、
    // 目的地也推不進去（會被 auth gate 攔），改暫存 prefs，登入後由
    // MainShell 的 OnboardingHandoffApplier 取走套用。
    final uid = await ref.read(authUserProfileScopeProvider.future);
    if (uid == null) {
      await OnboardingService.stashPendingHandoff(
        goalNames: _questionnaireGoals
            .map((goal) => goal.name)
            .toList(growable: false),
        route: route,
      );
      await OnboardingService.markCompleted();
      if (mounted) context.go('/'); // redirect 會落到 /login
      return;
    }
    await _seedProfileFromOnboardingAnswers();
    await OnboardingService.markCompleted();
    if (mounted) {
      context.go('/');
      context.push(route);
    }
  }

  /// 只種問卷（風格＋目標）：分流頁的「有沒有對象」不再轉寫進 notes——
  /// 那 100 字要留給用戶自己的真實自述，「有沒有對象」已經有
  /// onboarding_branch_answer funnel event 記錄，不需要佔用 profile
  /// （2026-08-03「關於我」重新定位 report）。問卷全略過就不建任何資料。
  /// 仍只在 profile 全空時種、失敗靜默放過、絕不擋導頁。
  Future<void> _seedProfileFromOnboardingAnswers() async {
    if (_questionnaireGoals.isEmpty) return;
    try {
      final existing = await ref.read(userProfileControllerProvider.future);
      if (existing != null && !existing.isEmpty) return;
      await ref.read(userProfileControllerProvider.notifier).save(
            UserProfile.create(
              practiceGoals: List.of(_questionnaireGoals),
              updatedAt: DateTime.now(),
            ),
          );
    } catch (_) {
      // best-effort：種子失敗不影響 onboarding 完成與導頁。
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
                    onPressed: AppHaptics.onPress(_skipOnboarding),
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
                  // +2：第 4 頁問卷（批 2）＋最後一頁冷啟動分流頁（案 3）。
                  itemCount: _pages.length + 2,
                  onPageChanged: (page) {
                    AppHaptics.tap();
                    unawaited(
                      ref.read(funnelTrackerProvider).track(
                        'onboarding_page_view',
                        properties: {'page_index': page},
                      ),
                    );
                    setState(() {
                      _currentPage = page;
                    });
                  },
                  itemBuilder: (context, index) {
                    if (index == _questionnairePageIndex) {
                      return OnboardingQuestionnairePage(
                        selectedGoals: _questionnaireGoals,
                        onGoalsChanged: (goals) =>
                            setState(() => _questionnaireGoals = goals),
                      );
                    }
                    if (index == _pages.length + 1) {
                      return _OnboardingBranchingPage(
                        onHasPartner: () => _completeOnboardingTo(
                          '/partner/new',
                          hasPartner: true,
                        ),
                        onNoPartner: () => _completeOnboardingTo(
                          // guide=1：圖鑑落地出 Sydney 引導泡泡，把 onboarding
                          // 的教練陪伴接到落地頁（只有這條路會帶）。
                          '/practice-collection?guide=1',
                          hasPartner: false,
                        ),
                      );
                    }
                    // 問卷插頁後，index 3 之後的靜態頁往前挪一格。
                    final page = _pages[
                        index < _questionnairePageIndex ? index : index - 1];
                    // 轉化診斷 Tier 1-1：第 2、3 頁掛零 API 示範卡，
                    // 讓「投入度」「五種風格」用演的不是用講的。
                    final demo = switch (page['imagePath']) {
                      'analyze' => const DemoSignalPreview(),
                      'reply' => const DemoStylesPreview(),
                      _ => null,
                    };
                    return OnboardingPage(
                      title: page['title']!,
                      description: page['description']!,
                      imagePath: page['imagePath']!,
                      heroImageAsset: page['heroImage'],
                      customContent: demo,
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
                    _pages.length + 2,
                    (index) => AnimatedContainer(
                      duration: AppMotion.enter,
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
              if (_currentPage < _pages.length + 1)
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
                // 2026-08-01 轉化診斷 Tier 1：分流頁 hero 改品牌教練 Sydney
                // （鼓勵姿勢），與第 1 頁的 greeting 前後呼應。
                Semantics(
                  image: true,
                  label: 'VibeSync Coach Sydney，欣欣',
                  child: Image.asset(
                    'assets/images/coach/sydney_encouragement.png',
                    key: const ValueKey('onboarding-branch-hero-image'),
                    height: 220,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(height: 40),
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
                const SizedBox(height: 6),
                // 按之前先講兩條路各通到哪（按之後回一句＝多一次點擊或計時器
                // 等待，都是在轉化最後一步加摩擦）。「先抽一位練習夥伴」對齊
                // 真實落地頁：按下去到圖鑑翻牌，Sydney 泡泡接著就叫你抽。
                _branchHint('先幫你把她這輪的訊號讀懂'),
                const SizedBox(height: 16),
                BrandSecondaryButton(
                  label: '還沒，先去練習',
                  onPressed: onNoPartner,
                ),
                const SizedBox(height: 6),
                _branchHint('先抽一位練習夥伴，把手感練起來'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _branchHint(String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundSecondary.withValues(alpha: 0.76),
        ),
      );
}
