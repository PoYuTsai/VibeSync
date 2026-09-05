import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../data/providers/practice_chat_providers.dart';
import '../../data/repositories/practice_game_intro_store.dart';
import '../../data/repositories/practice_session_repository.dart';
import '../../domain/entities/practice_acquaintance_origin.dart';
import '../../domain/entities/practice_hint.dart';
import '../../domain/entities/practice_learning_mode.dart';
import '../../domain/entities/practice_message.dart';
import '../../domain/entities/practice_profile.dart';
import '../../domain/entities/practice_session.dart';
import '../widgets/practice_debrief_card.dart';
import '../widgets/practice_game_coach_intro.dart';
import '../widgets/practice_game_intro_sheet.dart';
import '../widgets/practice_girl_photo.dart';
import '../widgets/practice_profile_sheet.dart';
import '../widgets/practice_temperature_style.dart';
import '../widgets/practice_wait_progress.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../shared/widgets/brand/brand_dialog.dart';
import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_icons.dart';

/// AI 實戰練習室主畫面：點入直接進聊天（不選目標）。
/// 使用者先發訊息，AI 扮演模擬對象回覆；最多 20 則 AI 回覆；
/// 結束練習產一張教練拆解卡。
class PracticeChatScreen extends ConsumerStatefulWidget {
  const PracticeChatScreen({super.key, this.startProfileId});

  /// 圖鑑點卡入口：帶 profileId 進場時由本頁發起開局（續玩或免費開新局）。
  /// 開局必須由本頁（controller 唯一 watcher）發起：controller 是 autoDispose，
  /// 若在圖鑑頁先 read+seed，導航間隙零 listener 會被 dispose、seed 全丟。
  final String? startProfileId;

  @override
  ConsumerState<PracticeChatScreen> createState() => _PracticeChatScreenState();
}

class _BoundAppliedHintDraft {
  const _BoundAppliedHintDraft({
    required this.reply,
    required this.sessionId,
    required this.aiReplyCount,
  });

  final PracticeHintReply reply;
  final String sessionId;
  final int aiReplyCount;

  bool matches(PracticeChatState state) =>
      sessionId == state.sessionId && aiReplyCount == state.aiReplyCount;
}

class _PracticeChatScreenState extends ConsumerState<PracticeChatScreen> {
  final _controller = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  _BoundAppliedHintDraft? _appliedHintDraft;

  // Game 教學卡本場只檢查一次（彈過或已確認 seen 就不再彈）；async gap 前
  // 先佔位，避免 listener 與 post-frame 兩條觸發路徑重入雙彈。
  bool _gameIntroChecked = false;

  /// 已按「開始和她聊」進到對話框的場次 id。存 sessionId 而不是 bool：翻新一位、
  /// 續玩開新場、還原別場都會換 id，畫面自動退回資料卡首屏，不必再補 reset。
  String? _chatOpenedSessionId;

