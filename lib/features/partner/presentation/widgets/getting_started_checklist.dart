import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../onboarding/data/onboarding_service.dart';
import '../../../practice_chat/data/providers/practice_chat_providers.dart';
import '../../../report/data/providers/report_providers.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../user_profile/data/providers/user_profile_providers.dart';
import '../providers/partner_providers.dart';

/// Tier 2 批 2：首頁起步清單卡（訊號驅動，全完成整卡消失不留殘骸）。
/// 2026-08-01 起縮為三項（iOS）／兩項（Android）：跟進提醒項移除（功能仍在設定頁）。
///
/// 訊號全部讀既有 provider／service，本卡不寫任何狀態；
/// 每項首次變成完成時打一發 `checklist_item_done`（per-item once-flag）。
class GettingStartedChecklist extends ConsumerWidget {
  const GettingStartedChecklist({super.key});

  static const cardKey = Key('getting_started_checklist');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileControllerProvider).valueOrNull;
    final profileDone = profile != null && !profile.isEmpty;

    final historyEvents = ref.watch(analysisHistoryEventsProvider);
    final practicePoints = ref.watch(practiceTemperatureTrendProvider);
    final firstActionDone =
        historyEvents.isNotEmpty || practicePoints.isNotEmpty;

    // 鍵盤僅 iOS（foundation 顯式 import——CI dart2js 教訓）。
    final showKeyboardItem = defaultTargetPlatform == TargetPlatform.iOS;

    // 鍵盤完成態走 ValueListenable：設定流程 pop 回首頁時本 widget 不重掛，
    // 靜態同步讀會 stale（比照 follow_up 的 stale bug 教訓）。
    return ValueListenableBuilder<bool>(
      valueListenable: OnboardingService.keyboardCompletedListenable,
      builder: (context, keyboardDone, _) => _buildCard(
        context,
        ref,
        profileDone: profileDone,
        firstActionDone: firstActionDone,
        showKeyboardItem: showKeyboardItem,
        keyboardDone: keyboardDone,
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref, {
    required bool profileDone,
    required bool firstActionDone,
    required bool showKeyboardItem,
    required bool keyboardDone,
  }) {
    final items = <_ChecklistItem>[
      _ChecklistItem(
        id: 'profile',
        label: '填 30 秒關於我',
        done: profileDone,
        onTap: () => context.push('/profile/about-me?source=checklist'),
      ),
      _ChecklistItem(
        id: 'first_action',
        label: '完成第一次分析或練習',
        done: firstActionDone,
        onTap: () {
          final partners = ref.read(partnerListProvider);
          context.push(
            partners.isEmpty ? '/partner/new' : '/partner/${partners.first.id}',
          );
        },
      ),
      if (showKeyboardItem)
        _ChecklistItem(
          id: 'keyboard',
          label: '設定 AI 鍵盤',
          done: keyboardDone,
          onTap: () => context.push('/settings/keyboard'),
        ),
    ];

    // 每項首次完成打一發（per-item once-flag，best-effort）。
    final tracker = ref.read(funnelTrackerProvider);
    for (final item in items.where((i) => i.done)) {
      unawaited(
        tracker.trackOnce(
          'checklist_item_done',
          properties: {'item': item.id},
          onceKey: 'checklist_item_done_${item.id}',
        ),
      );
    }

    // 全完成 → 變身一次性贈抽領獎卡（贈抽消耗後才永久消失）。
    if (items.every((i) => i.done)) {
      return const OnboardingDrawRewardCard();
    }

    final doneCount = items.where((i) => i.done).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: GettingStartedChecklist.cardKey,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '起步清單',
                    style: AppTypography.titleSmall.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$doneCount/${items.length}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final item in items) _ChecklistRow(item: item),
          ],
        ),
      ),
    );
  }
}

/// 起步清單全完成的一次性贈抽狀態。呼叫即 grant（server 冪等），回傳
/// consumed：true=已用掉。autoDispose：離開首頁重進會重查（抽完回來卡片即消失）。
final onboardingDrawBonusConsumedProvider =
    FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(practiceChatApiServiceProvider).grantOnboardingDrawBonus();
});

const _drawRewardDismissedKeyPrefix = 'onboarding_draw_reward_dismissed_v1_';

