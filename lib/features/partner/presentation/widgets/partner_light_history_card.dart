/// 對象頁的燈號紀錄卡（Eric 2026-10-18）：每次 v3 分析的燈號、決定與邀約進度，新到舊。
/// Starter 以上看完整紀錄，相鄰兩筆燈號不同時標「綠 → 黃」；免費只看最新一次，有兩次以上
/// 時下面放鎖住的預覽和一顆升級鈕。三個方案的分析一樣，只差這裡顯示多少。最新一次是先別回、
/// 停、關心，或這次比預定的少（少卡、斷線後重組）時不放升級：這些時刻不推銷（盤點報告的
/// 升級時機）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../analysis/domain/entities/guide_v3_result.dart';
import '../../../analysis/presentation/sections/guide_v3_result_section.dart';
import '../../domain/services/partner_light_history.dart';

/// 完整紀錄先列幾筆，其餘按「看全部」再展開。
const kPartnerLightHistoryCollapsedRows = 5;

/// 免費的鎖住預覽最多畫幾列空白示意（不露出真的燈號）。
const _kLockedPreviewRows = 2;

String _decisionLabel(PartnerLightHistoryEntry entry) =>
    switch (entry.decision) {
      GuideV3Decision.send => '該回',
      GuideV3Decision.close => '收尾',
      GuideV3Decision.hold => '先別回',
      GuideV3Decision.stop => '先停',
      GuideV3Decision.care =>
        entry.careKind == GuideV3CareKind.minor ? '不提供建議' : '先確認安全',
      null => '',
    };

String _lightShort(GuideV3Light light) => switch (light) {
      GuideV3Light.green => '綠',
      GuideV3Light.yellow => '黃',
      GuideV3Light.red => '紅',
    };

class PartnerLightHistoryCard extends StatelessWidget {
  const PartnerLightHistoryCard({
    super.key,
    required this.entries,
    required this.fullHistory,
    required this.onUpgrade,
    this.expanded = false,
    this.onToggleExpanded,
  });

  /// 新到舊，至少一筆。
  final List<PartnerLightHistoryEntry> entries;

  /// Starter、Essential 看完整紀錄；免費只看最新一次。
  final bool fullHistory;
  final VoidCallback onUpgrade;

  /// 完整紀錄超過 [kPartnerLightHistoryCollapsedRows] 筆時展開了沒有。狀態由頁面持有：
  /// 對象頁是 lazy ListView，卡片自己的 State 捲出去就被回收。
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final latest = entries.first;
    final invite = latest.inviteReadiness;
    final olderCount = entries.length - 1;
    final collapsible =
        fullHistory && entries.length > kPartnerLightHistoryCollapsedRows;
    final visible = !fullHistory
        ? [latest]
        : collapsible && !expanded
            ? entries.take(kPartnerLightHistoryCollapsedRows).toList()
            : entries;
    // 最新一次比預定的少（少卡、斷線後重組）也跟先別回、停、關心一樣不推升級（主審第 1 輪 P2）。
    final showLocked = !fullHistory &&
        olderCount > 0 &&
        (latest.decision?.hasCards ?? false) &&
        !latest.deliveredFewer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.traffic_outlined,
              size: 20,
              color: AppColors.onBackgroundPrimary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '燈號紀錄',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '燈號只代表那一輪的局面',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
        ),
        // 最新一次的邀約進度大家都看得到；舊的每筆自己帶（完整紀錄）。
        if (invite != null) ...[
          const SizedBox(height: 10),
          Text(
            '邀約進度：${invite.label}',
            key: const ValueKey('partner-light-history-invite'),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _HistoryRow(
            entry: visible[i],
            showInvite: i > 0,
            showChange: fullHistory,
          ),
        ],
        // 跟同頁「詳細特質與趨勢」的展開一樣用白字加箭頭（主題紫在深色卡上對比不夠）。
        if (collapsible)
          TextButton(
            onPressed: onToggleExpanded,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onBackgroundPrimary,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  expanded ? '收起' : '看全部 ${entries.length} 次',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.onBackgroundSecondary,
                ),
              ],
            ),
          ),
        if (showLocked) ...[
          const SizedBox(height: 14),
          _LockedPreview(olderCount: olderCount, onUpgrade: onUpgrade),
        ],
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.showInvite,
    required this.showChange,
  });

  final PartnerLightHistoryEntry entry;
  final bool showInvite;
  final bool showChange;

  @override
  Widget build(BuildContext context) {
    final light = entry.light;
    final previous = showChange ? entry.previousLight : null;
    final decision = _decisionLabel(entry);
    final invite = showInvite ? entry.inviteReadiness : null;
    final detail = [
      if (decision.isNotEmpty) decision,
      if (invite != null) '邀約進度：${invite.label}',
    ].join(' · ');
    final secondary = AppTypography.bodySmall.copyWith(
      color: AppColors.onBackgroundSecondary,
    );
    return Row(
      key: ValueKey('partner-light-history-row-${entry.recordId}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            DateFormat('MM/dd HH:mm').format(entry.analyzedAt.toLocal()),
            style: secondary,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 關心只寫一句，不放燈號與邀約進度。
              if (light != null && !entry.isCare)
                Row(
                  children: [
                    _Dot(color: guideV3LightColor(light)),
                    const SizedBox(width: 6),
                    Text(
                      light.label,
                      style: AppTypography.bodySmall.copyWith(
                        color: guideV3LightColor(light),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (previous != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${_lightShort(previous)} → ${_lightShort(light)}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              if (detail.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(
                    top: light != null && !entry.isCare ? 2 : 0,
                  ),
                  child: Text(
                    detail,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 免費、有兩次以上時：更早幾筆只畫空白示意（不露出真的燈號），一句說明，一顆升級鈕。
class _LockedPreview extends StatelessWidget {
  const _LockedPreview({required this.olderCount, required this.onUpgrade});

  final int olderCount;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final placeholder = Colors.white.withValues(alpha: 0.14);
    Widget bar(double width) => Container(
          width: width,
          height: 10,
          decoration: BoxDecoration(
            color: placeholder,
            borderRadius: BorderRadius.circular(999),
          ),
        );
    return Column(
      key: const ValueKey('partner-light-history-locked'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Column(
            children: [
              for (var i = 0;
                  i < math.min(olderCount, _kLockedPreviewRows);
                  i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    bar(64),
                    const SizedBox(width: 24),
                    _Dot(color: placeholder),
                    const SizedBox(width: 6),
                    bar(36.0 + 28 * i),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: AppColors.onBackgroundSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '還有 $olderCount 次更早的紀錄',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        BrandSecondaryButton(
          label: '升級 Starter 看完整燈號紀錄',
          icon: Icons.workspace_premium_outlined,
          onPressed: onUpgrade,
        ),
      ],
    );
  }
}