  @override
  void initState() {
    super.initState();
    final startProfileId = widget.startProfileId;
    if (startProfileId != null) {
      // 必須 post-frame：riverpod 禁止 build 期間同步改 provider state；
      // 此時首幀的 watch 已掛上 listener，controller 不會再被 autoDispose。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(practiceChatControllerProvider.notifier)
            .startSessionWithProfile(startProfileId);
      });
    }
    // 草稿還原路徑：進場時 learningMode 可能已經是 game（首幀就成立，
    // ref.listen 等不到轉變事件），post-frame 補一次檢查。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeShowGameIntro();
    });
  }

  /// 開啟 Game 教學卡；Free 帳號附訂閱鈎子，點「查看方案」導付費牆。
  /// 非 SR（鎖定）也開得了：CTA 分流見 sheet；已訂閱點「去圖鑑翻牌」導圖鑑。
  /// 任何路徑看過即 markSeen（首次自動彈與鎖定點擊共用這條）。
  Future<void> _openGameIntroSheet() async {
    final isPremium = ref.read(subscriptionProvider).isPremium;
    final locked = !ref.read(practiceChatControllerProvider).canUseGameMode;
    // async gap 後可能已 unmount，store 先取好再 await。
    final store = ref.read(practiceGameIntroStoreProvider);
    final result = await showPracticeGameIntroSheet(
      context,
      showUpgradeHook: !isPremium,
      locked: locked,
    );
    await store.markSeen();
    if (!mounted) return;
    if (result == PracticeGameIntroResult.viewPlans) {
      context.push('/paywall');
    } else if (result == PracticeGameIntroResult.goDraw) {
      context.push('/practice-collection');
    }
  }

  /// 首次進入 Game（手動選到或草稿還原）且未看過教學卡 → 彈一次。
  /// CTA／滑掉／點外面關閉都算看過（sheet future resolve 後 markSeen）。
  Future<void> _maybeShowGameIntro() async {
    if (_gameIntroChecked) return;
    final state = ref.read(practiceChatControllerProvider);
    if (state.learningMode != PracticeLearningMode.game ||
        state.messages.isNotEmpty) {
      return;
    }
    _gameIntroChecked = true;
    final store = ref.read(practiceGameIntroStoreProvider);
    if (await store.isSeen()) return;
    if (!mounted) return;
    // async gap 後模式可能已被切走：讓下一次進 game 再觸發。
    if (ref.read(practiceChatControllerProvider).learningMode !=
        PracticeLearningMode.game) {
      _gameIntroChecked = false;
      return;
    }
    await _openGameIntroSheet();
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 首屏 CTA：一記強震（Eric 指定強烈觸覺）後直接進對話框——訊息還是空的，
  /// 白底對話框先掛「你們怎麼認識的」，並把游標送進輸入列，讓使用者不必再點
  /// 一次就能打第一句。
  void _openChat(String sessionId) {
    unawaited(AppHaptics.strong());
    setState(() => _chatOpenedSessionId = sessionId);
    _inputFocusNode.requestFocus();
  }

  Future<void> _send() async {
    // 分則鐵律（2026-08-11）：輸入框裡的換行代表「連發 2-3 則短訊」，畫面上會
    // 拆成多顆泡（見 _Bubble），但送出去**永遠是一則訊息、一個 turn、一次請求、
    // 扣一次額度**。絕不可以改成迴圈送 N 次——那會扣 N 次額度、讓她回 N 次，
    // 而且本地索引會和 request.turns 索引錯開，appliedHintTurns[].turnIndex
    // 一錯，debrief 的「你有照提示做」就會歸錯人。
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    // 練習對話會送到 DeepSeek 生成模擬對象回覆，首次須取得第三方 AI 資料使用同意
    // （走 DeepSeek，與 Claude 功能各自獨立）。不同意則保留輸入、不送出、不扣額度。
    final consented = await AiDataSharingConsent.ensure(
      context,
      featureLabel: 'AI 實戰練習室',
      consentKey: AiDataSharingConsent.practiceConsentKey,
      destinationLabel: AiDataSharingConsent.practiceDestinationLabel,
      dataDescription: AiDataSharingConsent.practiceDataDescription,
      purposeText: AiDataSharingConsent.practicePurposeText,
    );
    if (!consented || !mounted) return;
    final currentState = ref.read(practiceChatControllerProvider);
    final boundDraft = _appliedHintDraft;
    final appliedHintDraft =
        boundDraft?.matches(currentState) == true ? boundDraft!.reply : null;
    final appliedHintType = appliedHintDraft?.type;
    final appliedHintText = appliedHintDraft?.text.trim();
    final appliedHintRequestId = appliedHintDraft?.hintRequestId;
    final appliedHintDecision = appliedHintDraft?.decision;
    _controller.clear();
    AppHaptics.light();
    await ref.read(practiceChatControllerProvider.notifier).sendMessage(
          text,
          appliedHintType: appliedHintType,
          appliedHintText: appliedHintText,
          appliedHintRequestId: appliedHintRequestId,
          appliedHintDecision: appliedHintDecision,
        );
    if (!mounted) return;
    final nextState = ref.read(practiceChatControllerProvider);
    final restoredSameText = nextState.restoreText == text;
    _appliedHintDraft =
        restoredSameText && boundDraft?.matches(nextState) == true
            ? boundDraft
            : null;
  }

  Future<void> _requestHint() async {
    _inputFocusNode.unfocus();
    final consented = await AiDataSharingConsent.ensure(
      context,
      featureLabel: 'AI 實戰練習室',
      consentKey: AiDataSharingConsent.practiceConsentKey,
      destinationLabel: AiDataSharingConsent.practiceDestinationLabel,
      dataDescription: AiDataSharingConsent.practiceDataDescription,
      purposeText: AiDataSharingConsent.practicePurposeText,
    );
    if (!consented || !mounted) return;
    ref.read(practiceChatControllerProvider.notifier).requestHint();
  }

  /// 續聊同一位：付費才放行；Free 由 controller 觸發付費牆（不動 transcript）。
  void _continueSamePartner() {
    final isPaid = ref.read(subscriptionProvider).isPremium;
    ref
        .read(practiceChatControllerProvider.notifier)
        .continueWithSamePartner(isPaid: isPaid);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: AppMotion.scroll,
        curve: AppMotion.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(practiceChatControllerProvider);

    // 訊息變動或開始等待 → 捲到底。
    ref.listen(practiceChatControllerProvider, (prev, next) {
      final turnChanged = prev != null &&
          (prev.sessionId != next.sessionId ||
              prev.aiReplyCount != next.aiReplyCount ||
              prev.messages.length != next.messages.length);
      if (turnChanged) {
        _appliedHintDraft = null;
        _controller.clear();
      }
      if (prev?.messages.length != next.messages.length ||
          prev?.isSending != next.isSending ||
          prev?.debrief != next.debrief) {
        _scrollToBottom();
      }
      // 失敗時把使用者剛打的字還回輸入列。
      if (next.restoreText != null &&
          next.restoreText != prev?.restoreText &&
          _controller.text.isEmpty) {
        _controller.text = next.restoreText!;
      }
      // 切到 Game（手動選或草稿還原補水）→ 首次教學卡。
      if (next.learningMode == PracticeLearningMode.game &&
          prev?.learningMode != PracticeLearningMode.game) {
        _maybeShowGameIntro();
      }
    });

    // 首屏＝資料卡：還沒按「開始和她聊」而且一則訊息都還沒送出。按下 CTA 後
    // 即使 messages 仍是空的也算已開聊，畫面換成 compact header ＋ 對話框。
    final showOpeningProfile =
        state.messages.isEmpty && _chatOpenedSessionId != state.sessionId;

    // 尚未翻牌（locked / drawing / error）：不顯示任何對象，只給翻牌入口。
    final Widget content;
    final shouldShowLockedEntry = !state.isRevealed && state.girl == null;
    if (shouldShowLockedEntry) {
      content = BrandScaffold(
        title: 'AI 實戰練習室',
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '最近練習',
            onPressed: () => _openHistory(context),
          ),
        ],
        resizeToAvoidBottomInset: true,
        body: _PracticeLockedEntry(state: state),
      );
    } else {
      content = BrandScaffold(
        title: 'AI 實戰練習室',
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '最近練習',
            onPressed: () => _openHistory(context),
          ),
        ],
        resizeToAvoidBottomInset: true,
        // iPhone 鍵盤沒有收起鍵：點輸入框以外任何空白處都要能退出輸入狀態，
        // 否則開場前的資訊卡被鍵盤壓縮後使用者會卡在打字模式。
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _inputFocusNode.unfocus(),
          child: Column(
            children: [
              // 開場前：難度控制（深色 scaffold 底，沿用原樣式；換一位入口
              // 已收斂角色圖鑑）。
              // 開聊後：compact identity header（小圓照片＋名字/職業/難度）。
              if (showOpeningProfile)
                _PracticeOpeningControls(
                  state: state,
                  onGameInfoTap: _openGameIntroSheet,
                )
              else
                _PracticeProfileBar(state: state),
              Expanded(
                child: _PracticeChatWorkspaceFrame(
                  opening: showOpeningProfile,
                  child: showOpeningProfile
                      ? _PracticeProfileHero(state: state)
                      : ListView(
                          controller: _scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                          children: [
                            // 空白對話框的場景說明：送出第一則後整塊消失，
                            // 對話框回到純訊息流。
                            if (state.messages.isEmpty)
                              _PracticeChatOriginIntro(state: state),
                            // Game 局固定頂部教練泡泡：UI-only，不進
                            // state.messages／API payload／Hive。
                            if (state.learningMode == PracticeLearningMode.game)
                              const PracticeGameCoachIntro(),
                            for (var i = 0; i < state.messages.length; i++)
                              _Bubble(
                                message: state.messages[i],
                                stagger: i == state.messages.length - 1,
                              ),
                            if (state.isSending) const _ThinkingBubble(),
                            if (state.debrief != null) ...[
                              const SizedBox(height: 8),
                              PracticeDebriefCard(
                                summary: state.debrief!.summary,
                                strengths: state.debrief!.strengths,
                                watchouts: state.debrief!.watchouts,
                                suggestedLine: state.debrief!.suggestedLine,
                                vibe: state.debrief!.vibe,
                                dateChance: state.debrief!.dateChance,
                                dateChanceReason:
                                    state.debrief!.dateChanceReason,
                                nextInviteMove: state.debrief!.nextInviteMove,
                                gameBreakdownPhaseReached:
                                    state.debrief!.gameBreakdown?.phaseReached,
                                gameBreakdownMissedVariable: state
                                    .debrief!.gameBreakdown?.missedVariable,
                                gameBreakdownFailureState:
                                    state.debrief!.gameBreakdown?.failureState,
                                gameBreakdownNextFirstLine:
                                    state.debrief!.gameBreakdown?.nextFirstLine,
                                gameBreakdownInviteDirection: state
                                    .debrief!.gameBreakdown?.inviteDirection,
                              ),
                            ],
                            if (state.hasRetiredDebrief) ...[
                              const SizedBox(height: 8),
                              const _RetiredDebriefNotice(),
                            ],
                          ],
                        ),
                ),
              ),
              if (state.errorMessage != null)
                _ErrorBanner(
                  message: state.errorMessage!,
                  showUpgrade: state.quotaExceeded ||
                      state.upgradeRequired ||
                      state.drawUpgradeRequired ||
                      state.drawQuotaExceeded,
                  onUpgrade: () => context.push('/paywall'),
                  onDismiss: () => ref
                      .read(practiceChatControllerProvider.notifier)
                      .clearError(),
                ),
              _BottomBar(
                state: state,
                inputController: _controller,
                inputFocusNode: _inputFocusNode,
                isDebriefing: state.isDebriefing,
                showStartCta: showOpeningProfile,
                onStartChat: () => _openChat(state.sessionId),
                onSend: _send,
                onEndPractice: () => ref
                    .read(practiceChatControllerProvider.notifier)
                    .endPractice(),
                onRequestHint: () => _requestHint(),
                onHintApplied: (reply) {
                  final current = ref.read(practiceChatControllerProvider);
                  _appliedHintDraft = _BoundAppliedHintDraft(
                    reply: reply,
                    sessionId: current.sessionId,
                    aiReplyCount: current.aiReplyCount,
                  );
                },
                onFinish: () async {
                  // 收尾必須等持久化成功才離開；失敗時留在畫面，否則這局
                  // 下次會被練習室無限接回（R1 主審 P1：不得靜默漏標記）。
                  final closed = await ref
                      .read(practiceChatControllerProvider.notifier)
                      .closeCurrentSession();
                  if (!context.mounted) return;
                  if (closed) {
                    context.pop();
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('收尾沒有存檔成功，請再按一次「完成」。'),
                    ),
                  );
                },
                onContinueSamePartner: _continueSamePartner,
                // 換人＝回圖鑑翻牌（top-level route，go 收斂 stack）。
                onNewPartner: () => context.go('/practice-collection'),
              ),
            ],
          ),
        ),
      );
    }

    // 翻牌揭曉儀式 overlay 已搬到角色圖鑑頁（翻牌入口所在地）；本頁不再掛載。
    return content;
  }

  void _openHistory(BuildContext context) {
    final sessions = ref.read(recentPracticeSessionsProvider);
    showAppSheet<void>(
      context: context,
      backgroundColor: AppColors.brandInk,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _RecentSessionsSheet(
        sessions: sessions,
        onResume: (session) {
          ref.read(practiceChatControllerProvider.notifier).resumeSession(
                session,
              );
        },
        onDelete: (session) async {
          // 刪整段對話（含同一位的所有續玩輪次），不能只刪最新一輪讓舊輪浮回。
          await ref.read(practiceSessionRepositoryProvider).deleteVisibleThread(
                PracticeSessionRepository.threadKeyOf(session),
              );
          ref.invalidate(recentPracticeSessionsProvider);
        },
      ),
    );
  }
}

// ── 未翻牌入口：每日翻牌 CTA（Batch 3 最小可用層；卡背/3D/光圈 等視覺留 Batch 4）──
class _PracticeLockedEntry extends ConsumerWidget {
  const _PracticeLockedEntry({required this.state});

