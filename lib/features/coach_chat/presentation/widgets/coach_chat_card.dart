import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/ai_data_sharing_consent.dart';
import '../../../../shared/widgets/coaching_outcome_capture_card.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../coaching_memory/data/providers/coaching_outcome_providers.dart';
import '../../../coaching_memory/domain/entities/coaching_outcome_event.dart';
import '../../data/providers/coach_chat_providers.dart';
import '../../data/services/coach_chat_api_service.dart';
import '../../domain/entities/coach_chat_mode.dart';
import '../../domain/entities/coach_chat_result.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import 'coach_chat_progress_notice.dart';

class CoachChatCard extends ConsumerStatefulWidget {
  final String conversationId;
  final CoachChatAnalysisSnapshot analysisSnapshot;
  final VoidCallback? onQuotaExceeded;
  final VoidCallback? onReturnToAnalysis;
  final int focusRequestToken;

  /// focusRequestToken 變化時一併預填進輸入框的問題（作戰板 nextStep 入口）。
  /// 只進 controller、絕不觸發送出——送出永遠是用戶按鈕行為（quota 安全）。
  final String? prefillText;

  const CoachChatCard({
    super.key,
    required this.conversationId,
    required this.analysisSnapshot,
    this.onQuotaExceeded,
    this.onReturnToAnalysis,
    this.focusRequestToken = 0,
    this.prefillText,
  });

  static bool isQuotaError(Object? error) =>
      error is CoachChatQuotaExceededException;

  static String failureTitleFor(Object error) {
    if (error is CoachChatQuotaExceededException) {
      return error.code == 'MONTHLY_LIMIT_EXCEEDED' ? '本月額度已用完' : '今日額度已用完';
    }
    return '這題教練沒接住';
  }

  static String failureSubtitleFor(Object error) {
    if (error is CoachChatQuotaExceededException) {
      return '這是額度限制，不是教練失敗。升級或等額度重置後再試。';
    }
    return '上一輪回覆已保留，但不是這題的新結果。';
  }

  static String failureMessageFor(Object error) {
    if (error is CoachChatQuotaExceededException) {
      final usage = error.used != null && error.limit != null
          ? '（${error.used}/${error.limit}）'
          : '';
      if (error.code == 'MONTHLY_LIMIT_EXCEEDED') {
        return '本月額度已用完$usage，升級後可以繼續問教練。';
      }
      if (error.code == 'DAILY_LIMIT_EXCEEDED') {
        return '今日額度已用完$usage，可以明天再試，或升級解鎖更多教練建議。';
      }
      return error.message;
    }
    // 「未扣額度」只保證在 4xx 驗證失敗路徑（server 未走到扣費）成立；
    // generation failure 含 client 端 parse 失敗（server 已扣）、未知錯誤
    // 含網路掉包（可能已扣），不得承諾未扣。
    if (error is CoachChatGenerationFailedException) {
      return '教練暫時沒接住，請稍後再試。';
    }
    if (error is CoachChatApiException) {
      // 429＝server per-user 模型限流：顯示 server「稍等再試」文案
      // （限流 gate 在扣費前，未扣額度承諾仍成立，但文案以 server 為準）。
      if (error.status == 429) {
        return error.message;
      }
      return '連線暫時不穩，這次未扣額度，請稍後再試。';
    }
    return '教練暫時沒接住，請稍後再試。';
  }

  static String failureActionLabelFor(Object error) {
    if (error is CoachChatQuotaExceededException) {
      return '查看升級';
    }
    return '重試這題';
  }

  @override
  ConsumerState<CoachChatCard> createState() => _CoachChatCardState();
}

