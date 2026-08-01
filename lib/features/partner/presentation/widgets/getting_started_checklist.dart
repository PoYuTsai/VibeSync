import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/funnel_tracker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../follow_up_notification/data/providers/follow_up_notification_service.dart';
import '../../../follow_up_notification/domain/follow_up_opt_in.dart';
import '../../../onboarding/data/onboarding_service.dart';
import '../../../report/data/providers/report_providers.dart';
import '../../../user_profile/data/providers/user_profile_providers.dart';
import '../providers/partner_providers.dart';

/// Tier 2 批 2：首頁起步清單卡（四項訊號驅動，全完成整卡消失不留殘骸）。
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

    final followUpDone = ref.watch(followUpOptInValueProvider).maybeWhen(
          data: (value) => value == FollowUpOptIn.granted,
          // StreamProvider 首幀 loading：同步 read 兜底，不閃「未完成」假態。
          orElse: () =>
              ref.read(followUpOptInStoreProvider).read() ==
              FollowUpOptIn.granted,
        );

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
        followUpDone: followUpDone,
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
    required bool followUpDone,
    required bool showKeyboardItem,
    required bool keyboardDone,
  }) {
    final items = <_ChecklistItem>[
      _ChecklistItem(
        id: 'profile',
        label: '填 30 秒關於我',
        done: profileDone,
        onTap: () => context.push('/profile/about-me'),
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
      _ChecklistItem(
        id: 'follow_up',
        label: '開啟跟進提醒',
        done: followUpDone,
        onTap: () => context.push('/settings'),
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

    if (items.every((i) => i.done)) return const SizedBox.shrink();

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
