// lib/features/learning/presentation/widgets/ebook_dialogue_block.dart
//
// 教材用對話泡泡（display-only）。
//
// 刻意不重用 production 的 conversation bubble：那一套帶著時間戳、已讀狀態與
// 互動依賴，塞進教材會變成假的聊天畫面。這裡只負責把案例排版出來。
//
// 三燈與死亡點一律「顏色＋圖示＋文字」三者齊全，不能只靠紅黃綠。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/ebook_block.dart';

/// 三燈標籤。文字與圖示都在，色盲或灰階螢幕也能判讀。
class EbookSignalChip extends StatelessWidget {
  const EbookSignalChip({super.key, required this.signal});

  final EbookSignal signal;

  static String labelFor(EbookSignal signal) {
    switch (signal) {
      case EbookSignal.green:
        return '綠燈';
      case EbookSignal.yellow:
        return '黃燈';
      case EbookSignal.red:
        return '紅燈';
    }
  }

  static String meaningFor(EbookSignal signal) {
    switch (signal) {
      case EbookSignal.green:
        return '可以推進';
      case EbookSignal.yellow:
        return '維持或換軌';
      case EbookSignal.red:
        return '退回或停止';
    }
  }

  static IconData iconFor(EbookSignal signal) {
    switch (signal) {
      case EbookSignal.green:
        return Icons.trending_up_rounded;
      case EbookSignal.yellow:
        return Icons.pause_circle_outline_rounded;
      case EbookSignal.red:
        return Icons.do_not_disturb_on_outlined;
    }
  }

  static Color colorFor(EbookSignal signal) {
    switch (signal) {
      case EbookSignal.green:
        return AppColors.success;
      case EbookSignal.yellow:
        return AppColors.warning;
      case EbookSignal.red:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(signal);
    final label = labelFor(signal);
    return Semantics(
      label: '$label，${meaningFor(signal)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconFor(signal), size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$label · ${meaningFor(signal)}',
                style: AppTypography.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeathPointChip extends StatelessWidget {
  const _DeathPointChip();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '死亡點：對話從這一句開始失去動能',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.70)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.heart_broken_outlined,
                size: 13, color: AppColors.error),
            const SizedBox(width: 4),
            Text(
              '死亡點',
              style: AppTypography.caption.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EbookDialogueBlockView extends StatelessWidget {
  const EbookDialogueBlockView({super.key, required this.block});

  final EbookDialogueBlock block;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block.title != null) ...[
          Text(
            block.title!,
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (block.caption != null) ...[
          Text(
            block.caption!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (final line in block.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DialogueLineView(line: line),
          ),
      ],
    );
  }
}

class _DialogueLineView extends StatelessWidget {
  const _DialogueLineView({required this.line});

  final EbookDialogueLine line;

  static String _speakerLabel(EbookSpeaker speaker) {
    switch (speaker) {
      case EbookSpeaker.you:
        return '你';
      case EbookSpeaker.other:
        return '對方';
      case EbookSpeaker.coach:
        return '教練';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCoach = line.speaker == EbookSpeaker.coach;
    final isYou = line.speaker == EbookSpeaker.you;

    final bubbleColor = isCoach
        ? AppColors.coachAccent.withValues(alpha: 0.16)
        : isYou
            ? AppColors.ctaStart.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.07);
    final borderColor = isCoach
        ? AppColors.coachAccent.withValues(alpha: 0.45)
        : isYou
            ? AppColors.ctaStart.withValues(alpha: 0.42)
            : Colors.white.withValues(alpha: 0.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              isYou ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            // 大字級時仍要能換行，所以用 Flexible 而不是固定寬度。
            Flexible(
              child: Column(
                crossAxisAlignment:
                    isYou ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCoach
                            ? Icons.school_outlined
                            : isYou
                                ? Icons.person_outline
                                : Icons.favorite_border,
                        size: 13,
                        color: AppColors.onBackgroundSecondary
                            .withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _speakerLabel(line.speaker),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onBackgroundSecondary
                              .withValues(alpha: 0.7),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (line.timeLabel != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          line.timeLabel!,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onBackgroundSecondary
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      line.text,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (line.signal != null || line.isDeathPoint) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: isYou ? WrapAlignment.end : WrapAlignment.start,
            children: [
              if (line.isDeathPoint) const _DeathPointChip(),
              if (line.signal != null) EbookSignalChip(signal: line.signal!),
            ],
          ),
        ],
        if (line.annotation != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 16,
                margin: const EdgeInsets.only(top: 2, right: 8),
                decoration: BoxDecoration(
                  color: AppColors.ctaStart.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(
                child: Text(
                  line.annotation!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary
                        .withValues(alpha: 0.82),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
