// lib/shared/widgets/coaching_outcome_capture_card.dart
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/coaching_memory/domain/entities/coaching_outcome_event.dart';

String coachingUserActionLabel(CoachingUserAction action) => switch (action) {
      CoachingUserAction.sentAsIs => '照著發了',
      CoachingUserAction.editedAndSent => '改一改才發',
      CoachingUserAction.didNotSend => '沒有發',
      CoachingUserAction.askedCoach => '回頭問了教練',
      CoachingUserAction.unknown => '尚未回報',
    };

String coachingOutcomeSignalLabel(CoachingOutcomeSignal signal) =>
    switch (signal) {
      CoachingOutcomeSignal.engaged => '有接話',
      CoachingOutcomeSignal.cold => '冷回',
      CoachingOutcomeSignal.noReply => '已讀沒回',
      CoachingOutcomeSignal.negative => '反應不好',
      CoachingOutcomeSignal.pending => '等你回報',
      CoachingOutcomeSignal.unknown => '未知',
    };

class _UserActionOption {
  final CoachingUserAction action;
  final IconData icon;

  const _UserActionOption({required this.action, required this.icon});
}

class _OutcomeSignalOption {
  final CoachingOutcomeSignal signal;
  final IconData icon;

  const _OutcomeSignalOption({required this.signal, required this.icon});
}

const _userActionOptions = <_UserActionOption>[
  _UserActionOption(
    action: CoachingUserAction.sentAsIs,
    icon: Icons.send_rounded,
  ),
  _UserActionOption(
    action: CoachingUserAction.editedAndSent,
    icon: Icons.edit_note_rounded,
  ),
  _UserActionOption(
    action: CoachingUserAction.didNotSend,
    icon: Icons.do_not_disturb_on_outlined,
  ),
  _UserActionOption(
    action: CoachingUserAction.askedCoach,
    icon: Icons.forum_outlined,
  ),
];

const _outcomeSignalOptions = <_OutcomeSignalOption>[
  _OutcomeSignalOption(
    signal: CoachingOutcomeSignal.engaged,
    icon: Icons.check_circle_outline_rounded,
  ),
  _OutcomeSignalOption(
    signal: CoachingOutcomeSignal.cold,
    icon: Icons.ac_unit_rounded,
  ),
  _OutcomeSignalOption(
    signal: CoachingOutcomeSignal.noReply,
    icon: Icons.hourglass_empty_rounded,
  ),
  _OutcomeSignalOption(
    signal: CoachingOutcomeSignal.negative,
    icon: Icons.thumb_down_alt_outlined,
  ),
];

/// Shared two-stage outcome capture card.
///
/// Stage 1 always asks what the user did with the suggestion. Stage 2
/// (her reaction) only appears once the user reports actually sending
/// something (as-is or edited) — there is nothing to react to otherwise.
///
/// This widget is stateless: all selection state is derived from the
/// passed-in [event]. Callers own persistence and pass the freshly
/// rebuilt [event] back down after handling the callbacks.
class CoachingOutcomeCaptureCard extends StatelessWidget {
  final CoachingOutcomeEvent? event;
  final ValueChanged<CoachingUserAction> onUserActionSelected;
  final ValueChanged<CoachingOutcomeSignal> onOutcomeSelected;

  const CoachingOutcomeCaptureCard({
    super.key,
    required this.event,
    required this.onUserActionSelected,
    required this.onOutcomeSelected,
  });

  bool get _showStage2 {
    final userAction = event?.userAction;
    return userAction == CoachingUserAction.sentAsIs ||
        userAction == CoachingUserAction.editedAndSent;
  }

  String get _subtitle {
    final currentEvent = event;
    final userAction = currentEvent?.userAction;

    if (currentEvent == null || userAction == CoachingUserAction.unknown) {
      return '點一下，教練下次就記得這招有沒有用。';
    }

    if (userAction == CoachingUserAction.didNotSend ||
        userAction == CoachingUserAction.askedCoach) {
      return '已記下，謝謝回報。';
    }

    final outcome = currentEvent.outcome;
    if (outcome != CoachingOutcomeSignal.pending &&
        outcome != CoachingOutcomeSignal.unknown) {
      return '已記下：${coachingOutcomeSignalLabel(outcome)}。你也可以改選新的結果。';
    }

    return '再告訴我們她的反應，記錄會更完整。';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.auto_stories_outlined,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '這則建議你怎麼處理？',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.glassTextPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _userActionOptions.map((option) {
              final isSelected = event?.userAction == option.action;
              return ChoiceChip(
                showCheckmark: false,
                selected: isSelected,
                label: Text(coachingUserActionLabel(option.action)),
                avatar: Icon(
                  option.icon,
                  size: 16,
                  color: isSelected ? Colors.white : AppColors.primary,
                ),
                onSelected: (_) => onUserActionSelected(option.action),
                selectedColor: AppColors.primary,
                backgroundColor: Colors.white.withValues(alpha: 0.62),
                labelStyle: AppTypography.caption.copyWith(
                  color:
                      isSelected ? Colors.white : AppColors.glassTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.glassBorder.withValues(alpha: 0.8),
                ),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          if (_showStage2) ...[
            const SizedBox(height: 10),
            Text(
              '她的反應？',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _outcomeSignalOptions.map((option) {
                final isSelected = event?.outcome == option.signal;
                return ChoiceChip(
                  showCheckmark: false,
                  selected: isSelected,
                  label: Text(coachingOutcomeSignalLabel(option.signal)),
                  avatar: Icon(
                    option.icon,
                    size: 16,
                    color: isSelected ? Colors.white : AppColors.primary,
                  ),
                  onSelected: (_) => onOutcomeSelected(option.signal),
                  selectedColor: AppColors.primary,
                  backgroundColor: Colors.white.withValues(alpha: 0.62),
                  labelStyle: AppTypography.caption.copyWith(
                    color:
                        isSelected ? Colors.white : AppColors.glassTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.glassBorder.withValues(alpha: 0.8),
                  ),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '回報不扣額度，也不會自動改寫長期記憶；只是先把結果存在本機。',
            style: AppTypography.caption.copyWith(
              color: AppColors.glassTextSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
