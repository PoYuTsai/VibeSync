// lib/features/partner/presentation/widgets/partner_list_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
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

  String _avatarLabel(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';

    final latinWords = RegExp(r'[A-Za-z]+')
        .allMatches(trimmed)
        .map((m) => m.group(0)!)
        .toList();
    if (latinWords.length >= 2) {
      return '${latinWords[0][0]}${latinWords[1][0]}'.toUpperCase();
    }
    if (latinWords.length == 1 && trimmed.startsWith(latinWords.first)) {
      return latinWords.first.characters.take(2).toString().toUpperCase();
    }

    return trimmed.characters.take(2).toString();
  }

  IconData _statusIcon(EnthusiasmLevel? level) {
    switch (level) {
      case EnthusiasmLevel.cold:
        return Icons.ac_unit_rounded;
      case EnthusiasmLevel.warm:
        return Icons.auto_awesome_rounded;
      case EnthusiasmLevel.hot:
        return Icons.local_fire_department_rounded;
      case EnthusiasmLevel.veryHot:
        return Icons.favorite_rounded;
      case null:
        return Icons.insights_rounded;
    }
  }

  Widget _buildAvatar() {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.ctaStart, AppColors.brandBlush],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.ctaStart.withValues(alpha: 0.20),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.brandInk.withValues(alpha: 0.90),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Center(
            child: Text(
              _avatarLabel(partner.name),
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(EnthusiasmLevel? level, int? heat) {
    final tone = level?.color ?? Colors.white.withValues(alpha: 0.64);
    final text = heat == null ? '待分析' : '本次投入 $heat';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: heat == null ? 0.08 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: tone.withValues(alpha: heat == null ? 0.12 : 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(level), size: 13, color: tone),
          const SizedBox(width: 5),
          Text(
            text,
            style: AppTypography.caption.copyWith(
              color: heat == null ? Colors.white.withValues(alpha: 0.70) : tone,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailing(String date) {
    return SizedBox(
      width: 64,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            date,
            style: AppTypography.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.50),
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (onDelete != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.delete_outline,
                  color: Colors.white.withValues(alpha: 0.46),
                  size: 22,
                ),
                onPressed: onDelete,
                tooltip: '刪除對象',
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tags = _previewTags(aggregate.unionInterests, aggregate.unionTraits);
    final heat = aggregate.latestHeat;
    final level = heat != null ? EnthusiasmLevel.fromScore(heat) : null;
    final date = _formatDate(aggregate.lastInteraction);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.brandSurface.withValues(alpha: 0.96),
                AppColors.brandSurface2.withValues(alpha: 0.92),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 102),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  _buildAvatar(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partner.name,
                          style: AppTypography.titleMedium.copyWith(
                            color: Colors.white.withValues(alpha: 0.93),
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        _buildStatusPill(level, heat),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            tags.join(' · '),
                            style: AppTypography.bodySmall.copyWith(
                              color: Colors.white.withValues(alpha: 0.62),
                              height: 1.25,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildTrailing(date),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
