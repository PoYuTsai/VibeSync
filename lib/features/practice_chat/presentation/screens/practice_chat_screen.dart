import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/practice_chat_providers.dart';
import '../../domain/entities/practice_message.dart';
import '../../domain/entities/practice_session.dart';
import '../widgets/practice_debrief_card.dart';

/// AI 實戰練習室主畫面：點入直接進聊天（不選目標）。
/// 使用者先發訊息，AI 扮演模擬對象回覆；最多 10 則 AI 回覆；
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
    );
    if (!consented || !mounted) return;
    _controller.clear();
    ref.read(practiceChatControllerProvider.notifier).sendMessage(text);
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
          Expanded(
            child: state.messages.isEmpty
                ? const _EmptyState()
                : ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
          if (state.errorMessage != null)
            _ErrorBanner(
              message: state.errorMessage!,
              quotaExceeded: state.quotaExceeded,
              onUpgrade: () => context.push('/paywall'),
              onDismiss: () =>
                  ref.read(practiceChatControllerProvider.notifier).clearError(),
            ),
          _BottomBar(
            state: state,
            inputController: _controller,
            isDebriefing: state.isDebriefing,
            onSend: _send,
            onEndPractice: () =>
                ref.read(practiceChatControllerProvider.notifier).endPractice(),
            onFinish: () => context.pop(),
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
      builder: (_) => _RecentSessionsSheet(sessions: sessions),
    );
  }
}

// ── 空狀態：引導使用者先發第一句 ───────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandIconBadge(
              icon: Icons.forum_outlined,
              size: 56,
              iconSize: 30,
            ),
            const SizedBox(height: 18),
            Text(
              '直接開聊吧',
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '對方是個有自己個性的模擬對象，不是教練。\n傳第一句出去，看看她怎麼回，練你的真實反應。',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.5,
              ),
            ),
          ],
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
    required this.quotaExceeded,
    required this.onUpgrade,
    required this.onDismiss,
  });

  final String message;
  final bool quotaExceeded;
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
          if (quotaExceeded)
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
  });

  final PracticeChatState state;
  final TextEditingController inputController;
  final bool isDebriefing;
  final VoidCallback onSend;
  final VoidCallback onEndPractice;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    // 已看到拆解卡 → 收尾。
    if (state.debrief != null) {
      return _BarContainer(
        child: BrandPrimaryButton(label: '完成', onPressed: onFinish),
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

    // 已達 10 則上限 → 引導看拆解。
    if (state.sessionComplete) {
      return _BarContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '這場練習已達 10 則回覆',
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
    return _BarContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '還能聊 ${state.remainingReplies} 則',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
              const Spacer(),
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

// ── 最近練習（read-only 歷史） ─────────────────────────────────────────
class _RecentSessionsSheet extends StatelessWidget {
  const _RecentSessionsSheet({required this.sessions});
  final List<PracticeSession> sessions;

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
          if (sessions.isEmpty)
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
            ...sessions.map((s) => _SessionRow(session: s)),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});
  final PracticeSession session;

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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BrandSurfaceCard(
        elevated: false,
        padding: const EdgeInsets.all(14),
        onTap: () {
          Navigator.of(context).pop();
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
            if (session.hasDebrief)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '已拆解',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              color: AppColors.onBackgroundSecondary,
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
    );
  }
}
