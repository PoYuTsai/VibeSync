/// 對象頁的燈號紀錄卡（Eric 2026-10-18）：每次 v3 分析的燈號、決定與邀約進度，新到舊，
/// 相鄰兩筆燈號不同時標「綠 → 黃」。不分方案都看完整紀錄（Bruce PR #97，Eric 2026-10-19
/// 照他決定）：不再有免費只看最新一次、鎖住的預覽與升級鈕。
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis/domain/entities/guide_v3_result.dart';
import '../../../analysis/presentation/sections/guide_v3_result_section.dart';
import '../../domain/services/partner_light_history.dart';

/// 紀錄先列幾筆，其餘按「看全部」再展開。
const kPartnerLightHistoryCollapsedRows = 5;

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
    this.expanded = false,
    this.onToggleExpanded,
  });

  /// 新到舊，至少一筆。
  final List<PartnerLightHistoryEntry> entries;

  /// 紀錄超過 [kPartnerLightHistoryCollapsedRows] 筆時展開了沒有。狀態由頁面持有：
  /// 對象頁是 lazy ListView，卡片自己的 State 捲出去就被回收。
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final invite = entries.first.inviteReadiness;
    final collapsible = entries.length > kPartnerLightHistoryCollapsedRows;
    final visible = collapsible && !expanded
        ? entries.take(kPartnerLightHistoryCollapsedRows).toList()
        : entries;
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
        // 最新一次的邀約進度寫在上面這一行；舊的每筆自己帶。
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
          _HistoryRow(entry: visible[i], showInvite: i > 0),
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
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.showInvite});

  final PartnerLightHistoryEntry entry;
  final bool showInvite;

  @override
  Widget build(BuildContext context) {
    final light = entry.light;
    final previous = entry.previousLight;
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
