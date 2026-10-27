// lib/features/onboarding/presentation/widgets/onboarding_handoff_applier.dart
//
// onboarding 移到登入前（2026-08-18）後的交接收尾：登入前完成 onboarding 時
// 第 1 頁的路徑、目標與目的地暫存在 prefs（OnboardingService.stashPendingHandoff），
// 使用者登入落地 MainShell 時由本 widget 套用——種 profile（沿用 onboarding
// 原規則：只在全空時種、失敗靜默）並 push 目的地。
// onboarding 轉換第 12 步：改成「讀取 → 套用 → 確認成功才清除」
// （OnboardingService.applyPendingHandoff）。套用到一半畫面被拆掉就不清，下次進
// 首頁再套用；以前是讀到就清，中途被打斷交接就不見了。
// 同一時機補送登入前排隊的漏斗事件（onboarding 轉換第 4 步，FunnelTracker）。
// 平常沒有暫存＝no-op，掛在 MainShell 常駐零成本。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/funnel_tracker.dart';
import '../../../user_profile/data/providers/user_profile_providers.dart';
import '../../../user_profile/domain/entities/user_profile.dart';
import '../../data/onboarding_service.dart';

class OnboardingHandoffApplier extends ConsumerStatefulWidget {
  const OnboardingHandoffApplier({super.key});

  @override
  ConsumerState<OnboardingHandoffApplier> createState() =>
      _OnboardingHandoffApplierState();
}

class _OnboardingHandoffApplierState
    extends ConsumerState<OnboardingHandoffApplier> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 登入前排隊的漏斗事件：不等它、也不影響下面的交接。
      unawaited(ref.read(funnelTrackerProvider).flushPending());
      unawaited(OnboardingService.applyPendingHandoff(_apply));
    });
  }

  /// 套用一份交接。回 true＝導頁做完（暫存才會被清掉）；畫面已經拆掉回 false，
  /// 暫存留給下次。種目標是 best-effort：失敗靜默、絕不擋導頁。
  Future<bool> _apply(OnboardingHandoff handoff) async {
    if (!mounted) return false;
    await _seedGoals(handoff.goalNames);
    if (!mounted) return false;
    context.push(handoff.route);
    return true;
  }

  /// 只在 profile 全空時種；照選的順序，認不得的目標名（舊版 enum 名）略過，
  /// 其他照種。
  Future<void> _seedGoals(List<String> goalNames) async {
    final goals = <PracticeGoal>[];
    for (final name in goalNames) {
      for (final goal in PracticeGoal.values) {
        if (goal.name == name && !goals.contains(goal)) goals.add(goal);
      }
    }
    if (goals.isEmpty) return;
    try {
      // notifier 在 App 層的 ProviderScope，先拿好；之後的 await 期間畫面被拆掉
      // 也不會碰到已經 dispose 的 ref。
      final controller = ref.read(userProfileControllerProvider.notifier);
      final existing = await ref.read(userProfileControllerProvider.future);
      if (existing != null && !existing.isEmpty) return;
      await controller.save(
        UserProfile.create(practiceGoals: goals, updatedAt: DateTime.now()),
      );
    } catch (_) {
      // best-effort：種子失敗不影響導頁。
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
