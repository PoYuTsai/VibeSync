import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';

/// 教練拆解卡：練習結束後顯示，唯一一張。聊天中不出現（AI 全程是「她」）。
class PracticeDebriefCard extends StatelessWidget {
  const PracticeDebriefCard({
    super.key,
    required this.summary,
    required this.strengths,
    required this.watchouts,
    required this.suggestedLine,
    required this.vibe,
    this.dateChance,
    this.dateChanceReason,
    this.nextInviteMove,
  });

  final String summary;
  final List<String> strengths;
  final List<String> watchouts;
  final String suggestedLine;
  final String vibe;
  final String? dateChance;
  final String? dateChanceReason;
  final String? nextInviteMove;

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      elevated: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandIconBadge(
                icon: Icons.psychology_alt_outlined,
                size: 34,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Text(
                '教練拆解',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              _VibePill(vibe: vibe),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            summary,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              height: 1.5,
            ),
          ),
          if (strengths.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Section(
              icon: Icons.thumb_up_alt_outlined,
              color: AppColors.success,
              title: '做得不錯',
              items: strengths,
            ),
          ],
          if (watchouts.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Section(
              icon: Icons.adjust,
              color: AppColors.warning,
              title: '可以調整',
              items: watchouts,
            ),
          ],
          if (_hasInviteInsight) ...[
            const SizedBox(height: 14),
            _InviteInsight(
              dateChance: dateChance,
              dateChanceReason: dateChanceReason,
              nextInviteMove: nextInviteMove,
            ),
          ],
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.ctaStart.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.ctaStart.withValues(alpha: 0.30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '下次可以這樣說',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  suggestedLine,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasInviteInsight =>
      (dateChance?.trim().isNotEmpty ?? false) ||
      (dateChanceReason?.trim().isNotEmpty ?? false) ||
      (nextInviteMove?.trim().isNotEmpty ?? false);
}

class _InviteInsight extends StatelessWidget {
  const _InviteInsight({
    this.dateChance,
    this.dateChanceReason,
    this.nextInviteMove,
  });

  final String? dateChance;
  final String? dateChanceReason;
  final String? nextInviteMove;

  String get _chanceLabel {
    switch (dateChance) {
      case 'high':
        return '高';
      case 'medium':
        return '中';
      case 'low':
        return '低';
      default:
        return '未評估';
    }
  }

  @override
  Widget build(BuildContext context) {
    final reason = dateChanceReason?.trim() ?? '';
    final nextMove = nextInviteMove?.trim() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brandSurface2.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryLight.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.flag_outlined,
                size: 16,
                color: AppColors.primaryLight,
              ),
              const SizedBox(width: 6),
              Text(
                '邀約判斷',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '機會 $_chanceLabel',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reason,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.45,
              ),
            ),
          ],
          if (nextMove.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '下一步：$nextMove',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundPrimary,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VibePill extends StatelessWidget {
  const _VibePill({required this.vibe});
  final String vibe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.brandSurface2.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.onBackgroundSecondary.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        '她的感覺：$vibe',
        style: AppTypography.caption.copyWith(
          color: AppColors.onBackgroundSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.color,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final Color color;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: AppTypography.labelMedium.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...items.map(
          (it) => Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 22),
            child: Text(
              '· $it',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
