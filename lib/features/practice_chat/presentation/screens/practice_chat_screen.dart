import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../data/providers/practice_chat_providers.dart';
import '../../data/repositories/practice_session_repository.dart';
import '../../domain/entities/practice_message.dart';
import '../../domain/entities/practice_profile.dart';
import '../../domain/entities/practice_session.dart';
import '../widgets/practice_debrief_card.dart';
import '../widgets/practice_girl_photo.dart';
import '../widgets/practice_profile_sheet.dart';

/// AI 實戰練習室主畫面：點入直接進聊天（不選目標）。
/// 使用者先發訊息，AI 扮演模擬對象回覆；最多 20 則 AI 回覆；
/// 結束練習產一張教練拆解卡。
class PracticeChatScreen extends ConsumerStatefulWidget {
  const PracticeChatScreen({super.key});

  @override
  ConsumerState<PracticeChatScreen> createState() => _PracticeChatScreenState();
}

class _PracticeChatScreenState extends ConsumerState<PracticeChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
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
    _controller.clear();
    ref.read(practiceChatControllerProvider.notifier).sendMessage(text);
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
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(practiceChatControllerProvider);

    // 訊息變動或開始等待 → 捲到底。
    ref.listen(practiceChatControllerProvider, (prev, next) {
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
    });

    // 尚未翻牌（locked / drawing / error）：不顯示任何對象，只給翻牌入口。
    if (!state.isRevealed) {
      return BrandScaffold(
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
    }

    return BrandScaffold(
      title: 'AI 實戰練習室',
      actions: [
        IconButton(
          icon: const Icon(Icons.history),
          tooltip: '最近練習',
          onPressed: () => _openHistory(context),
        ),
      ],
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          // 開場前：換一位＋難度控制（深色 scaffold 底，沿用原樣式）。
          // 開聊後：compact identity header（小圓照片＋名字/職業/難度）。
          if (state.messages.isEmpty)
            _PracticeOpeningControls(state: state)
          else
            _PracticeProfileBar(state: state),
          Expanded(
            child: _PracticeChatWorkspaceFrame(
              child: state.messages.isEmpty
                  ? _PracticeProfileHero(state: state)
                  : ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
                      children: [
                        for (final m in state.messages) _Bubble(message: m),
                        if (state.isSending) const _ThinkingBubble(),
                        if (state.debrief != null) ...[
                          const SizedBox(height: 8),
                          PracticeDebriefCard(
                            summary: state.debrief!.summary,
                            strengths: state.debrief!.strengths,
                            watchouts: state.debrief!.watchouts,
                            suggestedLine: state.debrief!.suggestedLine,
                            vibe: state.debrief!.vibe,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          if (state.errorMessage != null)
            _ErrorBanner(
              message: state.errorMessage!,
              showUpgrade: state.quotaExceeded || state.upgradeRequired,
              onUpgrade: () => context.push('/paywall'),
              onDismiss: () => ref
                  .read(practiceChatControllerProvider.notifier)
                  .clearError(),
            ),
          _BottomBar(
            state: state,
            inputController: _controller,
            isDebriefing: state.isDebriefing,
            onSend: _send,
            onEndPractice: () =>
                ref.read(practiceChatControllerProvider.notifier).endPractice(),
            onFinish: () => context.pop(),
            onContinueSamePartner: _continueSamePartner,
            onNewPartner: () => ref
                .read(practiceChatControllerProvider.notifier)
                .startNewPartner(),
          ),
        ],
      ),
    );
  }

  void _openHistory(BuildContext context) {
    final sessions = ref.read(recentPracticeSessionsProvider);
    showModalBottomSheet<void>(
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
    final drawing = state.isDrawing;
    return Center(
      child: SingleChildScrollView(
        key: const ValueKey('practice-locked-entry'),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 52,
              color: AppColors.ctaStart,
            ),
            const SizedBox(height: 20),
            Text(
              '每日登入就送新女孩',
              textAlign: TextAlign.center,
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '翻開今日對象，開始一場真實聊天練習。',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('practice-draw-cta'),
                onPressed: drawing
                    ? null
                    : () => ref
                        .read(practiceChatControllerProvider.notifier)
                        .drawNewPracticeGirl(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ctaStart,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: drawing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('翻開今日對象'),
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
              const SizedBox(height: 10),
              OutlinedButton(
                key: const ValueKey('practice-draw-upgrade'),
                onPressed: () => context.push('/paywall'),
                child: const Text('升級解鎖'),
              ),
            ] else if (state.drawQuotaExceeded) ...[
              const SizedBox(height: 16),
              Text(
                state.errorMessage ?? '額度已用完，明天中午會重置。',
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

// ── 開場前控制列：換一位＋難度 chips（深色 scaffold 底，沿用原樣式）──
class _PracticeOpeningControls extends ConsumerWidget {
  const _PracticeOpeningControls({required this.state});

  final PracticeChatState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '為你抽了一位，先看看再開練',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => ref
                    .read(practiceChatControllerProvider.notifier)
                    .regeneratePersona(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ctaStart,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('換一位'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _DifficultyChips(state: state),
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
        borderRadius: BorderRadius.circular(12),
        onTap: () => showPracticeProfileSheet(context, girl),
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
              const SizedBox(width: 10),
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

  static const _options = <(PracticeDifficultyPreference, String)>[
    (PracticeDifficultyPreference.easy, '輕鬆'),
    (PracticeDifficultyPreference.normal, '一般'),
    (PracticeDifficultyPreference.challenge, '挑戰'),
    (PracticeDifficultyPreference.random, '隨機'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final (pref, label) in _options)
          _DifficultyChip(
            label: label,
            selected: state.difficultyPreference == pref,
            onTap: () => ref
                .read(practiceChatControllerProvider.notifier)
                .setDifficultyPreference(pref),
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
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.ctaStart.withValues(alpha: 0.18)
              : AppColors.brandSurface2.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.ctaStart.withValues(alpha: 0.7)
                : AppColors.onBackgroundSecondary.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          label,
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
class _PracticeChatWorkspaceFrame extends StatelessWidget {
  const _PracticeChatWorkspaceFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 600 ? 600.0 : constraints.maxWidth;
        final frame = Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _PracticeChatWorkspace(child: child),
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
  const _PracticeChatWorkspace({required this.child});

  static const _radius = BorderRadius.all(Radius.circular(18));

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('practice-chat-workspace'),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: _radius,
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppColors.glassTextPrimary),
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
    return SingleChildScrollView(
      key: const ValueKey('practice-profile-hero'),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      child: Column(
        children: [
          GestureDetector(
            key: const ValueKey('practice-profile-hero-photo'),
            onTap: () => showPracticeGirlFullPhoto(context, girl),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                PracticeGirlPhoto(
                  profile: girl,
                  width: 232,
                  height: 290,
                  borderRadius: BorderRadius.circular(22),
                ),
                const Positioned(
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
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${girl.professionLabel} · ${girl.city}',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [for (final t in tags) _HeroTag(label: t)],
          ),
          const SizedBox(height: 14),
          Text(
            girl.selfIntro,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '對方是個有自己個性的模擬對象，不是教練。\n傳第一句出去，看看她怎麼回，練你的真實反應。',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.glassTextSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '首次 AI 回覆成功才扣 1 則；進來或送出失敗不扣。\n扣完這 1 則，本場最多可聊 20 則 AI 回覆，教練拆解不另扣。',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.glassTextHint,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ctaStart.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: AppColors.ctaStart,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── 訊息泡泡 ──────────────────────────────────────────────────────────
// 沿用對話窗（analyze chat）的泡泡樣式：我說＝橘色系右對齊、她說＝紫色系左對齊。
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final PracticeMessage message;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isFromMe;
    final fillColor = isMe
        ? AppColors.ctaStart.withValues(alpha: 0.14)
        : AppColors.primaryLight.withValues(alpha: 0.18);
    final borderColor = isMe
        ? AppColors.ctaEnd.withValues(alpha: 0.46)
        : AppColors.primaryLight.withValues(alpha: 0.52);
    final speakerColor = isMe ? AppColors.ctaEnd : AppColors.primaryDark;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(14).copyWith(
            bottomRight: isMe ? const Radius.circular(5) : null,
            bottomLeft: !isMe ? const Radius.circular(5) : null,
          ),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isMe ? '我說' : '她說',
              style: AppTypography.bodySmall.copyWith(
                color: speakerColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message.text,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextPrimary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
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
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14).copyWith(
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
        borderRadius: BorderRadius.circular(12),
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
    required this.isDebriefing,
    required this.onSend,
    required this.onEndPractice,
    required this.onFinish,
    required this.onContinueSamePartner,
    required this.onNewPartner,
  });

  final PracticeChatState state;
  final TextEditingController inputController;
  final bool isDebriefing;
  final VoidCallback onSend;
  final VoidCallback onEndPractice;
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
        onRetry: onEndPractice,
        onFinish: onFinish,
      );
    }

    // 拆解中。
    if (isDebriefing) {
      return _BarContainer(
        child: BrandPrimaryButton(
          label: '教練拆解中…',
          isLoading: true,
          onPressed: () {},
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
    return _BarContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                child: TextField(
                  controller: inputController,
                  enabled: canSend,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 240,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => canSend ? onSend() : null,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '輸入訊息…',
                    counterText: '',
                    hintStyle: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: AppColors.brandSurface2.withValues(alpha: 0.7),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(enabled: canSend, onTap: onSend),
            ],
          ),
        ],
      ),
    );
  }
}

class _DebriefFailedActionsBar extends StatelessWidget {
  const _DebriefFailedActionsBar({
    required this.onRetry,
    required this.onFinish,
  });

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
            '拆解卡暫時沒有產生',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: BrandPrimaryButton(
                  label: '再試一次',
                  onPressed: onRetry,
                ),
              ),
              const SizedBox(width: 10),
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

// ── 拆解後動作列：續玩同一位（主）＋ 換一位／完成（次）─────────────────
// roundIndex 已達上限（kMaxPracticeRounds）時隱藏續玩，只留換一位／完成。
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
    final canContinue = state.roundIndex < kMaxPracticeRounds;
    return _BarContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canContinue) ...[
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
          ],
          Row(
            children: [
              Expanded(
                child: BrandSecondaryButton(
                  label: '換一位',
                  onPressed: onNewPartner,
                ),
              ),
              const SizedBox(width: 10),
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最近練習',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
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
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.onResume,
    required this.onDelete,
  });

  final PracticeSession session;
  final ValueChanged<PracticeSession> onResume;
  final Future<void> Function(PracticeSession session) onDelete;

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

  bool get _canResume => !session.hasDebrief;

  String get _statusLabel {
    if (session.hasDebrief) return '已拆解';
    if (session.aiReplyCount >= kMaxPracticeAiReplies) return '待拆解';
    return '可續聊';
  }

  Color get _statusColor {
    if (session.hasDebrief) return AppColors.success;
    if (session.aiReplyCount >= kMaxPracticeAiReplies) return AppColors.warning;
    return AppColors.info;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.glassWhite,
        title: Text(
          '刪除這場練習？',
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.glassTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '只會刪除這支手機上的練習紀錄，不會退回已扣額度。',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.glassTextSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: BrandSurfaceCard(
        elevated: false,
        padding: const EdgeInsets.all(14),
        onTap: () {
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
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
          children: [
            for (final m in session.messages) _Bubble(message: m),
            if (session.hasDebrief) ...[
              const SizedBox(height: 12),
              PracticeDebriefCard(
                summary: session.debriefSummary ?? '',
                strengths: session.debriefStrengths,
                watchouts: session.debriefWatchouts,
                suggestedLine: session.debriefSuggestedLine ?? '',
                vibe: session.debriefVibe ?? '中性',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
