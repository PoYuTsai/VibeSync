/// v3（任務卡）結果區：燈號＋局面判讀＋任務卡（Eric 2026-10-17：新流程不留雷達、
/// 熱度、階段；先別回時加「要等她做什麼」）。卡一到就畫、就能複製；免費方案看
/// 不到的卡只顯示任務標籤與升級入口。被動 section：資料與動作都由畫面傳進來。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/guide_v3_result.dart';
import '../widgets/guide_v3_task_card.dart';

Color guideV3LightColor(GuideV3Light light) => switch (light) {
      GuideV3Light.green => AppColors.success,
      GuideV3Light.yellow => AppColors.warning,
      GuideV3Light.red => AppColors.error,
    };

String guideV3DecisionTitle(GuideV3Decision decision) => switch (decision) {
      GuideV3Decision.send => '局面判讀',
      GuideV3Decision.close => '這輪收個尾',
      GuideV3Decision.hold => '先別回',
      GuideV3Decision.stop => '先停在這裡',
      GuideV3Decision.care => '先關心安全',
    };

class GuideV3LightChip extends StatelessWidget {
  const GuideV3LightChip({super.key, required this.light});

  final GuideV3Light light;

  @override
  Widget build(BuildContext context) {
    final color = guideV3LightColor(light);
    return Container(
      key: const ValueKey('guide-v3-light'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            light.label,
            style: AppTypography.labelMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 燈號＋判讀（＋要等她做什麼／關心文案）。結果頁與分析紀錄共用。
class GuideV3ReadPanel extends StatelessWidget {
  const GuideV3ReadPanel({super.key, required this.read});

  final GuideV3Read read;

  @override
  Widget build(BuildContext context) {
    final decision = read.decision;
    final isCare = decision == GuideV3Decision.care;
    final accent = switch (decision) {
      GuideV3Decision.care => AppColors.info,
      GuideV3Decision.hold || GuideV3Decision.stop => AppColors.error,
      _ => AppColors.coachAccent,
    };
    final icon = switch (decision) {
      GuideV3Decision.care => TablerIcons.heart_handshake,
      GuideV3Decision.hold || GuideV3Decision.stop => TablerIcons.hand_stop,
      _ => TablerIcons.compass,
    };
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: AppColors.onBackgroundPrimary,
      height: 1.5,
    );
    final light = read.light;
    final waitFor = read.waitFor;
    final careMessage = read.careMessage;
    return Container(
      key: const ValueKey('guide-v3-read'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  guideV3DecisionTitle(decision),
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              // 關心只給固定文案，不放燈號與判讀。
              if (light != null && !isCare) GuideV3LightChip(light: light),
            ],
          ),
          if (isCare && careMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              careMessage,
              key: const ValueKey('guide-v3-care-message'),
              style: bodyStyle,
            ),
          ],
          if (!isCare && read.judgment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              read.judgment,
              key: const ValueKey('guide-v3-judgment'),
              style: bodyStyle,
            ),
          ],
          if (decision == GuideV3Decision.hold && waitFor != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                '等到這時候再回：$waitFor',
                key: const ValueKey('guide-v3-wait-for'),
                style: bodyStyle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class GuideV3ResultSection extends StatelessWidget {
  const GuideV3ResultSection({
    super.key,
    required this.read,
    required this.cards,
    required this.isStreaming,
    this.isFinal = false,
    this.partial = false,
    this.recovered = false,
    required this.editedMessagesFor,
    required this.onCopy,
    required this.onEdit,
    this.onUpgrade,
    this.lockedMessage = guideV3LockedLiveMessage,
    this.footerFor,
    this.anchorKey,
    this.showUpgradeRefresh = false,
    this.refreshBusy = false,
    this.onRefreshAfterUpgrade,
  });

  final GuideV3Read read;

  /// 已送到的卡（照 slot）。
  final List<GuideV3Card> cards;

  /// 還在寫（排好但還沒到的卡顯示「正在寫」）。
  final bool isStreaming;

  /// 已經是最終結果（這時才說「這次比預定的少」；中途斷線還在續看時不說）。
  final bool isFinal;
  final bool partial;
  final bool recovered;
  final List<String>? Function(GuideV3Card card) editedMessagesFor;
  final void Function(GuideV3Card card, String text, String toast) onCopy;
  final void Function(GuideV3Card card) onEdit;
  final VoidCallback? onUpgrade;

  /// 鎖住卡的說法（結果頁與分析紀錄不同，見 [GuideV3LockedCard.message]）。
  final String lockedMessage;
  final Widget? Function(GuideV3Card card)? footerFor;

  /// 分析完成時捲動定位用（第一張卡一到就捲到這裡）。
  final Key? anchorKey;
  final bool showUpgradeRefresh;
  final bool refreshBusy;
  final VoidCallback? onRefreshAfterUpgrade;

  @override
  Widget build(BuildContext context) {
    final decision = read.decision;
    final children = <Widget>[GuideV3ReadPanel(read: read)];
    if (decision.hasCards) {
      final bySlot = {for (final card in cards) card.slot: card};
      final slots = <Widget>[];
      final planned = read.plannedCards.isNotEmpty
          ? read.plannedCards
          : [
              for (final card in cards)
                GuideV3PlannedCard(
                  slot: card.slot,
                  task: card.task,
                  locked: false,
                ),
            ];
      final shownSlots = <int>{};
      for (final plan in planned) {
        final card = bySlot[plan.slot];
        if (card != null) {
          shownSlots.add(card.slot);
          slots.add(_taskCard(card));
        } else if (plan.locked) {
          slots.add(GuideV3LockedCard(
            planned: plan,
            onUpgrade: onUpgrade,
            message: lockedMessage,
          ));
        } else if (isStreaming) {
          slots.add(GuideV3PendingCard(planned: plan));
        }
      }
      // 排卡裡沒有的卡（不該發生）也照樣顯示，不吃掉已送到的內容。
      for (final card in cards) {
        if (!shownSlots.contains(card.slot)) slots.add(_taskCard(card));
      }
      if (slots.isNotEmpty) {
        children
          ..add(const SizedBox(height: 16))
          ..add(Text(
            decision == GuideV3Decision.close ? '收尾這樣說' : '可以這樣回',
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ));
        for (final slot in slots) {
          children
            ..add(const SizedBox(height: 10))
            ..add(slot);
        }
      }
      final fewer = isFinal &&
          (partial || recovered || cards.length < read.deliverableCount);
      if (fewer) {
        children
          ..add(const SizedBox(height: 10))
          ..add(Text(
            recovered ? '連線中斷過，先給你已經寫好的卡。' : '這次比預定的少幾張，已經寫好的可以直接用。',
            key: const ValueKey('guide-v3-partial-note'),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ));
      }
      if (showUpgradeRefresh) {
        children
          ..add(const SizedBox(height: 12))
          ..add(_upgradeRefreshNotice());
      }
    }
    return Column(
      key: anchorKey ?? const ValueKey('guide-v3-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _taskCard(GuideV3Card card) => GuideV3TaskCard(
        card: card,
        editedMessages: editedMessagesFor(card),
        onCopy: (text, toast) => onCopy(card, text, toast),
        onEdit: () => onEdit(card),
        footer: footerFor?.call(card),
      );

  /// 已升級但看的是免費版結果（沿用 v2 的「重新產生完整分析」文案）。
  Widget _upgradeRefreshNotice() {
    return Container(
      key: const ValueKey('guide-v3-upgrade-refresh'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ctaStart.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '你已升級，這份分析仍是免費版結果。',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.ctaStart,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: refreshBusy ? null : onRefreshAfterUpgrade,
              icon: refreshBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(refreshBusy ? '正在刷新完整分析…' : '重新產生完整分析'),
            ),
          ),
        ],
      ),
    );
  }
}
