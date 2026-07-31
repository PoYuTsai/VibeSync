// lib/features/learning/presentation/screens/chat_quiz_map_screen.dart
//
// 聊天測驗的關卡地圖。
//
// 解鎖規則：
//   - 群跟群之間全開（第 2 群不必等第 1 群全過）。
//   - 群裡面線性：1-1 過了才開 1-2。這是難度階梯，不是付費牆。
//   - 第 1 期只顯示已有內容的兩群，不畫「即將推出」的佔位（§11 決定 7）。
//
// 付費入口**只在這裡出現一次**，就在第一個鎖住的關卡那一列。答題器、結果頁、
// 學習頁區塊都不放——同一個功能出現三次升級提示，讀起來就是在推銷。
//
// 訂閱狀態還在確認時鎖頭顯示中性 loading，不得出現任何付費文案。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/chat_quiz_providers.dart';
import '../../domain/chat_quiz_access.dart';
import '../../domain/models/chat_quiz.dart';
import '../../domain/models/chat_quiz_progress.dart';
import '../../domain/models/ebook.dart';
import '../widgets/chat_quiz_gate_message.dart';
import '../widgets/ebook_access_gate.dart';

/// 一列關卡在畫面上的狀態。
enum ChatQuizLevelStatus {
  /// 可以進。
  open,

  /// 前一關還沒過（群內線性）。不是付費問題，不顯示升級入口。
  needsPrevious,

  /// 權限不足。
  locked,

  /// 訂閱狀態還在確認。中性 loading，不得顯示付費文案。
  resolving,

  /// 訂閱狀態查不到。
  unavailable,
}

class ChatQuizMapScreen extends ConsumerWidget {
  const ChatQuizMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(chatQuizCatalogProvider);

    return catalog.when(
      loading: () => const ChatQuizGateScaffold(
        title: '聊天測驗',
        child: ChatQuizGateLoading(label: '正在載入關卡…'),
      ),
      error: (error, _) => ChatQuizGateScaffold(
        title: '聊天測驗',
        child: ChatQuizGateMessage(
          icon: Icons.error_outline,
          title: '關卡載入失敗',
          message: '這一批題目暫時讀不到，你的進度不會受影響。',
          primaryLabel: '回學習頁',
          onPrimary: () => context.go('/?tab=learning'),
        ),
      ),
      data: (data) => _ChatQuizMapBody(catalog: data),
    );
  }
}

class _ChatQuizMapBody extends ConsumerWidget {
  const _ChatQuizMapBody({required this.catalog});

  final ChatQuizCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(ebookSubscriptionAccessProvider);
    final progress = ref.watch(chatQuizProgressProvider);

    // 付費入口只出現一次：第一個因為權限而鎖住的關卡那一列。
    var upsellShown = false;