  final PracticeChatState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upgradeLocked = state.drawUpgradeRequired;
    final quotaLocked = state.drawQuotaExceeded;
    // 批 3：free 每日免費抽已移除，「每日」字樣只對付費 tier 為真。
    final isPremium = ref.watch(subscriptionProvider).isPremium;
    return Center(
      child: SingleChildScrollView(
        key: const ValueKey('practice-locked-entry'),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 52,
              color: AppColors.ctaStart,
            ),
            const SizedBox(height: 24),
            Text(
              isPremium ? '每日登入解鎖新女孩' : '翻牌解鎖新女孩',
              textAlign: TextAlign.center,
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '到角色圖鑑翻開今日對象，開始練習。',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (upgradeLocked || quotaLocked)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('practice-draw-upgrade-primary'),
                  onPressed: AppHaptics.onPress(() => context.push('/paywall')),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ctaStart,
                    foregroundColor: AppColors.onCta,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(upgradeLocked ? '升級解鎖更多女孩' : '查看方案'),
                ),
              )
            else
              // Task 5：翻牌觸發點全收斂角色圖鑑，這裡只做導引。
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('practice-goto-collection-cta'),
                  onPressed: AppHaptics.onPress(() => context.push('/practice-collection')),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ctaStart,
                    foregroundColor: AppColors.onCta,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('去圖鑑翻牌'),
                ),
              ),
            if (state.drawUpgradeRequired) ...[
              const SizedBox(height: 16),
              Text(
                state.errorMessage ?? '升級後每天可以翻更多陪練女孩。',
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('practice-draw-upgrade'),
                onPressed: () => context.push('/paywall'),
                child: const Text('升級解鎖'),
              ),
            ] else if (state.drawQuotaExceeded) ...[
              const SizedBox(height: 16),
              Text(
                // 翻牌窗以台北中午 12 點為界（server draw_decision.ts）；
                // 「明天中午」在中午前用完的情境是錯的，講週期不講日期。
                state.errorMessage ?? '額度已用完，每天中午 12 點重置。',
                key: const ValueKey('practice-draw-quota'),
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: AppColors.error,
                ),
              ),
            ] else if (state.errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 開場前控制列：難度 chips（深色 scaffold 底，沿用原樣式）──
// 換一位入口已收斂角色圖鑑（Task 5）：這裡只留難度與教學模式控制。
class _PracticeOpeningControls extends ConsumerWidget {
  const _PracticeOpeningControls({
    required this.state,
    required this.onGameInfoTap,
  });

  final PracticeChatState state;
  final VoidCallback onGameInfoTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DifficultyChips(state: state),
          const SizedBox(height: 8),
          _LearningModeToggle(
            state: state,
            onChanged: (mode) => ref
                .read(practiceChatControllerProvider.notifier)
                .setPracticeLearningMode(mode),
            onGameInfoTap: onGameInfoTap,
          ),
        ],
      ),
    );
  }
}

// ── 聊天中對象列：compact identity header（小圓照片＋名字/職業/難度），點開 profile sheet ──
class _PracticeProfileBar extends StatelessWidget {
  const _PracticeProfileBar({required this.state});

  final PracticeChatState state;

