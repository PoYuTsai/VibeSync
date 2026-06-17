import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/analysis_models.dart';

class ReplyStyleCard extends StatelessWidget {
  final String type;
  final String content;
  final ReplyOption? option;
  final bool isRecommended;
  final void Function(String text, String snackBarMessage) onCopy;

  const ReplyStyleCard({
    super.key,
    required this.type,
    required this.content,
    required this.option,
    required this.isRecommended,
    required this.onCopy,
  });

  static const _labels = {
    'extend': '\u{1F504} 延展',
    'resonate': '\u{1F4AC} 共鳴',
    'tease': '\u{1F60F} 調情',
    'humor': '\u{1F3AD} 幽默',
    'coldRead': '\u{1F52E} 冷讀',
  };

  static const _reasons = {
    'extend': '順勢接話並深挖細節',
    'resonate': '建立情感連結與共鳴',
    'tease': '製造曖昧張力與反差',
    'humor': '用幽默化解尷尬或升溫',
    'coldRead': '猜中她沒說的，製造驚喜',
  };

  Color _colorForType(String type) {
    switch (type) {
      case 'extend':
        return AppColors.cold;
      case 'resonate':
        return AppColors.warm;
      case 'tease':
        return AppColors.veryHot;
      case 'humor':
        return AppColors.hot;
      case 'coldRead':
        return AppColors.primaryLight;
      default:
        return AppColors.onBackgroundPrimary;
    }
  }

  List<ReplySegment> get _messages {
    final optionMessages =
        option?.messages.where((segment) => segment.isUsable).toList() ??
            const <ReplySegment>[];
    if (optionMessages.isNotEmpty) {
      return optionMessages;
    }

    return [
      ReplySegment(
        label: '建議訊息',
        sourceMessage: '',
        reply: content,
        reason: '',
      ),
    ];
  }

  String get _copyAllText => _messages
      .map((segment) => segment.reply.trim())
      .where((reply) => reply.isNotEmpty)
      .join('\n');

  @override
  Widget build(BuildContext context) {
    final approach = option?.approach.trim() ?? '';
    final messages = _messages;
    final visibleMessages = messages.take(3).toList();

    return Container(
      width: 312,
      margin: const EdgeInsets.only(right: 12),
      child: BrandSurfaceCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _labels[type] ?? type,
                  style: AppTypography.titleMedium.copyWith(
                    color: _colorForType(type),
                  ),
                ),
                const Spacer(),
                if (isRecommended) _RecommendedBadge(),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (approach.isNotEmpty) ...[
                      Text(
                        '接法',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.ctaStart,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        approach,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onBackgroundSecondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      '訊息組',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.6),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    for (var i = 0; i < visibleMessages.length; i++) ...[
                      _ReplyOptionMessageRow(
                        segment: visibleMessages[i],
                        index: i,
                        total: messages.length,
                        onCopy: onCopy,
                      ),
                      if (i != visibleMessages.length - 1)
                        const SizedBox(height: 6),
                    ],
                    if (messages.length > visibleMessages.length) ...[
                      const SizedBox(height: 5),
                      Text(
                        '還有 ${messages.length - visibleMessages.length} 則可在推薦卡查看',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onBackgroundSecondary
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '為什麼推薦',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Flexible(
                  child: Text(
                    '・${_reasons[type] ?? ''}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
            if (_copyAllText.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 34,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ctaStart,
                    side: BorderSide(
                      color: AppColors.ctaStart.withValues(alpha: 0.55),
                    ),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _copyAllText));
                    onCopy(
                      _copyAllText,
                      messages.length == 1 ? '已複製這句' : '已複製這組訊息',
                    );
                  },
                  icon: const Icon(Icons.copy, size: 15),
                  label: Text(
                    messages.length == 1 ? '複製這句' : '複製整組',
                    style: AppTypography.labelMedium,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ctaStart, AppColors.ctaEnd],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'AI 推薦',
        style: AppTypography.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ReplyOptionMessageRow extends StatelessWidget {
  final ReplySegment segment;
  final int index;
  final int total;
  final void Function(String text, String snackBarMessage) onCopy;

  const _ReplyOptionMessageRow({
    required this.segment,
    required this.index,
    required this.total,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final source = segment.sourceMessage.trim();
    final reply = segment.reply.trim();
    final sourceLabel = source.isNotEmpty
        ? '接：$source'
        : (total == 1 ? segment.displayLabel : '訊息 ${index + 1}');

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Clipboard.setData(ClipboardData(text: reply));
        onCopy(reply, total == 1 ? '已複製這句' : '已複製第 ${index + 1} 句');
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.brandInk.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sourceLabel,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    reply,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      height: 1.28,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.copy_rounded,
              size: 15,
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}
