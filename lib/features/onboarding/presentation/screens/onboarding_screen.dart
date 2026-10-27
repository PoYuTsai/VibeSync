// lib/features/onboarding/presentation/screens/onboarding_screen.dart
//
// onboarding 轉換第 12 步（Eric 2026-10-27「全部都做 照夥伴預設」）：由 9 頁
// （6 頁功能介紹＋問卷＋獨立隱私頁＋分流頁）改成 4 頁，先問他現在要做什麼，
// 用最短的路帶他到第一件事——
//   0. OnboardingIntentPage：她回我了／剛配對／還沒有對象，或「先逛逛」略過；
//   1. OnboardingQuizTeaserPage：內建題庫的一題判讀，答完看解析（可「直接開始」）；
//   2. OnboardingQuestionnairePage：目標最多 2 個、鏡像卡（可「略過」）；
//   3. OnboardingFinishPage：登入後先做什麼、免費額度、AI 隱私一行＋看完整說明。
// 「繼續」→ 寫暫存 → 登入頁；登入後 MainShell 的 OnboardingHandoffApplier 帶他去
// 第 1 頁選的地方。右上「我有帳號」直接到登入、不寫暫存。
// 換頁只用按鈕（不能滑）：第 1 頁要選了路徑才往下走。
// 回退：沒有遠端開關（App 沒有遠端設定），要退回 9 頁版就 git revert 再出新版。
// `onboarding_completed` 這個鍵不改名（改了會把已登入的舊用戶拉回 onboarding）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/app_haptics.dart';
import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../learning/domain/models/chat_quiz.dart';
import '../../../partner/presentation/screens/add_partner_screen.dart'
    show AddPartnerScreen;
