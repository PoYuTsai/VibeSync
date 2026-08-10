import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../providers/partner_providers.dart';

/// 首頁功能入口列（onboarding 轉化 Tier 2 批 1；批 A 改導全域教練）：
/// 開場救援＋問教練。
///
/// 問教練一律導 /coach 全域教練頁（不分有無對象）；埋點字典零改動，
/// coach_entry_tap 照舊帶 has_partner。
class HomeFeatureEntries extends ConsumerWidget {
  const HomeFeatureEntries({super.key});

  static const openerKey = Key('home_entry_opener');
  static const coachKey = Key('home_entry_coach');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: _EntryCard(
              key: HomeFeatureEntries.openerKey,
              icon: Icons.forum_rounded,
              title: '開場救援',
              subtitle: '第一句不知道說什麼',
              onTap: () {
                unawaited(
                  ref.read(funnelTrackerProvider).track('opener_entry_tap'),
                );
                context.push('/opener');
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _EntryCard(
              key: HomeFeatureEntries.coachKey,
              icon: Icons.psychology_rounded,
              title: '問教練',
              subtitle: '聊到一半卡住了',
              onTap: () {
                final partners = ref.read(partnerListProvider);
                unawaited(
                  ref.read(funnelTrackerProvider).track(
                    'coach_entry_tap',
                    properties: {'has_partner': partners.isNotEmpty},
                  ),
                );
                context.push('/coach');
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: AppColors.ctaStart),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