  @override
  Widget build(BuildContext context) {
    final girl = state.girl!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showPracticeProfileSheet(
          context,
          girl,
          threadId: practiceThreadIdFor(
            sessionId: state.sessionId,
            visiblePracticeThreadId: state.visiblePracticeThreadId,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              PracticeGirlPhoto(
                key: const ValueKey('practice-profile-avatar'),
                profile: girl,
                width: 40,
                height: 40,
                circle: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${girl.displayName} · ${girl.professionLabel}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onBackgroundSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${girl.age} · ${girl.city} · ${state.difficultyLabel}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.expand_more,
                size: 18,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DifficultyChips extends ConsumerWidget {
  const _DifficultyChips({required this.state});

  final PracticeChatState state;

  static const _options = <(PracticeDifficultyPreference, String, String)>[
    (PracticeDifficultyPreference.easy, '輕鬆', '她今天心情不錯，願意給你空間'),
    (PracticeDifficultyPreference.normal, '一般', '真實體感，會已讀、會變短'),
    (PracticeDifficultyPreference.challenge, '挑戰', '高標準對象，不救場、會句點你'),
    (PracticeDifficultyPreference.random, '隨機', '每場隨機抽一檔難度'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 防禦性 orElse：enum 之後加值若忘了同步 _options，chip 只是少畫一顆
    // （靜默），這裡絕不能讓 firstWhere 丟 StateError 崩整頁 → 退回最後一筆。
    final (_, _, subtitle) = _options.firstWhere(
      (option) => option.$1 == state.difficultyPreference,
      orElse: () => _options.last,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 夥伴稿：四檔難度是一條連體 segmented bar，不是四顆各自帶框的 pill。
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.brandInk.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              for (final (pref, label, _) in _options)
                Expanded(
                  child: _DifficultyChip(
                    label: label,
                    selected: state.difficultyPreference == pref,
                    onTap: () {
                      // 只在真的切檔時震；重複點已選中那格不震。
                      if (state.difficultyPreference != pref) {
                        AppHaptics.light();
                      }
                      ref
                          .read(practiceChatControllerProvider.notifier)
                          .setDifficultyPreference(pref);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(
            color: AppColors.onBackgroundSecondary.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.state,
        curve: AppMotion.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.ctaStart.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.ctaStart.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(
            color:
                selected ? AppColors.ctaStart : AppColors.onBackgroundSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── 淺色聊天工作區：沿用 analyze-chat 的對話視窗底色 ─────────────────────
class _LearningModeToggle extends StatelessWidget {
  const _LearningModeToggle({
    required this.state,
    required this.onChanged,
    required this.onGameInfoTap,
  });

  final PracticeChatState state;
  final ValueChanged<PracticeLearningMode> onChanged;

  /// 開 Game 教學卡：Game 選中時 info icon 重看；非 SR 點鎖定分頁也走這
  /// （2026-08-08 拍板：不分 N/R/SR 都要認識玩法，取代原本只閃鎖定字幕）。
  final VoidCallback onGameInfoTap;

  @override
  Widget build(BuildContext context) {
    final gameAvailable = state.canUseGameMode;
    final gameLockedByRarity = state.canChangeLearningMode && !gameAvailable;
    final descriptors = [
      const _LearningModeDescriptor(
        mode: PracticeLearningMode.standard,
        icon: Icons.chat_bubble_outline,
        title: '標準',
        badge: '真人感',
        summary: '她照真實反應，沒有教學鷹架',
        accent: Color(0xFFBCA7FF),
      ),
      const _LearningModeDescriptor(
        mode: PracticeLearningMode.beginner,
        icon: Icons.school_outlined,
        title: '新手',
        badge: '有提示',
        summary: 'AI 給提示，看著溫度計升溫',
        accent: AppColors.info,
      ),
      _LearningModeDescriptor(
        mode: PracticeLearningMode.game,
        icon: Icons.sports_esports_outlined,
        title: 'Game',
        badge: gameAvailable ? 'SR速約' : 'SR解鎖',
        summary: gameAvailable ? '她會考你、會給診斷，目標是速約' : '抽到 SR 角色卡解鎖 Game',
        accent: AppColors.ctaStart,
      ),
    ];
    final selectedDescriptor = descriptors.firstWhere(
      (descriptor) => descriptor.mode == state.learningMode,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.brandSurface2.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.18),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: descriptors.map((descriptor) {
                final enabled = descriptor.mode == PracticeLearningMode.game
                    ? state.canChangeLearningMode && gameAvailable
                    : state.canChangeLearningMode;
                return Expanded(
                  child: _LearningModeSegment(
                    key: ValueKey(
                      'practice-learning-mode-${descriptor.mode.name}',
                    ),
                    descriptor: descriptor,
                    selected: state.learningMode == descriptor.mode,
                    enabled: enabled,
                    onTap: () {
                      // 只在真的切模式時震；重複點已選中那格不震。
                      if (state.learningMode != descriptor.mode) {
                        AppHaptics.light();
                      }
                      onChanged(descriptor.mode);
                    },
                    // 鎖定的 Game 分頁點了開教學卡（不切模式），讓非 SR
                    // 用戶也認識玩法；解鎖條件在卡內講清楚。
                    onDisabledTap:
                        descriptor.mode == PracticeLearningMode.game &&
                                gameLockedByRarity
                            ? AppHaptics.onPress(onGameInfoTap)
                            : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          key: ValueKey(
            'practice-learning-mode-subtitle-${selectedDescriptor.mode.name}',
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Icon(
                selectedDescriptor.icon,
                size: 15,
                color: AppColors.onBackgroundSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${selectedDescriptor.title}｜${selectedDescriptor.summary}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Game 選中（必然已解鎖）才有教學卡可重看的 info icon。
              if (selectedDescriptor.mode == PracticeLearningMode.game)
                GestureDetector(
                  key: const ValueKey('practice-game-intro-info'),
                  onTap: AppHaptics.onPress(onGameInfoTap),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: selectedDescriptor.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LearningModeDescriptor {
  const _LearningModeDescriptor({
    required this.mode,
    required this.icon,
    required this.title,
    required this.badge,
    required this.summary,
    required this.accent,
  });

  final PracticeLearningMode mode;
  final IconData icon;
  final String title;
  final String badge;
  final String summary;
  final Color accent;
}

class _LearningModeSegment extends StatelessWidget {
  const _LearningModeSegment({
    super.key,
    required this.descriptor,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.onDisabledTap,
  });

  final _LearningModeDescriptor descriptor;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onDisabledTap;

  @override
  Widget build(BuildContext context) {
    final accent = descriptor.accent;
    final foreground = enabled
        ? selected
            ? AppColors.ctaStart
            : AppColors.onBackgroundSecondary.withValues(alpha: 0.88)
        : AppColors.onBackgroundSecondary.withValues(alpha: 0.42);
    final badgeColor = enabled
        ? selected
            ? AppColors.onBackgroundSecondary
            : accent
        : AppColors.onBackgroundSecondary.withValues(alpha: 0.45);
    return Tooltip(
      message: descriptor.summary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled ? onTap : onDisabledTap,
            child: AnimatedContainer(
              duration: AppMotion.state,
              curve: AppMotion.easeOut,
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              // 選中態沿用正上方難度 chip 的同一套處方（橘底＋橘框）。原本靠
              // 同一個紫色的不透明度差（0.92 vs 軌道 0.42）表達，深色底上看不出來。
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.ctaStart.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? AppColors.ctaStart.withValues(alpha: 0.45)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(descriptor.icon, size: 15, color: foreground),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          descriptor.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    descriptor.badge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: badgeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PracticeChatWorkspaceFrame extends StatelessWidget {
  const _PracticeChatWorkspaceFrame({
    required this.child,
    this.opening = false,
  });

  final Widget child;
  final bool opening;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 600 ? 600.0 : constraints.maxWidth;
        final frame = Padding(
          padding: opening
              ? const EdgeInsets.fromLTRB(16, 8, 16, 8)
              : const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _PracticeChatWorkspace(opening: opening, child: child),
        );

        return Center(
          child: constraints.hasBoundedHeight
              ? SizedBox(
                  width: width,
                  height: constraints.maxHeight,
                  child: frame,
                )
              : SizedBox(width: width, child: frame),
        );
      },
    );
  }
}

class _PracticeChatWorkspace extends StatelessWidget {
  const _PracticeChatWorkspace({
    required this.child,
    this.opening = false,
  });

  static const _radius = BorderRadius.all(Radius.circular(18));

  final Widget child;
  final bool opening;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('practice-chat-workspace'),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color:
            opening ? Colors.transparent : Colors.white.withValues(alpha: 0.96),
        borderRadius: opening ? BorderRadius.zero : _radius,
        border: opening
            ? null
            : Border.all(
                color: AppColors.ctaStart.withValues(alpha: 0.24),
              ),
        boxShadow: opening
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: opening
              ? AppColors.onBackgroundPrimary
              : AppColors.glassTextPrimary,
        ),
        child: child,
      ),
    );
  }
}

// ── 首屏 hero：以對象大照片 profile card 作為第一視覺，引導先發第一句 ──
class _PracticeProfileHero extends StatelessWidget {
  const _PracticeProfileHero({required this.state});

  final PracticeChatState state;

  @override
  Widget build(BuildContext context) {
    final girl = state.girl!;
    // 難度已由下方控制列的 chips 呈現，這裡只放人格／興趣／生活風格，避免重複。
    final tags = <String>[
      if (state.personaLabel.isNotEmpty) state.personaLabel,
      ...girl.interestTags.take(2),
      ...girl.lifestyleTags.take(1),
    ];
    // 認識場合要在送出第一句話「之前」就看得到——它決定開場該用什麼語氣切入
    // （街頭搭訕跟 IG 冷私訊的破冰方式完全不同），事後才在 profile sheet 看到
    // 等於練習當下缺了關鍵資訊。算法與 practice_profile_sheet.dart 用同一顆
    // practiceAcquaintanceOriginFor，threadId 組法也一致，保證跟開聊後看到的
    // 是同一個管道。
    final origin = practiceAcquaintanceOriginFor(
      profileId: girl.profileId,
      professionId: girl.professionId,
      threadId: practiceThreadIdFor(
        sessionId: state.sessionId,
        visiblePracticeThreadId: state.visiblePracticeThreadId,
      ),
    );
    // 首屏底部是「開始和她聊」CTA、沒有輸入框，鍵盤不可能壓在這張卡上面，
    // 所以這裡不再需要拖動收鍵盤的保護。
    return SingleChildScrollView(
      key: const ValueKey('practice-profile-hero'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            key: const ValueKey('practice-profile-hero-photo'),
            onTap: () => showPracticeGirlFullPhoto(context, girl),
            child: Stack(
              children: [
                PracticeGirlPhoto(
                  profile: girl,
                  width: double.infinity,
                  height: 320,
                  borderRadius: BorderRadius.circular(22),
                ),
                const Positioned(
                  right: 10,
                  bottom: 10,
                  child: PracticeGirlPhotoExpandHint(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${girl.displayName}，${girl.age}',
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${girl.professionLabel} · ${girl.city}',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
          const SizedBox(height: 8),
          // 夥伴稿：人格／興趣是一行點分隔文字，只有人格標籤用橘色，
          // 不再是四顆橘框 chip 跟照片搶視覺。
          Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < tags.length; i++) ...[
                  if (i > 0)
                    TextSpan(
                      text: '  ·  ',
                      style: TextStyle(
                        color: AppColors.onBackgroundSecondary.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  TextSpan(
                    text: tags[i],
                    style: TextStyle(
                      color: i == 0
                          ? AppColors.ctaStart
                          : AppColors.onBackgroundSecondary,
                    ),
                  ),
                ],
              ],
            ),
            style: AppTypography.bodyMedium.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.route_outlined,
                size: 16,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  origin.sharedFact,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            girl.selfIntro,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            state.learningMode == PracticeLearningMode.game
                ? '這局是 Game：照五階段推進——開場、展示、測試、張力、收尾。\n'
                    '第 1 步「開場」：用「狀態＋感受」丟一顆有情緒的球，'
                    '留一半讓她想追問。別用「在幹嘛」查戶口開局。'
                : '對方是個有自己個性的陪練女孩，不是教練。\n傳第一句出去，看看她怎麼回，練你的真實反應。',
            key: const ValueKey('practice-hero-guidance'),
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '首次 AI 回覆成功才扣 1 則；進來或送出失敗不扣。\n扣完這 1 則，本場最多可聊 20 則 AI 回覆，教練拆解不另扣。',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.72),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// 空白對話框的開場說明：把「你們是怎麼認識的」直接寫在對話框裡。
///
/// 為什麼要在這裡再寫一次（資料卡上已經有一份）——按下「開始和她聊」之後資料卡
/// 就收起來了，而認識場合正是決定第一句語氣的那個資訊（街頭搭訕跟 IG 冷私訊
/// 的破冰方式完全不同）。送出第一則訊息後由呼叫端（messages.isEmpty）整塊撤掉，
/// 不留在歷史訊息裡佔位。
///
/// 算法與 _PracticeProfileHero／practice_profile_sheet.dart 共用同一顆
/// practiceAcquaintanceOriginFor，threadId 組法也一致，保證三個地方看到的是
/// 同一個管道。
class _PracticeChatOriginIntro extends StatelessWidget {
  const _PracticeChatOriginIntro({required this.state});

  final PracticeChatState state;

  @override
  Widget build(BuildContext context) {
    final girl = state.girl!;
    final origin = practiceAcquaintanceOriginFor(
      profileId: girl.profileId,
      professionId: girl.professionId,
      threadId: practiceThreadIdFor(
        sessionId: state.sessionId,
        visiblePracticeThreadId: state.visiblePracticeThreadId,
      ),
    );
    return Padding(
      key: const ValueKey('practice-chat-origin-intro'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.ctaStart.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  TablerIcons.route,
                  size: 14,
                  color: AppColors.ctaEnd,
                ),
                const SizedBox(width: 6),
                Text(
                  origin.label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaEnd,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            origin.sharedFact,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 訊息泡泡 ──────────────────────────────────────────────────────────
// 沿用對話窗（analyze chat）的泡泡樣式：我說＝橘色系右對齊、她說＝紫色系左對齊。
//
// 分則顯示（2026-08-11）：真人傳 LINE 是一次連發 2-3 則短訊，不是一段長句。
// server 端的 NPC 回覆與 Hint 可貼句都改成用換行分則，這裡照換行拆成多顆泡。
//
// 鐵律：**多顆泡仍然是一則訊息、一個 turn、一次請求、扣一次額度**。
// 本地不會存成多筆 PracticeMessage——那會讓本地索引和 request.turns 索引錯開，
// 而 appliedHintTurns[].turnIndex 正是 debrief「你有照提示做」責任歸屬的鍵。
const int _kMaxBubbleSplit = 4;

/// 心法的第一句＝這輪戰術（prompt 契約保證）。開頭的「Game 心法：」是固定標籤，
/// 畫面上已有燈泡圖示，重複顯示只是佔一行，這裡剝掉。
String _coachingHeadline(String coaching) {
  final stripped = coaching.trim().replaceFirst(
        RegExp(r'^(Game\s*)?心法[:：]\s*'),
        '',
      );
  final end = stripped.indexOf('。');
  if (end > 0) return stripped.substring(0, end + 1);
  return stripped;
}

/// 依換行把一則訊息拆成多顆泡。超過上限就不拆（使用者可能貼了一段長文，
/// 拆成十幾顆泡會洗版），維持原本的單泡行為。
List<String> _splitBubbles(String text) {
  final parts = text
      .split('\n')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length <= 1 || parts.length > _kMaxBubbleSplit) {
    return <String>[text.trim()];
  }
  return parts;
}

class _Bubble extends StatefulWidget {
  const _Bubble({required this.message, this.stagger = false});
  final PracticeMessage message;

  /// 只有畫面上最新的一則會逐則跳出（間隔 1 秒），歷史訊息直接全顯示。
  final bool stagger;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  late List<String> _parts;
  late int _visible;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _parts = _splitBubbles(widget.message.text);
    // stagger 只在 widget 首次建立時決定，之後不重播：捲動或其他訊息進來
    // 造成的 rebuild 不該讓舊訊息再演一次。
    final shouldStagger = widget.stagger && _parts.length > 1;
    _visible = shouldStagger ? 1 : _parts.length;
    if (shouldStagger) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _visible++);
        if (_visible >= _parts.length) timer.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMe = message.isFromMe;
    final fillColor = isMe
        ? AppColors.ctaStart.withValues(alpha: 0.14)
        : AppColors.primaryLight.withValues(alpha: 0.18);
    final borderColor = isMe
        ? AppColors.ctaEnd.withValues(alpha: 0.46)
        : AppColors.primaryLight.withValues(alpha: 0.52);
    final speakerColor = isMe ? AppColors.ctaEnd : AppColors.primaryDark;

    final shown = _parts.take(_visible).toList();
    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < shown.length; index++)
          Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: EdgeInsets.only(
                top: index == 0 ? 4 : 2,
                bottom: index == shown.length - 1 ? 4 : 0,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(18).copyWith(
                  bottomRight: isMe && index == shown.length - 1
                      ? const Radius.circular(5)
                      : null,
                  bottomLeft: !isMe && index == shown.length - 1
                      ? const Radius.circular(5)
                      : null,
                ),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 說話者只標在第一顆泡，連發時不重複三次。
                  if (index == 0) ...[
                    Text(
                      isMe ? '我說' : '她說',
                      style: AppTypography.bodySmall.copyWith(
                        color: speakerColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    shown[index],
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.glassTextPrimary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomLeft: const Radius.circular(5),
          ),
          border: Border.all(
            color: AppColors.primaryLight.withValues(alpha: 0.52),
          ),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

// ── 錯誤 / 額度橫幅 ───────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.showUpgrade,
    required this.onUpgrade,
    required this.onDismiss,
  });

  final String message;
  final bool showUpgrade;
  final VoidCallback onUpgrade;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundPrimary,
                height: 1.4,
              ),
            ),
          ),
          if (showUpgrade)
            TextButton(
              onPressed: onUpgrade,
              child: Text(
                '升級',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.ctaStart,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.onBackgroundSecondary,
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}

// ── 底部輸入 / 動作列 ─────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.state,
    required this.inputController,
    required this.inputFocusNode,
    required this.isDebriefing,
    required this.showStartCta,
    required this.onStartChat,
    required this.onSend,
    required this.onEndPractice,
    required this.onRequestHint,
    required this.onHintApplied,
    required this.onFinish,
    required this.onContinueSamePartner,
    required this.onNewPartner,
  });

  final PracticeChatState state;
  final TextEditingController inputController;
  final FocusNode inputFocusNode;
  final bool isDebriefing;

  /// 首屏（資料卡）狀態：不給輸入框，只給「開始和她聊」CTA。
  final bool showStartCta;
  final VoidCallback onStartChat;
  final VoidCallback onSend;
  final VoidCallback onEndPractice;
  final VoidCallback onRequestHint;
  final ValueChanged<PracticeHintReply> onHintApplied;
  final VoidCallback onFinish;
  final VoidCallback onContinueSamePartner;
  final VoidCallback onNewPartner;

  @override
  Widget build(BuildContext context) {
    // 已看到拆解卡 → 收尾或續玩同一位（Eric 決策：續玩當主鈕）。
    if (state.debrief != null) {
      return _DebriefActionsBar(
        state: state,
        onContinueSamePartner: onContinueSamePartner,
        onNewPartner: onNewPartner,
        onFinish: onFinish,
      );
    }

    if (state.debriefFailed) {
      return _DebriefFailedActionsBar(
        retryable: state.debriefRetryable,
        onRetry: onEndPractice,
        onFinish: onFinish,
      );
    }

    // 拆解中。
    if (isDebriefing) {
      return _BarContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrandPrimaryButton(
              label: '教練拆解中…',
              isLoading: true,
              onPressed: () {},
            ),
            const SizedBox(height: 8),
            const PracticeWaitProgress(
              key: ValueKey('practice-debrief-wait-progress'),
              stages: [
                PracticeWaitStage(minSeconds: 0, label: '教練正在回顧整局對話…'),
                PracticeWaitStage(minSeconds: 10, label: '正在整理亮點和可以更好的地方…'),
                PracticeWaitStage(minSeconds: 25, label: '快好了，正在做最後檢查…'),
              ],
            ),
          ],
        ),
      );
    }

    // 已達 20 則上限 → 引導看拆解。
    if (state.sessionComplete) {
      return _BarContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '這場練習已達 20 則回覆',
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
            const SizedBox(height: 8),
            BrandPrimaryButton(label: '看教練拆解', onPressed: onEndPractice),
          ],
        ),
      );
    }

    // 一般聊天輸入。
    final canSend = state.canSend;
    final quotaLabel = state.aiReplyCount == 0
        ? '首次 AI 回覆成功才扣 1 則'
        : '本場已扣 1 則，還能聊 ${state.remainingReplies} 則';
    // 首屏：輸入框換成一顆 CTA。第一句的門檻不是「有沒有輸入框」，是「要不要
    // 開始」——先把資料卡看完，按下去才進對話框（見 _openChat）。
    if (showStartCta) {
      return _BarContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.isAssistedLearningMode) ...[
              _TemperatureMeter(state: state),
              const SizedBox(height: 12),
            ],
            Text(
              quotaLabel,
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
            const SizedBox(height: 8),
            BrandPrimaryButton(
              key: const ValueKey('practice-start-chat-cta'),
              label: '開始和她聊',
              // 句尾的 🤓 走 Tabler icon（2026-08-17 Eric 拍板：不用 iOS emoji），
              // 位置維持在文案後面。
              trailingIcon: TablerIcons.mood_nerd,
              onPressed: canSend ? onStartChat : null,
            ),
          ],
        ),
      );
    }

    void useHintReply(PracticeHintReply reply) {
      inputController.text = reply.text;
      inputController.selection = TextSelection.collapsed(
        offset: inputController.text.length,
      );
      onHintApplied(reply);
      inputFocusNode.requestFocus();
    }

    return _BarContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Phase 4.5c 刀 3／Phase 5 WP5：她說「先忙了」或只回已讀之後，玩家
          // 再丟也拿不到回應——沒有這一段他不知道這場其實該收了。提示＋一顆
          // 「看教練拆解」導向檢討；輸入框仍然可以打字送出（不鎖、不自動結束）。
          if (state.partnerCheckedOut) ...[
            Text(
              '她先去忙了，這場可以結束練習看拆解',
              key: const ValueKey('practice-partner-checked-out'),
              style: AppTypography.caption.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
            const SizedBox(height: 8),
            BrandPrimaryButton(
              key: const ValueKey('practice-partner-checked-out-debrief'),
              label: '看教練拆解',
              onPressed: state.canDebrief ? onEndPractice : null,
            ),
            const SizedBox(height: 8),
          ],
          if (state.isAssistedLearningMode) ...[
            _TemperatureMeter(state: state),
            const SizedBox(height: 8),
          ],
          if (state.isAssistedLearningMode && state.messages.isNotEmpty) ...[
            _HintCoachPanel(
              state: state,
              onRequestHint: onRequestHint,
              onUseReply: useHintReply,
              onEndPractice: onEndPractice,
            ),
            const SizedBox(height: 8),
          ],
          // iPhone 鍵盤沒有收起鍵：聚焦時給明確退出動作。資料入口一律在 header
          // 的 compact identity 列（點開 profile sheet），這裡不重複。
          ListenableBuilder(
            listenable: inputFocusNode,
            builder: (context, _) {
              if (!inputFocusNode.hasFocus) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('practice-dismiss-keyboard'),
                      onPressed: () => inputFocusNode.unfocus(),
                      icon: const Icon(Icons.keyboard_hide_outlined, size: 15),
                      label: const Text('收起鍵盤'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.onBackgroundSecondary,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  quotaLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (state.canDebrief)
                TextButton.icon(
                  onPressed: onEndPractice,
                  icon: const Icon(Icons.flag_outlined, size: 16),
                  label: const Text('結束練習'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ctaStart,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                // 聚焦時輕微抬升＋品牌橘光暈，跟送出鈕呼應（默認只留淡陰影）。
                child: ListenableBuilder(
                  listenable: inputFocusNode,
                  builder: (context, child) => AnimatedContainer(
                    duration: AppMotion.state,
                    curve: AppMotion.easeOut,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: inputFocusNode.hasFocus
                          ? [
                              BoxShadow(
                                color:
                                    AppColors.ctaStart.withValues(alpha: 0.22),
                                blurRadius: 14,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: child,
                  ),
                  child: TextField(
                    controller: inputController,
                    focusNode: inputFocusNode,
                    enabled: canSend,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 240,
                    // Return 鍵＝換行，不是送出（Eric 2026-08-12）：自己打字時也要能
                    // 連發短訊，換行在畫面上就拆成多顆泡、一秒一顆（見 _Bubble）。
                    // 送出一律走右邊的 _SendButton，跟 LINE／WhatsApp 的手感一致。
                    textInputAction: TextInputAction.newline,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onBackgroundPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          state.messages.isEmpty ? '傳出你的第一句開場白…' : '輸入訊息…',
                      counterText: '',
                      hintStyle: AppTypography.bodyMedium.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.85),
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.12),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                        borderSide: BorderSide(
                          color: AppColors.ctaStart,
                          width: 1.4,
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 空字串灰階、有字才亮橘：用狀態變化引導「打字→送出」。
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: inputController,
                builder: (context, value, _) => _SendButton(
                  enabled: canSend && value.text.trim().isNotEmpty,
                  onTap: onSend,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemperatureMeter extends StatelessWidget {
  const _TemperatureMeter({required this.state});

  final PracticeChatState state;

  @override
  Widget build(BuildContext context) {
    final score = (state.temperatureScore ??
            initialPracticeTemperatureScore(state.difficulty))
        .clamp(0, 100)
        .toInt();
    // 顏色由 server 回的 band 驅動；band 缺席（還原/舊快照）才用 score 鏡像兜底。
    final color = practiceTemperatureColor(
      score: score,
      band: state.temperatureBand,
    );
    final delta = state.lastTemperatureDelta;
    final signalText = _temperatureSignalText(delta);
    final stageLabel =
        state.relationshipStageLabel ?? kInitialPracticeRelationshipStageLabel;

    return Container(
      key: const ValueKey('practice-temperature-meter'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brandSurface2.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.thermostat, size: 17, color: color),
              const SizedBox(width: 6),
              Text(
                '升溫 $score',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  stageLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (delta != null)
                Text(
                  delta == 0 ? '±0' : '${delta > 0 ? '+' : ''}$delta',
                  style: AppTypography.caption.copyWith(
                    color: delta >= 0 ? AppColors.success : AppColors.info,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: score / 100,
              color: color,
              backgroundColor:
                  AppColors.onBackgroundSecondary.withValues(alpha: 0.14),
            ),
          ),
          if (signalText != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.insights, size: 14, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    signalText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String? _temperatureSignalText(int? delta) {
  if (delta == null) return null;
  if (delta > 0) return '這輪有升溫';
  if (delta < 0) return '這輪降溫，先放慢';
  return '這輪持平';
}

class _HintCoachPanel extends StatefulWidget {
  const _HintCoachPanel({
    required this.state,
    required this.onRequestHint,
    required this.onUseReply,
    required this.onEndPractice,
  });

  final PracticeChatState state;
  final VoidCallback onRequestHint;
  final ValueChanged<PracticeHintReply> onUseReply;

  /// 「沒有可貼句」狀態的出口：這局的學習價值在拆盤，別讓使用者困在死局
  /// 重複燒提示。
  final VoidCallback onEndPractice;

  @override
  State<_HintCoachPanel> createState() => _HintCoachPanelState();
}

class _HintCoachPanelState extends State<_HintCoachPanel> {
  late bool _expanded;

  /// 提示等待分段進度（套 analysis_screen 的 stage label＋經過秒數模式）。
  /// 純時間分段，不假造伺服器進度；timer 只在 isHintLoading 期間存活，
  /// 載入結束／widget dispose 必取消（鐵則：pumpAndSettle 必收斂）。
  Timer? _hintWaitTimer;
  int _hintWaitElapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _expanded = widget.state.hintReplies.isNotEmpty ||
        (widget.state.hintNoPasteableReason?.trim().isNotEmpty ?? false);
    _syncHintWaitTimer();
  }

  @override
  void didUpdateWidget(covariant _HintCoachPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final receivedNewHint = widget.state.hintUsedCount !=
            oldWidget.state.hintUsedCount ||
        widget.state.hintReplies.length != oldWidget.state.hintReplies.length;
    final reason = widget.state.hintNoPasteableReason?.trim() ?? '';
    final receivedNewNoPasteable = reason.isNotEmpty &&
        reason != (oldWidget.state.hintNoPasteableReason?.trim() ?? '');
    // 「沒有可貼句」是判定不是失敗——折疊起來只剩「0 則提示」會被誤讀成
    // 產生失敗（2026-08-08 Eric 實測），所以跟收到可貼句一樣自動展開。
    if ((receivedNewHint && widget.state.hintReplies.isNotEmpty) ||
        receivedNewNoPasteable) {
      _expanded = true;
    }
    _syncHintWaitTimer();
  }

  /// 同一輪已判定「沒有可貼句」還再按提示：答案不會變但照扣額度，先確認。
  /// 她一回新訊息 reason 就會清掉，確認框只擋原地重按。
  Future<void> _requestHintWithNoPasteableGuard() async {
    final reason = widget.state.hintNoPasteableReason?.trim() ?? '';
    if (reason.isEmpty) {
      widget.onRequestHint();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('再要一次提示？'),
        content: const Text(
          '這輪已判定沒有可以送出的句子，教練建議先收手。\n'
          '再按一次仍會扣 1 則提示額度，而且判定大概率不會變。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('practice-hint-recharge-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('仍要提示'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.onRequestHint();
    }
  }

  @override
  void dispose() {
    _hintWaitTimer?.cancel();
    super.dispose();
  }

  void _syncHintWaitTimer() {
    final loading = widget.state.isHintLoading;
    if (loading && _hintWaitTimer == null) {
      // 這裡不 setState：initState 不可 setState，didUpdateWidget 本來就有
      // 一次 rebuild 要來。
      _hintWaitElapsedSeconds = 0;
      _hintWaitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _hintWaitElapsedSeconds++);
      });
    } else if (!loading && _hintWaitTimer != null) {
      _hintWaitTimer!.cancel();
      _hintWaitTimer = null;
      _hintWaitElapsedSeconds = 0;
    }
  }

  /// 0-8s → 8-20s → 20s+ 三段文案；對齊單發管線的實際階段順序
  /// （讀 transcript → 單發生成 → 機械檢查/補發），但只按時間切換。
  String get _hintWaitStageLabel {
    if (_hintWaitElapsedSeconds < 8) return '教練正在讀你們最後幾句…';
    if (_hintWaitElapsedSeconds < 20) return '正在想兩種回法…';
    return '快好了，正在做最後檢查…';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final hintUsedCount =
        state.hintUsedCount.clamp(0, kMaxPracticeHintsPerRound).toInt();
    final isHintLimitReached =
        state.hintLimitReached || hintUsedCount >= kMaxPracticeHintsPerRound;
    final canRequest = state.canRequestHint && !isHintLimitReached;
    final noPasteableReason = state.hintNoPasteableReason?.trim();
    final hasNoPasteableNotice =
        noPasteableReason != null && noPasteableReason.isNotEmpty;
    final hasHint = state.hintReplies.isNotEmpty ||
        hasNoPasteableNotice ||
        (state.hintCoaching != null && state.hintCoaching!.trim().isNotEmpty);
    final isGameMode = state.learningMode == PracticeLearningMode.game;
    final hintTitle = isGameMode ? 'Game Hint' : 'Hint';
    final hintActionLabel = isGameMode ? '攻略 1 則' : '提示 1 則';
    final hintMoreLabel = isGameMode ? '看完整攻略' : '看完整心法';
    return Container(
      key: const ValueKey('practice-hint-panel'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.brandSurface2.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primaryLight.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // WP4：顯示剩餘顆數，不是已用幾顆（剩餘＝上限－已用，零 server 改動）。
                  '$hintTitle 還剩 ${kMaxPracticeHintsPerRound - hintUsedCount} 顆',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('practice-hint-button'),
                onPressed: canRequest ? _requestHintWithNoPasteableGuard : null,
                icon: state.isHintLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lightbulb_outline, size: 16),
                label: Text(
                  isHintLimitReached
                      ? '本輪已用完'
                      : state.hintFailed
                          ? '再試一次'
                          : hintActionLabel,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (hasHint) ...[
                const SizedBox(width: 2),
                IconButton(
                  key: const ValueKey('practice-hint-toggle-button'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                  ),
                  color: AppColors.onBackgroundSecondary,
                  tooltip: _expanded ? '收合提示' : '展開提示',
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ],
          ),
          if (state.isHintLoading) ...[
            const SizedBox(height: 4),
            Row(
              key: const ValueKey('practice-hint-wait-progress'),
              children: [
                Icon(
                  Icons.hourglass_top,
                  size: 14,
                  color: AppColors.primaryLight,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$_hintWaitStageLabel（$_hintWaitElapsedSeconds 秒）',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (isHintLimitReached) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: AppColors.onBackgroundSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '本輪提示已用完，先用自己的話試著回覆。',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (state.hintFailed && !isHintLimitReached) ...[
            const SizedBox(height: 4),
            Row(
              key: const ValueKey('practice-hint-retry-message'),
              children: [
                Icon(
                  Icons.refresh,
                  size: 14,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$hintTitle 暫時沒有成功產生，請再試一次。',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (hasHint && !_expanded) ...[
            const SizedBox(height: 4),
            Row(
              key: const ValueKey('practice-hint-collapsed-summary'),
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 14,
                  color: AppColors.primaryLight,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hasNoPasteableNotice
                        ? '這輪沒有可以送出的訊息'
                        : '已產生 ${state.hintReplies.length} 則提示',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_expanded && state.hintReplies.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (var i = 0; i < state.hintReplies.length; i++) ...[
              _HintReplyButton(
                key: ValueKey('practice-hint-reply-$i'),
                reply: state.hintReplies[i],
                onTap: () {
                  setState(() => _expanded = false);
                  widget.onUseReply(state.hintReplies[i]);
                },
              ),
              if (i != state.hintReplies.length - 1) const SizedBox(height: 6),
            ],
          ],
          // 她已封鎖／要求停止聯絡：沒有可貼句是合法結果，不是失敗。刻意用
          // 小字並與可貼句按鈕明確區隔——它是說明不是話術，不該被複製貼出去
          //（Eric 2026-08-05 指示）。
          if (_expanded && hasNoPasteableNotice) ...[
            const SizedBox(height: 8),
            Row(
              key: const ValueKey('practice-hint-no-pasteable'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.block_outlined,
                  size: 14,
                  color:
                      AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    noPasteableReason,
                    style: AppTypography.caption.copyWith(
                      fontSize: 12,
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.85),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            // 死局的正確出口：這局的學習價值在拆盤（結束卡會指出關鍵轉折與
            // 下次第一句），別讓使用者原地重按提示。
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('practice-hint-end-practice'),
                onPressed: widget.onEndPractice,
                icon: const Icon(Icons.flag_outlined, size: 14),
                label: const Text('結束練習，看拆盤'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
          if (_expanded &&
              state.hintCoaching != null &&
              state.hintCoaching!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.psychology_alt_outlined,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 心法只留第一句（2026-08-11 Eric 拍板）：prompt 契約已
                      // 要求 coaching 第一句就是「這輪戰術」，所以取到第一個
                      // 句號即可，比硬截兩行更完整可讀；其餘進「看完整心法」。
                      Text(
                        _coachingHeadline(state.hintCoaching!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onBackgroundSecondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 2),
                      TextButton(
                        key: const ValueKey('practice-hint-coaching-more'),
                        onPressed: () => _showCoachingSheet(
                          context,
                          state.hintCoaching!.trim(),
                          isGameMode: isGameMode,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryLight,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(hintMoreLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showCoachingSheet(
    BuildContext context,
    String coaching, {
    required bool isGameMode,
  }) {
    showAppSheet<void>(
      context: context,
      backgroundColor: AppColors.brandInk,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          key: const ValueKey('practice-hint-coaching-sheet'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isGameMode ? 'Game 攻略' : '回覆心法',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  coaching,
                  key: const ValueKey('practice-hint-coaching-sheet-text'),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    height: 1.55,
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

class _HintReplyButton extends StatelessWidget {
  const _HintReplyButton({
    super.key,
    required this.reply,
    required this.onTap,
  });

  final PracticeHintReply reply;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = reply.type == PracticeHintReplyType.warmUp
        ? AppColors.ctaStart
        : AppColors.info;
    return Material(
      color: accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_fix_high, size: 14, color: accent),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      reply.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Text(
                      '套用',
                      style: AppTypography.caption.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 分則預覽：Hint 可貼句可能是 2-4 則短訊（換行分則）。原本
              // maxLines: 2 + ellipsis 會把第三則吃掉，使用者看不到全文就
              // 不敢按套用，等於廢掉分則功能。改成一則一小格全部顯示——
              // 每則只有 4-15 字，三則加起來比舊版單則還短，卡片不會變高。
              for (final part in _splitBubbles(reply.text))
                Container(
                  margin: const EdgeInsets.only(bottom: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    part,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebriefFailedActionsBar extends StatelessWidget {
  const _DebriefFailedActionsBar({
    required this.retryable,
    required this.onRetry,
    required this.onFinish,
  });

  final bool retryable;
  final VoidCallback onRetry;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return _BarContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            retryable ? '拆解卡暫時沒有產生' : '這場練習已結束',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (retryable)
            Row(
              children: [
                Expanded(
                  child: BrandPrimaryButton(
                    label: '再試一次',
                    onPressed: onRetry,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BrandSecondaryButton(
                    label: '完成',
                    onPressed: onFinish,
                  ),
                ),
              ],
            )
          else
            BrandPrimaryButton(
              label: '完成',
              onPressed: onFinish,
            ),
        ],
      ),
    );
  }
}

// ── 拆解後動作列：續玩同一位（主）＋ 去圖鑑換人／完成（次）─────────────
// 續聊不再以 3 輪封頂；每次續聊開新 billing session，但保留同一位與前文脈絡。
// 換人＝導回角色圖鑑翻牌（Task 5：翻牌觸發點唯一收斂圖鑑）。
class _DebriefActionsBar extends StatelessWidget {
  const _DebriefActionsBar({
    required this.state,
    required this.onContinueSamePartner,
    required this.onNewPartner,
    required this.onFinish,
  });

  final PracticeChatState state;
  final VoidCallback onContinueSamePartner;
  final VoidCallback onNewPartner;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return _BarContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandPrimaryButton(
            // 目前 client 只有 persona 型別標籤、無女孩名字（name batch 未接），
            // 用「續聊同一位」避免「和慢熱上班族續聊」這種怪句；name 接上再改。
            label: '續聊同一位',
            onPressed: onContinueSamePartner,
          ),
          const SizedBox(height: 6),
          Text(
            '再扣 1 則，最多 20 則 AI 回覆（她會記得前面的對話）',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: BrandSecondaryButton(
                  label: '去圖鑑換人',
                  onPressed: onNewPartner,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BrandSecondaryButton(
                  label: '完成',
                  onPressed: onFinish,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarContainer extends StatelessWidget {
  const _BarContainer({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: child,
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('practice-send-button'),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [AppColors.ctaStart, AppColors.ctaEnd],
                )
              : null,
          color: enabled ? null : AppColors.brandSurface2,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.arrow_upward,
          color: enabled
              ? AppColors.onBackgroundPrimary
              : AppColors.onBackgroundSecondary.withValues(alpha: 0.5),
          size: 22,
        ),
      ),
    );
  }
}

// ── 最近練習：未拆解可續聊，已拆解可回顧 ─────────────────────────────
class _RecentSessionsSheet extends StatefulWidget {
  const _RecentSessionsSheet({
    required this.sessions,
    required this.onResume,
    required this.onDelete,
  });

  final List<PracticeSession> sessions;
  final ValueChanged<PracticeSession> onResume;
  final Future<void> Function(PracticeSession session) onDelete;

  @override
  State<_RecentSessionsSheet> createState() => _RecentSessionsSheetState();
}

class _RecentSessionsSheetState extends State<_RecentSessionsSheet> {
  late List<PracticeSession> _sessions;

  /// 批次刪除多選模式（沿用分析紀錄 sheet 的同一套互動）。
  bool _selecting = false;
  final Set<String> _selectedIds = <String>{};
  bool _isDeleting = false;

  bool get _allSelected =>
      _sessions.isNotEmpty &&
      _sessions.every((s) => _selectedIds.contains(s.id));

  @override
  void initState() {
    super.initState();
    _sessions = [...widget.sessions];
  }

  Future<void> _delete(PracticeSession session) async {
    await widget.onDelete(session);
    if (!mounted) return;
    setState(() {
      _sessions.removeWhere((s) => s.id == session.id);
    });
  }

  void _enterSelection([String? firstId]) {
    if (_sessions.isEmpty || _isDeleting) return;
    AppHaptics.light();
    setState(() {
      _selecting = true;
      if (firstId != null) _selectedIds.add(firstId);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(PracticeSession session) {
    if (_isDeleting) return;
    AppHaptics.tap();
    setState(() {
      if (!_selectedIds.add(session.id)) _selectedIds.remove(session.id);
    });
  }

  void _toggleSelectAll() {
    if (_isDeleting) return;
    AppHaptics.tap();
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_sessions.map((s) => s.id));
      }
    });
  }

  /// 逐場走呼叫端 onDelete（沿用單場刪的安全語義）；中途失敗停在原地，
  /// 已刪的不回滾（既成事實，跟分析紀錄批次刪同規則）。
  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty || _isDeleting) return;
    final targets =
        _sessions.where((s) => _selectedIds.contains(s.id)).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _BatchDeleteSessionsConfirmDialog(count: targets.length),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    var deleted = 0;
    var failed = false;
    for (final session in targets) {
      try {
        await widget.onDelete(session);
      } catch (_) {
        failed = true;
        break;
      }
      deleted += 1;
      if (!mounted) return;
      setState(() {
        _sessions.removeWhere((s) => s.id == session.id);
        _selectedIds.remove(session.id);
      });
    }
    if (!mounted) return;
    setState(() {
      _isDeleting = false;
      if (!failed) {
        _selecting = false;
        _selectedIds.clear();
      }
    });
    if (failed) {
      AppHaptics.failure();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刪除中斷：已刪 $deleted 場，其餘保留，請再試一次')),
      );
    } else {
      AppHaptics.medium();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已刪除 $deleted 場練習')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _selecting ? '已選 ${_selectedIds.length} 場' : '最近練習',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_selecting) ...[
                _SheetLinkButton(
                  key: const ValueKey('practice-session-select-all'),
                  label: _allSelected ? '取消全選' : '全選',
                  onTap: _isDeleting ? null : _toggleSelectAll,
                ),
                _SheetLinkButton(
                  key: const ValueKey('practice-session-select-cancel'),
                  label: '取消',
                  onTap: _isDeleting ? null : _exitSelection,
                ),
              ] else if (_sessions.isNotEmpty)
                _SheetLinkButton(
                  key: const ValueKey('practice-session-select'),
                  label: '選取',
                  onTap: _enterSelection,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '只保留最近 5 場，存在這支手機上。',
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (_sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '還沒有練習紀錄',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
              ),
            )
          else
            ..._sessions.map(
              (s) => _SessionRow(
                session: s,
                onResume: widget.onResume,
                onDelete: _delete,
                selecting: _selecting,
                selected: _selectedIds.contains(s.id),
                onToggleSelect: () => _toggleSelected(s),
                onLongPress: !_selecting && !_isDeleting
                    ? () => _enterSelection(s.id)
                    : null,
              ),
            ),
          if (_selecting) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                key: const ValueKey('practice-session-batch-delete'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _selectedIds.isEmpty || _isDeleting
                    ? null
                    : AppHaptics.onPress(() => _deleteSelected()),
                child: _isDeleting
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '刪除中…',
                            style: AppTypography.bodyLarge.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        '刪除（${_selectedIds.length}）',
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// sheet 標題列右側的小文字鈕（選取／全選／取消），比照分析紀錄 sheet。
class _SheetLinkButton extends StatelessWidget {
  const _SheetLinkButton({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: AppColors.ctaStart,
      ),
      child: Text(
        label,
        style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 批次刪除確認框：講清楚幾場、不可復原（比照單場刪的語氣）。
class _BatchDeleteSessionsConfirmDialog extends StatelessWidget {
  const _BatchDeleteSessionsConfirmDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return BrandAlertDialog(
      title: Text('刪除 $count 場練習？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('只會刪除這支手機上的練習紀錄，不會退回已扣額度。'),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(TablerIcons.alert_triangle,
                  size: 15, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 5),
              Text(
                '此操作不可復原',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          key: const ValueKey('practice-session-batch-delete-confirm'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: AppHaptics.onPress(() => Navigator.of(context).pop(true)),
          child: const Text('確認刪除'),
        ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.onResume,
    required this.onDelete,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelect,
    this.onLongPress,
  });

  final PracticeSession session;
  final ValueChanged<PracticeSession> onResume;
  final Future<void> Function(PracticeSession session) onDelete;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onLongPress;

  String get _preview {
    final firstUser = session.messages
        .where((m) => m.isFromMe)
        .map((m) => m.text)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);
    return firstUser ?? '（無內容）';
  }

  String get _dateLabel {
    final d = session.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.month}/${d.day} ${two(d.hour)}:${two(d.minute)}';
  }

  bool get _canResume => session.isOpen;

  String get _statusLabel {
    if (session.hasDebrief) return '已拆解';
    if (session.closed) return '已結束';
    if (session.aiReplyCount >= kMaxPracticeAiReplies) return '待拆解';
    return '可續聊';
  }

  Color get _statusColor {
    if (session.hasDebrief) return AppColors.success;
    if (session.closed) return AppColors.onBackgroundSecondary;
    if (session.aiReplyCount >= kMaxPracticeAiReplies) return AppColors.warning;
    return AppColors.info;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      // BrandAlertDialog 自帶白玻璃底＋深色玻璃字；之前手刻 AlertDialog 用了
      // 深色主題的近白文字，白底白字整塊反白刺眼（2026-08-18 dogfood）。
      builder: (dialogContext) => BrandAlertDialog(
        title: const Text('刪除這場練習？'),
        content: const Text('只會刪除這支手機上的練習紀錄，不會退回已扣額度。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: AppHaptics.onPress(
              () => Navigator.of(dialogContext).pop(true),
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await onDelete(session);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BrandSurfaceCard(
        elevated: false,
        padding: const EdgeInsets.all(16),
        borderColor:
            selected ? AppColors.ctaStart.withValues(alpha: 0.64) : null,
        onLongPress: onLongPress,
        onTap: selecting
            ? onToggleSelect
            : () {
                Navigator.of(context).pop();
                if (_canResume) {
                  onResume(session);
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _SessionReviewScreen(session: session),
                  ),
                );
              },
        child: Row(
          children: [
            if (selecting) ...[
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                size: 22,
                color: selected
                    ? AppColors.ctaStart
                    : Colors.white.withValues(alpha: 0.40),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dateLabel,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _statusLabel,
                style: AppTypography.caption.copyWith(
                  color: _statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!selecting) ...[
              const SizedBox(width: 4),
              IconButton(
                key: ValueKey('delete-practice-${session.id}'),
                tooltip: '刪除練習',
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.onBackgroundSecondary,
                onPressed: () => _confirmDelete(context),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.onBackgroundSecondary,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 單場 read-only 回顧（逐字稿 + 拆解卡）。
class _SessionReviewScreen extends StatelessWidget {
  const _SessionReviewScreen({required this.session});
  final PracticeSession session;

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      title: '練習回顧',
      body: _PracticeChatWorkspaceFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          children: [
            for (final m in session.messages) _Bubble(message: m),
            if (session.hasRestorableDebrief) ...[
              const SizedBox(height: 12),
              PracticeDebriefCard(
                summary: session.debriefSummary ?? '',
                strengths: session.debriefStrengths,
                watchouts: session.debriefWatchouts,
                suggestedLine: session.debriefSuggestedLine ?? '',
                vibe: session.debriefVibe ?? '中性',
                dateChance: session.debriefDateChance,
                dateChanceReason: session.debriefDateChanceReason,
                nextInviteMove: session.debriefNextInviteMove,
                gameBreakdownPhaseReached: session.debriefGamePhaseReached,
                gameBreakdownMissedVariable: session.debriefGameMissedVariable,
                gameBreakdownFailureState: session.debriefGameFailureState,
                gameBreakdownNextFirstLine: session.debriefGameNextFirstLine,
                gameBreakdownInviteDirection:
                    session.debriefGameInviteDirection,
              ),
            ] else if (session.hasDebrief) ...[
              const SizedBox(height: 12),
              const _RetiredDebriefNotice(),
            ],
          ],
        ),
      ),
    );
  }
}

class _RetiredDebriefNotice extends StatelessWidget {
  const _RetiredDebriefNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('practice-retired-debrief-notice'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandSurface2.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 19,
            color: AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '舊版拆解已停用，請開始新一場取得新版。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundPrimary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
