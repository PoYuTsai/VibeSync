// lib/features/partner/presentation/widgets/partner_conversation_tile.dart
//
// Cell rendering a single conversation underneath a Partner detail screen.
// Pure render — receives the Conversation + onTap + optional onReassign.
//
// PR-B Task 5: trailing changed from chevron to ⋮ menu so reassign is
// discoverable. The tile stays pure (no routing / picker) — caller wires
// onReassign with the actual picker + ConversationWriteController flow.
//
// Post-A2 visual polish (2026-04-28): glass shell with heat-driven accent.
// Iter v2 (Bruce TF feedback): tiles are the *actionable* items on this
// page (hero/traits/radar are info displays — these are what users tap to
// enter a conversation), so they need to pop more than the info cards.
//   - Glass opacity bumped: 6% → 10% bg, 10% → 18% border.
//   - 4px left accent stripe colored by heat bucket (cold/warm/hot/veryHot,
//     primaryLight when heat is null) — at-a-glance signal of conversation
//     temperature, reinforces the page's "互動狀態" mood.
// Behavior unchanged — onTap, onReassign, onDelete, ⋮ menu all preserved.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../conversation/domain/entities/conversation.dart';

class PartnerConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onReassign;
  final VoidCallback? onDelete;
  const PartnerConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onReassign,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final heat = conversation.lastEnthusiasmScore;
    final dateLabel = DateFormat('MM/dd').format(conversation.updatedAt);
    final accent = _accentColorForHeat(heat);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.14),
              blurRadius: 18,
              spreadRadius: 0,
            ),
          ],
        ),
        // Material(transparent) lets the InkWell ripple show without painting
        // a solid rectangle on top of the glass surface.
        child: Material(
          color: Colors.transparent,
          // Stack > Row(crossAxis.stretch) here: ListTile sizes itself by
          // intrinsic content, so a stretched Row child needs a bounded
          // parent height (ListTile alone has none). Positioned stripe
          // with top/bottom: 0 fills the tile's painted height correctly
          // without forcing intrinsic-layout passes.
          child: Stack(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                onTap: onTap,
                title: Text(
                  '$dateLabel 互動紀錄',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
                subtitle: Text(
                  '${conversation.currentRound} 輪 · ${conversation.messages.length} 則訊息'
                  '${heat != null ? ' · 本次投入 $heat' : ''}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                trailing: onReassign == null && onDelete == null
                    ? const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.onBackgroundSecondary,
                      )
                    : PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: AppColors.onBackgroundPrimary,
                        ),
                        onSelected: (v) {
                          if (v == 'reassign') onReassign?.call();
                          if (v == 'delete') onDelete?.call();
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem<String>(
                            value: 'reassign',
                            enabled: onReassign != null,
                            child: const Text('改派到其他對象'),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            enabled: onDelete != null,
                            child: const Text('刪除對話'),
                          ),
                        ],
                      ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Heat → accent color bucket. Reuses existing AppColors enthusiasm
  /// tokens so the tile reads consistent with any future heat indicator.
  /// Null heat (analysis pending) gets primaryLight — the "neutral but
  /// alive" tone, never grey, so the tile still feels intentional.
  static Color _accentColorForHeat(int? heat) {
    if (heat == null) return AppColors.primaryLight;
    if (heat <= 30) return AppColors.cold;
    if (heat <= 60) return AppColors.warm;
    if (heat <= 80) return AppColors.hot;
    return AppColors.veryHot;
  }
}