import '../../../user_profile/data/providers/user_profile_providers.dart';
import '../../../user_profile/domain/entities/user_profile.dart';
import '../../data/onboarding_quiz.dart';
import '../../data/onboarding_service.dart';
import '../../domain/onboarding_intent.dart';
import '../widgets/onboarding_finish_page.dart';
import '../widgets/onboarding_intent_page.dart';
import '../widgets/onboarding_questionnaire_page.dart';
import '../widgets/onboarding_quiz_teaser_page.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const pageCount = 4;
  static const intentPage = 0;
  static const quizPage = 1;
  static const questionnairePage = 2;
  static const finishPage = 3;

  static const haveAccountLabel = '我有帳號';
  static const skipQuizLabel = '直接開始';
  static const skipQuestionnaireLabel = '略過';
  static const nextLabel = '下一步';
  static const finishLabel = '繼續';

  /// 第 1 頁的路徑登入後要去哪。未登入時這串原樣存進暫存、登入後才 push。
  static String? routeForIntent(OnboardingIntent intent) => switch (intent) {
        // 建好對象卡直接到選截圖（第 10 步）。
        OnboardingIntent.analyze => AddPartnerScreen.screenshotFlowLocation,
        OnboardingIntent.opener => '/opener',
        // guide=1：圖鑑落地出 Sydney 引導泡泡；免費帳號第一次進來就發首抽（第 1 步，決策 C）。
        OnboardingIntent.practice => '/practice-collection?guide=1',
        OnboardingIntent.browse => null,
      };

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = OnboardingScreen.intentPage;

  OnboardingIntent? _intent;

  // 第 2 頁：作答一次就定案。
  String? _quizChoiceId;
  bool? _quizCorrect;

  // 問卷選擇存在這裡，本頁不寫 Hive，按「繼續」才一次種（或暫存）。
  // 2026-08-04 拍板：問卷只留練習目標。
  List<PracticeGoal> _goals = const [];

  // 已經按了離開（繼續／先逛逛／我有帳號）：轉場期間再按不重複送。
  bool _leaving = false;

  FunnelTracker get _funnel => ref.read(funnelTrackerProvider);

  @override
  void initState() {
    super.initState();
    // 第 0 頁不是換頁換來的，漏斗第一格在這裡補（GLM 審查 F5：否則第一頁就
    // 跳出的流失測不見）。
    unawaited(
      _funnel.track(
        'onboarding_page_view',
        properties: {'page_index': OnboardingScreen.intentPage},
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 換頁：每換一頁記一筆 page_view（含按上一頁回去）。相鄰頁滑過去，跳頁
  /// （「直接開始」「略過」）直接切，免得滑過中間那頁又多記一筆。
  void _goToPage(int page) {
    if (page == _currentPage || !_pageController.hasClients) return;
    final adjacent = (page - _currentPage).abs() == 1;
    setState(() => _currentPage = page);
    AppHaptics.tap();
    unawaited(
      _funnel.track('onboarding_page_view', properties: {'page_index': page}),
    );
    if (adjacent) {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _pageController.jumpToPage(page);
    }
  }

  void _goBack() {
    if (_currentPage > OnboardingScreen.intentPage) {
      _goToPage(_currentPage - 1);
    }
  }

  void _selectIntent(OnboardingIntent intent) {
    // 換頁動畫期間連點第二下不重記、不重複換頁。
    if (_leaving || _currentPage != OnboardingScreen.intentPage) return;
    unawaited(
      _funnel.track('onboarding_intent', properties: {'intent': intent.wire}),
    );
    setState(() => _intent = intent);
    _goToPage(OnboardingScreen.quizPage);
  }

  void _answerQuiz(ChatQuizQuestion question, String choiceId) {
    if (_quizChoiceId != null) return;
    final correct = question.isCorrectChoice(choiceId);
    setState(() {
      _quizChoiceId = choiceId;
      _quizCorrect = correct;
    });
    unawaited(
      _funnel.track('onboarding_quiz_answer', properties: {'correct': correct}),
    );
  }

  /// 「先逛逛」：不選路徑、略過整個 onboarding（每頁可逃生）。不寫暫存，
  /// 登入後落在首頁。
  Future<void> _browse() async {
    if (_leaving) return;
    _leaving = true;
    unawaited(
      _funnel.track(
        'onboarding_intent',
        properties: {'intent': OnboardingIntent.browse.wire},
      ),
    );
    unawaited(
      _funnel.track(
        'onboarding_skip',
        properties: {'page_index': _currentPage},
      ),
    );
    await _markCompletedAndGo('/');
  }

  /// 「我有帳號」：直接到登入、不寫暫存。一定要先記成看過 onboarding：未登入
  /// 又沒看過 onboarding 的人會被 resolveAppRedirect 拉回 /onboarding，順序
  /// 反過來會卡在迴圈。
  Future<void> _haveAccount() async {
    if (_leaving) return;
    _leaving = true;
    await _markCompletedAndGo('/login');
  }

  Future<void> _markCompletedAndGo(String location) async {
    try {
      await OnboardingService.markCompleted();
    } catch (e) {
      // 記號寫不進手機也照走：記憶體裡的快取已經翻成完成，這次不會被拉回來。
      debugPrint('[OnboardingScreen] markCompleted failed (ignored): $e');
    }
    if (mounted) context.go(location);
  }

  /// 第 4 頁「繼續」：未登入時把路徑、目標、測驗結果寫進暫存再去登入頁；
  /// 已登入（少見：這支手機沒看過 onboarding）就直接種 profile、帶去目的地。
  Future<void> _finish() async {
    if (_leaving) return;
    _leaving = true;
    final intent = _intent;
    final route =
        intent == null ? null : OnboardingScreen.routeForIntent(intent);
    unawaited(
      _funnel.track(
        'onboarding_questionnaire_submit',
        properties: {'goals_count': _goals.length},
      ),
    );
    final String? uid;
    try {
      uid = await ref.read(authUserProfileScopeProvider.future);
    } catch (e) {
      debugPrint('[OnboardingScreen] auth scope failed: $e');
      _leaving = false;
      return;
    }
    if (!mounted) return;
    if (uid == null) {
      if (intent != null && route != null) {
        try {
          await OnboardingService.stashPendingHandoff(
            intent: intent,
            route: route,
            goalNames: [for (final goal in _goals) goal.name],
            quizCorrect: _quizCorrect,
          );
        } catch (e) {
          // 暫存寫不進去就只少了登入後的導頁與目標，照樣去登入頁。
          debugPrint('[OnboardingScreen] stash failed (ignored): $e');
        }
      }
      // 回到 '/'，redirect 會落到 /login。
      await _markCompletedAndGo('/');
      return;
    }
    await _seedProfileFromGoals();
    try {
      await OnboardingService.markCompleted();
    } catch (e) {
      debugPrint('[OnboardingScreen] markCompleted failed (ignored): $e');
    }
    if (!mounted) return;
    // 先 go('/') 再 push：返回鍵退回首頁，不卡死（2026-07-06 案 3）。
    context.go('/');
    if (route != null) context.push(route);
  }

  /// 已登入時直接種目標：只在 profile 全空時種、失敗靜默、絕不擋導頁。目標全
  /// 略過就不建任何資料（2026-08-03「關於我」重新定位）。
  Future<void> _seedProfileFromGoals() async {
    if (_goals.isEmpty) return;
    try {
      final existing = await ref.read(userProfileControllerProvider.future);
      if (existing != null && !existing.isEmpty) return;
      await ref.read(userProfileControllerProvider.notifier).save(
            UserProfile.create(
              practiceGoals: List.of(_goals),
              updatedAt: DateTime.now(),
            ),
          );
    } catch (_) {
      // best-effort：種子失敗不影響 onboarding 完成與導頁。
    }
  }

  /// 第 2 頁的「下一步」：作答後才能按；題目打不開（讀不到題庫或找不到題）時
  /// 直接可按，不擋路。
  bool get _quizNextEnabled {
    if (_quizChoiceId != null) return true;
    final item = ref.watch(onboardingQuizItemProvider);
    return item.hasError || (item.hasValue && item.value == null);
  }

  ({String label, VoidCallback? onPressed})? _bottomAction() =>
      switch (_currentPage) {
        OnboardingScreen.quizPage => (
            label: OnboardingScreen.nextLabel,
            onPressed: _quizNextEnabled
                ? () => _goToPage(OnboardingScreen.questionnairePage)
                : null,
          ),
        OnboardingScreen.questionnairePage => (
            label: OnboardingScreen.nextLabel,
            onPressed: () => _goToPage(OnboardingScreen.finishPage),
          ),
        OnboardingScreen.finishPage => (
            label: OnboardingScreen.finishLabel,
            onPressed: _finish,
          ),
        _ => null,
      };

  ({String label, VoidCallback onPressed})? _topAction() =>
      switch (_currentPage) {
        OnboardingScreen.intentPage => (
            label: OnboardingScreen.haveAccountLabel,
            onPressed: _haveAccount,
          ),
        // 「直接開始」：跳過測驗與目標，直接到最後一頁（下一步與隱私一行照樣看得到）。
        OnboardingScreen.quizPage => (
            label: OnboardingScreen.skipQuizLabel,
            onPressed: () => _goToPage(OnboardingScreen.finishPage),
          ),
        // 「略過」目標：不帶目標到最後一頁。
        OnboardingScreen.questionnairePage => (
            label: OnboardingScreen.skipQuestionnaireLabel,
            onPressed: () {
              setState(() => _goals = const []);
              _goToPage(OnboardingScreen.finishPage);
            },
          ),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final bottom = _bottomAction();
    final top = _topAction();
    return BrandPageBackground(
      child: PopScope(
        // 系統返回（Android 返回鍵、iOS 邊緣滑）在第 2–4 頁回上一頁，不離開 onboarding。
        canPop: _currentPage == OnboardingScreen.intentPage,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goBack();
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                _OnboardingTopBar(
                  currentPage: _currentPage,
                  onBack: _currentPage > OnboardingScreen.intentPage
                      ? _goBack
                      : null,
                  actionLabel: top?.label,
                  onAction:
                      top == null ? null : AppHaptics.onPress(top.onPressed),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      OnboardingIntentPage(
                        selected: _intent,
                        onSelect: _selectIntent,
                        onBrowse: () {
                          AppHaptics.light();
                          unawaited(_browse());
                        },
                      ),
                      OnboardingQuizTeaserPage(
                        selectedChoiceId: _quizChoiceId,
                        onAnswer: _answerQuiz,
                      ),
                      OnboardingQuestionnairePage(
                        selectedGoals: _goals,
                        onGoalsChanged: (goals) =>
                            setState(() => _goals = goals),
                      ),
                      OnboardingFinishPage(
                        intent: _intent,
                        hasGoals: _goals.isNotEmpty,
                        onOpenPrivacy: () =>
                            unawaited(showOnboardingPrivacySheet(context)),
                      ),
                    ],
                  ),
                ),
                if (bottom != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: BrandPrimaryButton(
                      label: bottom.label,
                      onPressed: bottom.onPressed,
                      verticalPadding: 16,
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

/// 頂列：左邊上一頁（第 2–4 頁）、中間頁數點、右邊逃生出口（我有帳號／
/// 直接開始／略過）。
class _OnboardingTopBar extends StatelessWidget {
  const _OnboardingTopBar({
    required this.currentPage,
    required this.onBack,
    required this.actionLabel,
    required this.onAction,
  });

  final int currentPage;
  final VoidCallback? onBack;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _PageDots(current: currentPage),
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: IconButton(
                  onPressed: onBack,
                  tooltip: '上一頁',
                  color: Colors.white,
                  icon: const BackButtonIcon(),
                ),
              ),
            ),
          if (actionLabel != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: onAction,
                  child: Text(
                    actionLabel!,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '第 ${current + 1} 頁，共 ${OnboardingScreen.pageCount} 頁',
      child: ExcludeSemantics(
        child: Row(
          key: const ValueKey('onboarding-page-dots'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < OnboardingScreen.pageCount; index++)
              AnimatedContainer(
                duration: AppMotion.enter,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: current == index ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: current == index
                      ? AppColors.ctaStart
                      : Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