    return ChatQuizGateScaffold(
      title: '聊天測驗',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const _MapIntro(),
          const SizedBox(height: 16),
          for (final group in catalog.groups) ...[
            _GroupHeader(group: group),
            const SizedBox(height: 10),
            for (final level in _visibleLevels(group, subscription)) ...[
              Builder(
                builder: (context) {
                  final status = _statusFor(level, subscription, progress);
                  final showUpsell =
                      status == ChatQuizLevelStatus.locked && !upsellShown;
                  if (showUpsell) upsellShown = true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LevelRow(
                      level: level,
                      status: status,
                      result: progress.resultFor(level.id),
                      showUpsell: showUpsell,
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  /// 這個視角看得到哪些關。
  ///
  /// Essential 取材的關卡在非 Essential 視角**完全不顯示**：對 Starter 來說
  /// 那是「你買的方案不含這個」，在同一條關卡線上掛一排永遠打不開的鎖，
  /// 已經付過錢的人只會覺得被騙。電子書那邊能掛鎖是因為兩個單元分開陳列，
  /// 講得清楚；這裡混在一條線上講不清楚。
  ///
  /// 第 1 期沒有 essential 關卡，所以這條規則現在是空跑，第 2 期才會生效。
  List<ChatQuizLevel> _visibleLevels(
    ChatQuizGroup group,
    EbookSubscriptionAccess subscription,
  ) {
    return [
      for (final level in group.levels)
        if (level.access != EbookAccess.essential || subscription.isEssential)
          level,
    ];
  }

  ChatQuizLevelStatus _statusFor(
    ChatQuizLevel level,
    EbookSubscriptionAccess subscription,
    ChatQuizProgress progress,
  ) {
    final gate = gateForLevel(level, subscription);
    switch (gate) {
      case ChatQuizGate.resolving:
        return ChatQuizLevelStatus.resolving;
      case ChatQuizGate.unavailable:
        return ChatQuizLevelStatus.unavailable;
      case ChatQuizGate.locked:
        return ChatQuizLevelStatus.locked;
      case ChatQuizGate.allowed:
        final previous = catalog.levelBefore(level.id);
        if (previous != null && !progress.isLevelPassed(previous.id)) {
          return ChatQuizLevelStatus.needsPrevious;
        }
        return ChatQuizLevelStatus.open;
    }
  }
}

class _MapIntro extends StatelessWidget {
  const _MapIntro();

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '判讀訓練場',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '一次一題，先讀懂她現在是哪一種，再決定怎麼回。答錯不扣任何東西，'
            '想重跑幾次都可以。',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final ChatQuizGroup group;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.ctaStart.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            group.stageLabel,
            style: AppTypography.caption.copyWith(
              color: AppColors.ctaStart,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.title,
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                group.subtitle,
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.level,
    required this.status,
    required this.result,
    required this.showUpsell,
  });

  final ChatQuizLevel level;
  final ChatQuizLevelStatus status;
  final ChatQuizLevelResult? result;

  /// 這一列是否負責承載整個功能唯一的付費入口。
  final bool showUpsell;

  bool get _enterable => status == ChatQuizLevelStatus.open;

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(16),
      onTap: _enterable
          ? () => context.push('/learning/quiz/levels/${level.id}')
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusBadge(status: status, passed: result?.passed ?? false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${level.number}　${level.title}',
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      level.goal,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                '${level.questionCount} 題',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundSecondary
                      .withValues(alpha: 0.85),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (result != null)
                Text(
                  '最佳 ${result!.correctCount} / ${result!.questionCount}',
                  style: AppTypography.caption.copyWith(
                    color: result!.passed
                        ? AppColors.success
                        : AppColors.onBackgroundSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                _statusText,
                style: AppTypography.caption.copyWith(
                  color: _statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (showUpsell) ...[
            const SizedBox(height: 12),
            BrandPrimaryButton(
              label: '看訂閱方案',
              onPressed: () => context.push('/paywall'),
            ),
          ],
        ],
      ),
    );
  }

  /// 狀態一定要有文字，不能只靠圖示與顏色。
  String get _statusText => switch (status) {
        ChatQuizLevelStatus.open => '可以開始',
        ChatQuizLevelStatus.needsPrevious => '先過上一關',
        ChatQuizLevelStatus.locked => '需要訂閱',
        ChatQuizLevelStatus.resolving => '正在確認你的訂閱狀態…',
        ChatQuizLevelStatus.unavailable => '暫時無法確認訂閱狀態',
      };

  Color get _statusColor => switch (status) {
        ChatQuizLevelStatus.open => AppColors.ctaStart,
        ChatQuizLevelStatus.needsPrevious ||
        ChatQuizLevelStatus.resolving ||
        ChatQuizLevelStatus.unavailable =>
          AppColors.onBackgroundSecondary,
        ChatQuizLevelStatus.locked => AppColors.warning,
      };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.passed});

  final ChatQuizLevelStatus status;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    // resolving 用靜態圖示而不是 spinner：關卡地圖一次會有好幾列，無限旋轉的
    // 動畫會讓整頁永遠不收斂（widget test 的 pumpAndSettle 直接逾時），而且
    // 一排轉圈圈看起來像整頁壞掉。狀態靠旁邊那行文字講清楚。
    final IconData icon = switch (status) {
      ChatQuizLevelStatus.open =>
        passed ? Icons.check_circle_outline : Icons.play_circle_outline,
      ChatQuizLevelStatus.needsPrevious => Icons.lock_clock_outlined,
      ChatQuizLevelStatus.locked => Icons.lock_outline,
      ChatQuizLevelStatus.unavailable => Icons.cloud_off_outlined,
      ChatQuizLevelStatus.resolving => Icons.hourglass_empty,
    };

    final color = switch (status) {
      ChatQuizLevelStatus.open =>
        passed ? AppColors.success : AppColors.ctaStart,
      ChatQuizLevelStatus.locked => AppColors.warning,
      _ => AppColors.onBackgroundSecondary,
    };

    return Icon(icon, size: 22, color: color);
  }
}