class _CoachChatCardState extends ConsumerState<CoachChatCard> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _lastAskedQuestion;

  static const _chips = <String>[
    '她是什麼意思？',
    '我該怎麼回？',
    '我是不是太急？',
    '這局值不值得？',
    '我該推進嗎？',
  ];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant CoachChatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusRequestToken != oldWidget.focusRequestToken) {
      final prefill = widget.prefillText?.trim();
      if (prefill != null && prefill.isNotEmpty) {
        _fillSuggestedQuestion(prefill);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final provider = coachChatControllerProvider(widget.conversationId);
    final state = ref.watch(provider);
    final progress =
        ref.watch(coachChatProgressProvider(widget.conversationId));
    final history = ref.watch(coachChatHistoryProvider(widget.conversationId));
    final subscription = ref.watch(subscriptionProvider);
    final conversation = ref.watch(conversationProvider(widget.conversationId));
    final timeline = _mergeCoachHistory(
      history: history,
      current: state.valueOrNull,
    );
    final memorySources = _coachMemorySources(
      ref: ref,
      conversation: conversation,
      analysisSnapshot: widget.analysisSnapshot,
    );
    final activeError = state.hasError && _lastAskedQuestion != null;
    final activeErrorObject = state.error;
    final isLoading = state.isLoading;
    final canSubmit = !isLoading;
    final latest = timeline.isEmpty ? null : timeline.first;
    final isClarifying =
        !activeError && (latest?.isClarifyingQuestion ?? false);

    ref.listen<AsyncValue<CoachChatResult?>>(provider, (previous, next) {
      final error = next.error;
      if (error == null) return;
      if (!context.mounted) return;
      if (error is CoachChatQuotaExceededException) {
        widget.onQuotaExceeded?.call();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(CoachChatCard.failureMessageFor(error)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });

    return GlassmorphicContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.forum_outlined,
                  color: AppColors.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '問教練一句',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.glassTextPrimary,
                      ),
                    ),
                    Text(
                      '免費釐清最多 3 次；正式建議扣 1 則，額度用完會提醒升級。',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.glassTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_focusNode.hasFocus)
                TextButton.icon(
                  onPressed: _returnToAnalysis,
                  icon: const Icon(Icons.keyboard_hide_outlined, size: 17),
                  label: const Text('回分析'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.glassTextSecondary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _CoachMemorySourceStrip(sources: memorySources),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _chips
                .map(
                  (chip) => ActionChip(
                    label: Text(chip),
                    onPressed: () => _fillSuggestedQuestion(chip),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.white.withValues(alpha: 0.55),
                    labelStyle: AppTypography.caption.copyWith(
                      color: AppColors.glassTextPrimary,
                    ),
                    side: BorderSide(
                      color: AppColors.glassBorder.withValues(alpha: 0.7),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLength: 240,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onSubmitted: canSubmit ? (_) => _ask() : null,
            inputFormatters: [LengthLimitingTextInputFormatter(240)],
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText:
                  isClarifying ? '補充：你聽到後的感受，或你原本想怎麼回' : '例如：她這句話是真的有興趣嗎？',
              hintStyle: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextHint,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.62),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.4,
                ),
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 48),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_focusNode.hasFocus)
                    IconButton(
                      tooltip: '收起鍵盤',
                      icon: const Icon(Icons.keyboard_hide_outlined),
                      onPressed: _unfocusInput,
                      color: AppColors.glassTextSecondary,
                    ),
                  IconButton(
                    tooltip: isLoading ? '教練思考中' : '送出問題',
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward_rounded),
                    onPressed: canSubmit ? _ask : null,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
          if (isLoading) ...[
            const SizedBox(height: 14),
            CoachChatProgressNotice(
              update: progress,
              question: _lastAskedQuestion,
            ),
          ] else if (activeError) ...[
            const SizedBox(height: 14),
            _CoachFailureNotice(
              title: CoachChatCard.failureTitleFor(activeErrorObject!),
              subtitle: CoachChatCard.failureSubtitleFor(activeErrorObject),
              question: _lastAskedQuestion!,
              message: CoachChatCard.failureMessageFor(activeErrorObject),
              actionLabel:
                  CoachChatCard.failureActionLabelFor(activeErrorObject),
              onRetry: CoachChatCard.isQuotaError(activeErrorObject)
                  ? (widget.onQuotaExceeded ?? _retryLastQuestion)
                  : _retryLastQuestion,
            ),
            if (timeline.isNotEmpty) ...[
              const SizedBox(height: 12),
              _CoachChatThreadView(
                results: timeline,
                dailyRemaining: subscription.dailyRemaining,
                onFollowUp: _focusInputForFollowUp,
                onForceAnswer: _forceAnswer,
              ),
            ],
          ] else if (timeline.isNotEmpty) ...[
            const SizedBox(height: 14),
            _CoachChatThreadView(
              results: timeline,
              dailyRemaining: subscription.dailyRemaining,
              onFollowUp: _focusInputForFollowUp,
              onForceAnswer: _forceAnswer,
            ),
          ],
        ],
      ),
    );
  }

  List<CoachChatResult> _mergeCoachHistory({
    required List<CoachChatResult> history,
    required CoachChatResult? current,
  }) {
    final byId = <String, CoachChatResult>{
      for (final result in history) result.id: result,
    };
    if (current != null) {
      byId[current.id] = current;
    }
    final list = byId.values.toList()
      ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
    return list;
  }

  List<String> _coachMemorySources({
    required WidgetRef ref,
    required Conversation? conversation,
    required CoachChatAnalysisSnapshot analysisSnapshot,
  }) {
    final sources = <String>[];
    final messages = conversation?.messages ?? const [];
    final hasConversation = messages.any(
      (message) => message.content.trim().isNotEmpty,
    );
    if (hasConversation) sources.add('本段對話');

    final summaries = conversation?.summaries;
    if (summaries != null && summaries.isNotEmpty) {
      sources.add('舊摘要');
    }

    if (_hasAnalysisSnapshot(analysisSnapshot)) {
      sources.add('最新分析');
    }

    final partnerId = conversation?.partnerId;
    if (partnerId != null) {
      final flag = ref.watch(dataQualityFlagProvider(partnerId));
      final flagged = flag.isFlagged;
      final styleContext = ref.watch(coachChatStyleContextProvider((
        partnerId: partnerId,
        includePartnerOverride: !flagged,
      )));
      if (styleContext != null && styleContext.trim().isNotEmpty) {
        sources.add('你的風格');
      }
      sources.add(flagged ? '只看本段' : '對象資料');
    }

    return sources.isEmpty ? const ['目前問題'] : sources;
  }

  bool _hasAnalysisSnapshot(CoachChatAnalysisSnapshot snapshot) {
    return snapshot.heatScore != null ||
        (snapshot.stage?.trim().isNotEmpty ?? false) ||
        (snapshot.summary?.trim().isNotEmpty ?? false) ||
        (snapshot.nextStep?.trim().isNotEmpty ?? false) ||
        (snapshot.coachActionType?.trim().isNotEmpty ?? false) ||
        snapshot.keySignals.any((signal) => signal.trim().isNotEmpty);
  }

  Future<void> _ask() async {
    if (ref
        .read(coachChatControllerProvider(widget.conversationId))
        .isLoading) {
      return;
    }
    final question = _controller.text.trim();
    if (question.isEmpty) return;
    final consented = await AiDataSharingConsent.ensure(
      context,
      featureLabel: 'Coach 1:1',
    );
    if (!consented || !mounted) return;
    if (ref
        .read(coachChatControllerProvider(widget.conversationId))
        .isLoading) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _lastAskedQuestion = question;
      _controller.clear();
    });
    ref.read(coachChatControllerProvider(widget.conversationId).notifier).ask(
          question: question,
          analysisSnapshot: widget.analysisSnapshot,
        );
  }

  void _fillSuggestedQuestion(String question) {
    _controller.text = question;
    _controller.selection = TextSelection.collapsed(offset: question.length);
  }

  Future<void> _retryLastQuestion() async {
    final question = _lastAskedQuestion?.trim();
    if (question == null || question.isEmpty) return;
    _controller.text = question;
    _controller.selection = TextSelection.collapsed(offset: question.length);
    await _ask();
  }

  Future<void> _forceAnswer() async {
    final consented = await AiDataSharingConsent.ensure(
      context,
      featureLabel: 'Coach 1:1',
    );
    if (!consented || !mounted) return;
    await ref
        .read(coachChatControllerProvider(widget.conversationId).notifier)
        .forceAnswer(analysisSnapshot: widget.analysisSnapshot);
  }

  void _focusInputForFollowUp() {
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _unfocusInput() {
    _focusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _returnToAnalysis() {
    _unfocusInput();
    widget.onReturnToAnalysis?.call();
  }
}

class _CoachChatThreadView extends StatelessWidget {
  final List<CoachChatResult> results;
  final int dailyRemaining;
  final VoidCallback onFollowUp;
  final VoidCallback onForceAnswer;

  const _CoachChatThreadView({
    required this.results,
    required this.dailyRemaining,
    required this.onFollowUp,
    required this.onForceAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final latest = results.first;
    final previous = results.skip(1).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoachChatResultView(
          result: latest,
          question: latest.question,
          dailyRemaining: dailyRemaining,
          onFollowUp: onFollowUp,
          onForceAnswer: onForceAnswer,
        ),
        if (latest.earlierSummary?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 10),
          _EarlierCoachSummaryCard(result: latest),
        ],
        if (previous.isNotEmpty) ...[
          const SizedBox(height: 10),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              initiallyExpanded: false,
              title: Text(
                '前面 ${previous.length} 輪教練紀錄',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '已扣額度的正式建議會保留；最新版仍放在上面。',
                style: AppTypography.caption.copyWith(
                  color: AppColors.glassTextSecondary,
                ),
              ),
              children: previous
                  .map(
                    (result) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CoachChatHistoryTile(result: result),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _EarlierCoachSummaryCard extends StatelessWidget {
  final CoachChatResult result;

  const _EarlierCoachSummaryCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final count = result.earlierResultCount;
    final title = count > 0 ? '更早 $count 輪摘要' : '更早教練摘要';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          initiallyExpanded: false,
          title: Text(
            title,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            '超過最近 10 輪的內容會保留成摘要，不讓頁面無限變長。',
            style: AppTypography.caption.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                result.earlierSummary!.trim(),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachChatHistoryTile extends StatelessWidget {
  final CoachChatResult result;

  const _CoachChatHistoryTile({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.glassBorder.withValues(alpha: 0.7),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(
            result.question,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            '${_timeLabel(result.generatedAt)} · ${result.headline}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _CostStatusChip(
                costDeducted: result.costDeducted,
                dailyRemaining: -1,
                isClarifying: result.isClarifyingQuestion,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              result.answer,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextPrimary,
                height: 1.45,
              ),
            ),
            if (result.suggestedLine != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.56),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  result.suggestedLine!,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _InfoLine(label: '這次先做', value: result.nextStep),
            _InfoLine(label: '邊界提醒', value: result.boundaryReminder),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _copyCoachTurn(context),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('複製這輪'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _copyCoachTurn(BuildContext context) async {
    final parts = <String>[
      '你問：${result.question}',
      result.headline,
      result.answer,
      '這次先做：${result.nextStep}',
      if (result.suggestedLine != null) '可以這樣說：${result.suggestedLine}',
      '邊界提醒：${result.boundaryReminder}',
    ];
    await Clipboard.setData(ClipboardData(text: parts.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已複製'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// 公開僅為了 widget test 直接 pump；production 只在本檔內使用。
@visibleForTesting
class CoachChatResultView extends ConsumerWidget {
  final CoachChatResult result;
  final String? question;
  final int dailyRemaining;
  final VoidCallback onFollowUp;
  final VoidCallback onForceAnswer;

  const CoachChatResultView({
    super.key,
    required this.result,
    required this.dailyRemaining,
    required this.onFollowUp,
    required this.onForceAnswer,
    this.question,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = CoachChatModeX.fromWire(result.mode);
    final isClarifying = result.isClarifyingQuestion;
    final outcomeEvent = isClarifying
        ? null
        : ref.watch(
            coachingOutcomeEventProvider(
              coachingOutcomeIdForCoachResult(result.id),
            ),
          );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  mode.label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.headline,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.glassTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (question != null && question!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '你剛剛問：$question',
              style: AppTypography.caption.copyWith(
                color: AppColors.glassTextSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          _CostStatusChip(
            costDeducted: result.costDeducted,
            dailyRemaining: dailyRemaining,
            isClarifying: isClarifying,
          ),
          const SizedBox(height: 10),
          if (isClarifying) ...[
            _CoachNotice(
              icon: Icons.psychology_alt_outlined,
              title: '教練想先問清楚（免費釐清）',
              body: result.reflectionQuestion ?? result.answer,
            ),
            const SizedBox(height: 10),
            Text(
              result.answer,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextPrimary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            if (result.userTruth != null)
              _InfoLine(label: '我理解你的真實想法', value: result.userTruth!),
            _InfoLine(
              label: '這輪卡點',
              value: _frictionTypeLabel(result.frictionType),
            ),
            _InfoLine(label: '你現在卡在', value: result.userState),
            _InfoLine(label: '先補充這一點', value: result.nextStep),
          ] else
            _InfoLine(label: '這次先做', value: result.nextStep),
          if (result.suggestedLine != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                result.suggestedLine!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _copyText(context, result.suggestedLine!),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('複製這句'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          _InfoLine(label: '邊界提醒', value: result.boundaryReminder),
          if (!isClarifying)
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                key: ValueKey('coach-full-analysis-${result.id}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                visualDensity: VisualDensity.compact,
                iconColor: AppColors.primary,
                collapsedIconColor: AppColors.glassTextSecondary,
                title: Text(
                  '看完整教練分析',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.answer,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.glassTextPrimary,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (result.userTruth != null)
                          _InfoLine(
                            label: '我理解你的真實想法',
                            value: result.userTruth!,
                          ),
                        _InfoLine(
                          label: '這輪卡點',
                          value: _frictionTypeLabel(result.frictionType),
                        ),
                        _InfoLine(
                          label: '你現在卡在',
                          value: result.userState,
                        ),
                        if (result.rewriteDecision != null)
                          _InfoLine(
                            label: '教練判斷',
                            value:
                                '${_rewriteDecisionLabel(result.rewriteDecision!)}${result.rewriteReason == null ? '' : '：${result.rewriteReason}'}',
                          ),
                        if (result.needsReflection &&
                            result.reflectionQuestion != null)
                          _InfoLine(
                            label: '教練追問',
                            value: result.reflectionQuestion!,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onFollowUp,
                icon: Icon(
                  isClarifying
                      ? Icons.edit_note_outlined
                      : Icons.add_comment_outlined,
                  size: 18,
                ),
                label: Text(isClarifying ? '補充我的想法' : '繼續深挖'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.38),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (isClarifying)
                TextButton.icon(
                  onPressed: () => _confirmForceAnswer(context),
                  icon: const Icon(Icons.bolt_outlined, size: 18),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.glassTextSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                  label: const Text('直接看建議（扣 1 則）'),
                ),
            ],
          ),
          if (!isClarifying) ...[
            const SizedBox(height: 12),
            CoachingOutcomeCaptureCard(
              event: outcomeEvent,
              onUserActionSelected: (action) =>
                  _recordUserAction(context, ref, action),
              onOutcomeSelected: (signal) =>
                  _recordReaction(context, ref, signal),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _recordUserAction(
    BuildContext context,
    WidgetRef ref,
    CoachingUserAction action,
  ) async {
    final outcome = coachingOutcomeForUserAction(action);
    try {
      await ref.read(coachingOutcomeRecorderProvider).recordCoachResultOutcome(
            result: result,
            userAction: action,
            outcome: outcome,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已記下「${coachingUserActionLabel(action)}」，不扣額度。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暫時記不起來，晚點再試一次。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _recordReaction(
    BuildContext context,
    WidgetRef ref,
    CoachingOutcomeSignal signal,
  ) async {
    try {
      final updated = await ref
          .read(coachingOutcomeRecorderProvider)
          .recordCoachResultReaction(result: result, outcome: signal);
      if (updated == null) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已記下「${coachingOutcomeSignalLabel(signal)}」，不扣額度。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暫時記不起來，晚點再試一次。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _rewriteDecisionLabel(String decision) {
    return switch (decision) {
      'keep_original' => '原話就很好',
      'light_edit' => '輕修就好',
      'rewrite' => '建議重寫',
      'do_not_send' => '先不要送',
      _ => '保持彈性',
    };
  }

  String _frictionTypeLabel(String type) {
    return switch (type) {
      'fearOfMistake' => '怕犯錯／怕丟臉',
      'overPolishing' => '想找完美句，反而卡住',
      'hesitatesToMoveForward' => '有窗口，但不敢往前一步',
      'emotionalOverreach' => '情緒上頭，想補位或討確認',
      'boundaryRisk' => '界線或壓迫風險',
      'stopLoss' => '這局該先停或止損',
      'none' => '狀態穩，照節奏走',
      _ => '意圖還沒完全釐清',
    };
  }

  Future<void> _confirmForceAnswer(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('直接看正式建議？'),
        content: const Text(
          '教練會跳過免費釐清，直接給完整建議；成功後會扣 1 則額度。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('先補充想法'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('扣 1 則並生成'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onForceAnswer();
    }
  }

  Future<void> _copyText(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已複製'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _CoachMemorySourceStrip extends StatelessWidget {
  final List<String> sources;

  const _CoachMemorySourceStrip({required this.sources});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.glassBorder.withValues(alpha: 0.75),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome_outlined,
                size: 15,
                color: AppColors.primary,
              ),
              const SizedBox(width: 5),
              Text(
                '教練參考',
                style: AppTypography.caption.copyWith(
                  color: AppColors.glassTextSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          ...sources.map(
            (source) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.14),
                ),
              ),
              child: Text(
                source,
                style: AppTypography.caption.copyWith(
                  color: AppColors.glassTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachFailureNotice extends StatelessWidget {
  final String title;
  final String subtitle;
  final String question;
  final String message;
  final String actionLabel;
  final VoidCallback onRetry;

  const _CoachFailureNotice({
    required this.title,
    required this.subtitle,
    required this.question,
    required this.message,
    required this.actionLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.glassTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.glassTextSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '你剛剛問：$question',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: AppColors.glassTextSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: AppTypography.caption.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(actionLabel),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CostStatusChip extends StatelessWidget {
  final int costDeducted;
  final int dailyRemaining;
  final bool isClarifying;

  const _CostStatusChip({
    required this.costDeducted,
    required this.dailyRemaining,
    required this.isClarifying,
  });

  @override
  Widget build(BuildContext context) {
    final color = isClarifying || costDeducted == 0
        ? AppColors.success
        : AppColors.warning;
    final label = isClarifying || costDeducted == 0
        ? '免費釐清（最多 3 次）'
        : dailyRemaining >= 0
            ? '已扣 $costDeducted 則 · 今日剩 $dailyRemaining 則'
            : '已扣 $costDeducted 則';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.glassTextPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: RichText(
        text: TextSpan(
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.glassTextPrimary,
            height: 1.4,
          ),
          children: [
            TextSpan(
              text: '$label：',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _CoachNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _CoachNotice({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
