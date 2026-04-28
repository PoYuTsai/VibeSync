// lib/features/partner/presentation/widgets/partner_list_card.dart
//
// Pure render — receives Partner + already-computed PartnerAggregateView.
// Does NOT subscribe to providers (lifted-aggregate API, Codex r1 P1.3b).
// Keeps tests hermetic and allows reuse outside the list screen.
//
// Phase 4 Task 2 visual restoration (D-P4-3 / D-P4-4):
//   1. GlassmorphicContainer card background
//   2. Yellow gradient avatar circle with name initial
//   3. Name + relative-date header row
//   4. Heat indicator (emoji + score) OR "🌡️ 待分析" fallback
//   5. Interleaved interest/trait preview joined by " · ", capped at 3
//   6. Trailing delete icon (only when onDelete is non-null)
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/glassmorphic_container.dart';
import '../../../analysis/domain/entities/enthusiasm_level.dart';
import '../../domain/entities/partner.dart';
import '../../domain/extensions/partner_aggregates.dart';

class PartnerListCard extends StatelessWidget {
  final Partner partner;
  final PartnerAggregateView aggregate;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const PartnerListCard({
    super.key,
    required this.partner,
    required this.aggregate,
    required this.onTap,
    this.onDelete,
  });

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return DateFormat('HH:mm').format(date);
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return DateFormat('MM/dd').format(date);
  }

  /// interleave interests / traits 後 cap 3，避免 traits 被 interests 餓死。
  /// (Codex spec review HS-P4-5)
  List<String> _previewTags(List<String> interests, List<String> traits) {
    final out = <String>[];
    final maxLen =
        interests.length > traits.length ? interests.length : traits.length;
    for (var i = 0; i < maxLen && out.length < 3; i++) {
      if (i < interests.length) {
        out.add(interests[i]);
        if (out.length >= 3) break;
      }
      if (i < traits.length) {
        out.add(traits[i]);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final tags = _previewTags(aggregate.unionInterests, aggregate.unionTraits);
    final heat = aggregate.latestHeat;
    final level = heat != null ? EnthusiasmLevel.fromScore(heat) : null;

    return GlassmorphicContainer(
      padding: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.avatarHerStart, AppColors.avatarHerEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              partner.name.isNotEmpty ? partner.name[0] : '?',
              style:
                  AppTypography.titleLarge.copyWith(color: Colors.black87),
            ),
          ),
        ),
        title: Row(children: [
          Expanded(
            child: Text(
              partner.name,
              style: AppTypography.titleLarge
                  .copyWith(color: AppColors.glassTextPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatDate(aggregate.lastInteraction),
            style: AppTypography.caption
                .copyWith(color: AppColors.glassTextHint),
          ),
        ]),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (level != null)
              Row(children: [
                Text(level.emoji),
                const SizedBox(width: 4),
                Text(
                  '$heat',
                  style: AppTypography.caption.copyWith(color: level.color),
                ),
              ])
            else
              Row(children: [
                const Text('🌡️'),
                const SizedBox(width: 4),
                Text(
                  '待分析',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.glassTextHint),
                ),
              ]),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                tags.join(' · '),
                style: AppTypography.caption
                    .copyWith(color: AppColors.glassTextHint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: onDelete != null
            ? IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.glassTextHint),
                onPressed: onDelete,
                tooltip: '刪除對象',
              )
            : null,
      ),
    );
  }
}
