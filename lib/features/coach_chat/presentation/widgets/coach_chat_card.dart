import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../conversation/data/providers/conversation_providers.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../data/providers/coach_chat_providers.dart';
import '../../data/services/coach_chat_api_service.dart';
import '../../domain/entities/coach_chat_mode.dart';
import '../../domain/entities/coach_chat_result.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';

class CoachChatCard extends ConsumerStatefulWidget {
  final String conversationId;
  final CoachChatAnalysisSnapshot analysisSnapshot;
  final VoidCallback? onQuotaExceeded;
  final VoidCallback? onReturnToAnalysis;
  final int focusRequestToken;

  const CoachChatCard({
    super.key,
    required this.conversationId,
    required this.analysisSnapshot,
    this.onQuotaExceeded,
    this.onReturnToAnalysis,
    this.focusRequestToken = 0,
  });

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
    final history = ref.watch(coachChatHistoryProvider(widget.conversationId));
    final subscription = ref.watch(subscriptionProvider);
    final conversation = ref.watch(conversationProvider(widget.conversationId));
    final memorySources = _coachMemorySources(
      ref: ref,
      conversation: conversation,
      analysisSnapshot: widget.analysisSnapshot,
    );
    final activeError = state.hasError && _lastAskedQuestion != null;
    final latest = activeError
        ? null
        : (state.valueOrNull ?? (history.isEmpty ? null : history.first));
    final isLoading = state.isLoading;
    final canSubmit = !isLoading;
    final isClarifying = latest?.isClarifyingQuestion ?? false;

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
          content: Text(_failureMessage(error)),
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
                      '先釐清你的真實想法；正式建議才扣 1 則額度。',
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
            _CoachThinkingNotice(question: _lastAskedQuestion),
          ] else if (activeError) ...[
            const SizedBox(height: 14),
            _CoachFailureNotice(
              question: _lastAskedQuestion!,
              message: _failureMessage(state.error!),
              onRetry: _retryLastQuestion,
            ),
          ] else if (latest != null) ...[
            const SizedBox(height: 14),
            _CoachChatResultView(
              result: latest,
              question: latest.question,
              dailyRemaining: subscription.dailyRemaining,
              onFollowUp: _focusInputForFollowUp,
              onForceAnswer: () => ref
                  .read(coachChatControllerProvider(widget.conversationId)
                      .notifier)
                  .forceAnswer(analysisSnapshot: widget.analysisSnapshot),
            ),
          ],
        ],
      ),
    );
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

  void _ask() {
    if (ref
        .read(coachChatControllerProvider(widget.conversationId))
        .isLoading) {
      return;
    }
    final question = _controller.text.trim();
    if (question.isEmpty) return;
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

  void _retryLastQuestion() {
    final question = _lastAskedQuestion?.trim();
    if (question == null || question.isEmpty) return;
    _controller.text = question;
    _controller.selection = TextSelection.collapsed(offset: question.length);
    _ask();
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

  String _failureMessage(Object error) {
    if (error is CoachChatGenerationFailedException) {
      return '教練暫時沒接住，這次未扣額度，請稍後再試。';
    }
    if (error is CoachChatApiException) {
      return '連線不穩，這次未扣額度，請稍後再試。';
    }
    return '教練暫時沒接住，這次未扣額度，請稍後再試。';
  }
}

class _CoachChatResultView extends StatelessWidget {
  final CoachChatResult result;
  final String? question;
  final int dailyRemaining;
  final VoidCallback onFollowUp;
  final VoidCallback onForceAnswer;

  const _CoachChatResultView({
    required this.result,
    required this.dailyRemaining,
    required this.onFollowUp,
    required this.onForceAnswer,
    this.question,
  });

  @override
  Widget build(BuildContext context) {
    final mode = CoachChatModeX.fromWire(result.mode);
    final isClarifying = result.isClarifyingQuestion;
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
              IconButton(
                tooltip: '複製教練回覆',
                icon: const Icon(Icons.copy_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                color: AppColors.glassTextSecondary,
                onPressed: () => _copyCoachAnswer(context),
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
              title: '教練想先問清楚（這題不扣）',
              body: result.reflectionQuestion ?? result.answer,
            ),
            const SizedBox(height: 10),
          ],
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
          _InfoLine(
              label: isClarifying ? '先補充這一點' : '這次先做', value: result.nextStep),
          if (!isClarifying && result.rewriteDecision != null)
            _InfoLine(
              label: '教練判斷',
              value:
                  '${_rewriteDecisionLabel(result.rewriteDecision!)}${result.rewriteReason == null ? '' : '：${result.rewriteReason}'}',
            ),
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
          if (!isClarifying &&
              result.needsReflection &&
              result.reflectionQuestion != null)
            _InfoLine(label: '教練追問', value: result.reflectionQuestion!),
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
        ],
      ),
    );
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
          '教練會跳過免費追問，直接給完整建議；成功後會扣 1 則額度。',
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

  Future<void> _copyCoachAnswer(BuildContext context) async {
    final parts = <String>[
      result.headline,
      result.answer,
      '這輪卡點：${_frictionTypeLabel(result.frictionType)}',
      '你現在卡在：${result.userState}',
      '這次先做：${result.nextStep}',
      if (result.suggestedLine != null) '可以這樣說：${result.suggestedLine}',
      '邊界提醒：${result.boundaryReminder}',
      if (result.needsReflection && result.reflectionQuestion != null)
        '教練追問：${result.reflectionQuestion}',
    ];
    await _copyText(context, parts.join('\n'));
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

class _CoachThinkingNotice extends StatelessWidget {
  final String? question;

  const _CoachThinkingNotice({this.question});

  @override
  Widget build(BuildContext context) {
    final trimmedQuestion = question?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '教練正在接這句',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.glassTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  trimmedQuestion == null || trimmedQuestion.isEmpty
                      ? '正在整合本段對話、你的風格和最新分析。'
                      : '「$trimmedQuestion」',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
    );
  }
}

class _CoachFailureNotice extends StatelessWidget {
  final String question;
  final String message;
  final VoidCallback onRetry;

  const _CoachFailureNotice({
    required this.question,
    required this.message,
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
                      '這題教練沒接住',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.glassTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '未扣額度。上一輪回覆已保留，但不是這題的新結果。',
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
              label: const Text('重試這題'),
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
        ? '這次不扣額度'
        : '已扣 $costDeducted 則 · 今日剩 $dailyRemaining 則';
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
