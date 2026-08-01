import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/subscription_providers.dart';

/// 首頁免費額度小條（onboarding 轉化 Tier 2 批 1）。
///
/// 只對免費用戶顯示一行剩餘額度；剩 ≤3 則換醒目色。點擊開說明 sheet，
/// 內含「看訂閱方案」導向 /paywall。付費用戶整條隱藏。
class HomeQuotaStrip extends ConsumerStatefulWidget {
  const HomeQuotaStrip({super.key});

  static const normalKey = Key('home_quota_strip_normal');
  static const urgentKey = Key('home_quota_strip_urgent');

  @override
  ConsumerState<HomeQuotaStrip> createState() => _HomeQuotaStripState();
}

class _HomeQuotaStripState extends ConsumerState<HomeQuotaStrip> {
  @override
  void initState() {
    super.initState();
    _refreshQuotaBestEffort();
  }

  /// best-effort 刷新額度快照；失敗一律吞掉，首頁不因此出錯。
  Future<void> _refreshQuotaBestEffort() async {
    try {
      await ref.read(subscriptionScreenRefreshProvider)();
    } catch (_) {
      // 靜默：額度小條只是快照露出，刷新失敗照舊顯示上次狀態。
    }
  }

  void _openExplainSheet(
    BuildContext context,
    int monthlyLimit, {
    bool isGuest = false,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.brandSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isGuest ? '訪客額度怎麼算？' : '免費額度怎麼算？',
                style: const TextStyle(
                  color: AppColors.onBackgroundPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isGuest
                    ? '訪客共有 $monthlyLimit 則 AI 額度，聊天分析、開場救援、'
                        '教練與練習共用，用完不再補充。免費註冊即可解鎖每月 '
                        '${AppConstants.freeMonthlyLimit} 則額度，'
                        '訪客期間的紀錄全部保留。'
                    : '免費方案每月共 $monthlyLimit 則 AI 額度，聊天分析、開場救援、'
                        '教練與練習共用，每月自動重置。升級後額度大幅提升。',
                style: const TextStyle(
                  color: AppColors.onBackgroundSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              BrandPrimaryButton(
                label: isGuest ? '免費註冊' : '看訂閱方案',
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.push(
                    isGuest ? '/register?source=quota_strip' : '/paywall',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);
    if (!subscription.isFreeUser) return const SizedBox.shrink();

    final remaining = subscription.monthlyRemaining;
    final urgent = subscription.isGuest ? remaining <= 1 : remaining <= 3;
    final accent =
        urgent ? AppColors.ctaStart : AppColors.onBackgroundSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: urgent ? HomeQuotaStrip.urgentKey : HomeQuotaStrip.normalKey,
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            unawaited(ref.read(funnelTrackerProvider).track('quota_strip_tap'));
            _openExplainSheet(
              context,
              subscription.effectiveMonthlyLimit,
              isGuest: subscription.isGuest,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: urgent
                  ? AppColors.ctaStart.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: urgent
                    ? AppColors.ctaStart.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 16, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subscription.isGuest
                        ? '訪客額度剩 $remaining 則'
                        : '本月免費額度還剩 $remaining 則',
                    style: TextStyle(
                      color: urgent
                          ? AppColors.ctaStart
                          : AppColors.onBackgroundPrimary,
                      fontSize: 13,
                      fontWeight: urgent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.info_outline_rounded, size: 15, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
