import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../data/providers/coach_chat_providers.dart';
import '../../data/services/coach_chat_api_service.dart';
import '../../domain/entities/coach_chat_mode.dart';
import '../../domain/entities/coach_chat_result.dart';

class CoachChatCard extends ConsumerStatefulWidget {
  final String conversationId;
  final CoachChatAnalysisSnapshot analysisSnapshot;
  final VoidCallback? onQuotaExceeded;

  const CoachChatCard({
    super.key,
    required this.conversationId,
    required this.analysisSnapshot,
    this.onQuotaExceeded,
  });

  @override
  ConsumerState<CoachChatCard> createState() => _CoachChatCardState();
}

class _CoachChatCardState extends ConsumerState<CoachChatCard> {
  final _controller = TextEditingController();

  static const _chips = <String>[
    '她是什麼意思？',
    '我該怎麼回？',
    '我是不是太急？',
    '這局值不值得？',
    '我該推進嗎？',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = coachChatControllerProvider(widget.conversationId);
    final state = ref.watch(provider);
    final history = ref.watch(coachChatHistoryProvider(widget.conversationId));
    final latest =
        state.valueOrNull ?? (history.isEmpty ? null : history.first);
    final isLoading = state.isLoading;

    ref.listen<AsyncValue<CoachChatResult?>>(provider, (previous, next) {
      final error = next.error;
      if (error == null) return;
      if (error is CoachChatQuotaExceededException) {
        widget.onQuotaExceeded?.call();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('教練暫時沒接住，請稍後再試。'),
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
                      '不確定怎麼判斷，就直接問；成功回覆會扣 1 則額度。',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.glassTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _chips
                .map(
                  (chip) => ActionChip(
                    label: Text(chip),
                    onPressed: isLoading ? null : () => _controller.text = chip,
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
            maxLength: 240,
            minLines: 1,
            maxLines: 3,
            enabled: !isLoading,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _ask(),
            inputFormatters: [LengthLimitingTextInputFormatter(240)],
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextPrimary,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '例如：她這句話是真的有興趣嗎？',
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
              suffixIcon: IconButton(
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded),
                onPressed: isLoading ? null : _ask,
                color: AppColors.primary,
              ),
            ),
          ),
          if (latest != null) ...[
            const SizedBox(height: 14),
            _CoachChatResultView(result: latest),
          ],
        ],
      ),
    );
  }

  void _ask() {
    final question = _controller.text.trim();
    if (question.isEmpty) return;
    FocusScope.of(context).unfocus();
    ref.read(coachChatControllerProvider(widget.conversationId).notifier).ask(
          question: question,
          analysisSnapshot: widget.analysisSnapshot,
        );
  }
}

class _CoachChatResultView extends StatelessWidget {
  final CoachChatResult result;

  const _CoachChatResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    final mode = CoachChatModeX.fromWire(result.mode);
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
          const SizedBox(height: 10),
          Text(
            result.answer,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.glassTextPrimary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          _InfoLine(label: '你現在卡在', value: result.userState),
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
          ],
          const SizedBox(height: 10),
          _InfoLine(label: '邊界提醒', value: result.boundaryReminder),
          if (result.needsReflection && result.reflectionQuestion != null)
            _InfoLine(label: '教練追問', value: result.reflectionQuestion!),
        ],
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