/// 領獎卡一次性收起旗標（per-uid 本機）。卡片與贈抽消耗刻意脫鉤（Eric 拍板
/// 2026-08-02 丙案）：點過「去抽卡」回首頁即永久收起；付費 tier 的贈抽仍以
/// 懶消耗默默留在額度裡自動兌現。重裝/換機時退回看 server consumed
///（free 抽過＝consumed 亦會收，付費最壞情況＝再看到一次卡片，無害）。
final onboardingDrawRewardDismissedProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final uid = SupabaseService.currentUser?.id;
  if (uid == null) return false;
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('$_drawRewardDismissedKeyPrefix$uid') ?? false;
});

Future<void> _markDrawRewardDismissed() async {
  final uid = SupabaseService.currentUser?.id;
  if (uid == null) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('$_drawRewardDismissedKeyPrefix$uid', true);
}

/// 起步清單全完成 → 領獎卡：送一次免費抽卡＋導練習室圖鑑（功能導覽一石二鳥）。
/// 贈抽已消耗（或狀態拿不到）→ 整卡消失，不擋首頁。
class OnboardingDrawRewardCard extends ConsumerWidget {
  const OnboardingDrawRewardCard({super.key});

  static const cardKey = Key('onboarding_draw_reward_card');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 丙案：抽過一次回首頁即永久收起（本機旗標），與贈抽消耗脫鉤。
    final dismissed =
        ref.watch(onboardingDrawRewardDismissedProvider).valueOrNull ?? false;
    if (dismissed) return const SizedBox.shrink();

    final consumed = ref.watch(onboardingDrawBonusConsumedProvider);
    // 已消耗 → 永久消失；loading 一幀不佔版面；error 必須給「重試」出口
    //（Codex P2：provider 停在 error 不會自己重跑，藏卡＝把可領的獎藏死）。
    if (consumed.valueOrNull == true || consumed.isLoading) {
      return const SizedBox.shrink();
    }
    final isError = consumed.hasError;
    // 分身份文案：free 的獎勵是「馬上能抽的那張」；付費的獎勵是「疊在每日
    // 額度後的 +1」，領卡當下講清楚，之後兌現無感（懶消耗自動生效）。
    final isPremium = ref.watch(subscriptionProvider).isPremium;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: OnboardingDrawRewardCard.cardKey,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.brandFlame.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.brandFlame.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPremium ? '🎉 起步完成！加送你 1 次翻牌機會' : '🎉 起步完成！送你一次免費抽卡',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isError
                  ? '獎勵狀態載入失敗，點一下重試。'
                  : isPremium
                      ? '已加進你的翻牌額度——每日免費次數用完後，還能多翻一張。'
                      : '到 AI 練習室翻一張角色卡，馬上開始實戰演練。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
            const SizedBox(height: 12),
            BrandPrimaryButton(
              label: isError ? '重試' : '去抽卡',
              onPressed: () {
                if (isError) {
                  ref.invalidate(onboardingDrawBonusConsumedProvider);
                  return;
                }
                unawaited(
                  context.push('/practice-collection').whenComplete(() async {
                    // 回首頁即永久收起（丙案）；贈抽本身不受影響。
                    await _markDrawRewardDismissed();
                    if (!context.mounted) return;
                    ref.invalidate(onboardingDrawRewardDismissedProvider);
                    ref.invalidate(onboardingDrawBonusConsumedProvider);
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistItem {
  const _ChecklistItem({
    required this.id,
    required this.label,
    required this.done,
    required this.onTap,
  });

  final String id;
  final String label;
  final bool done;
  final VoidCallback onTap;
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.item});

  final _ChecklistItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: item.done ? null : item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
              item.done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              key: item.done ? Key('checklist_done_${item.id}') : null,
              size: 18,
              color: item.done
                  ? AppColors.success
                  : Colors.white.withValues(alpha: 0.35),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: AppTypography.bodyMedium.copyWith(
                  color: item.done
                      ? AppColors.onBackgroundSecondary
                      : AppColors.onBackgroundPrimary,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                  decorationColor: AppColors.onBackgroundSecondary,
                ),
              ),
            ),
            if (!item.done)
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.4),
              ),
          ],
        ),
      ),
    );
  }
}
