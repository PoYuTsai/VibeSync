import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/coach_head_avatar.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../providers/partner_providers.dart';

/// 首頁功能入口列（onboarding 轉化 Tier 2 批 1；批 A 改導全域教練）：
/// 開場救星＋問教練。
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        // 夥伴稿：兩個入口左右並排，共用一張 surface，中間只有一條直向 hairline。
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _EntryCard(
                  key: HomeFeatureEntries.openerKey,
                  // 夥伴稿：外框對話泡＋三個「圓」點（textsms_outlined 的點是圓的，
                  // sms_outlined 是方點）。
                  leading: const Icon(
                    Icons.textsms_outlined,
                    size: 32,
                    color: AppColors.ctaStart,
                  ),
                  title: '開場救星',
                  subtitle: '第一句不知道說什麼',
                  onTap: () {
                    unawaited(
                      ref.read(funnelTrackerProvider).track('opener_entry_tap'),
                    );
                    context.push('/opener');
                  },
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Expanded(
                child: _EntryCard(
                  key: HomeFeatureEntries.coachKey,
                  // 夥伴稿：問教練用教練本人的圓形頭像，不是抽象 icon。
                  leading: const CoachHeadAvatar(size: 42),
                  title: '問教練 Sydney',
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
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 42,
                    child:
                        Align(alignment: Alignment.centerLeft, child: leading),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    // 夥伴稿量到 ~17pt（見清單列同註）。
                    style: AppTypography.titleMedium.copyWith(
                      fontSize: 17,
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 13,
                      color: AppColors.onBackgroundSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
