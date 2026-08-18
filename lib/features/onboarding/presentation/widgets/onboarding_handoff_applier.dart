// lib/features/onboarding/presentation/widgets/onboarding_handoff_applier.dart
//
// onboarding 移到登入前（2026-08-18）後的交接收尾：登入前完成 onboarding 時
// 問卷目標與分流目的地暫存在 prefs（OnboardingService.stashPendingHandoff），
// 使用者登入落地 MainShell 時由本 widget 取走——種 profile（沿用 onboarding
// 原規則：只在全空時種、失敗靜默）並 push 分流目的地。
// 平常沒有暫存＝no-op，掛在 MainShell 常駐零成本。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_apply()));
  }

  Future<void> _apply() async {
    final pending = await OnboardingService.takePendingHandoff();
    if (pending == null || !mounted) return;
    try {
      final goals = pending.goalNames
          .map(PracticeGoal.values.byName)
          .toList(growable: false);
      if (goals.isNotEmpty) {
        final existing = await ref.read(userProfileControllerProvider.future);
        if (existing == null || existing.isEmpty) {
          await ref.read(userProfileControllerProvider.notifier).save(
                UserProfile.create(
                  practiceGoals: goals,
                  updatedAt: DateTime.now(),
                ),
              );
        }
      }
    } catch (_) {
      // best-effort：種子失敗（含舊版 enum 名對不上）不影響導頁。
    }
    if (mounted) context.push(pending.route);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
