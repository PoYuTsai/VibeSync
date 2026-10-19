/// v3 結果頁「關係狀態」卡（Bruce 2026-10-19 路線二，選的是 A3）：放在局面判讀下面，
/// 燈號、她這一輪在做什麼、回覆意願、邀約進度、關係階段；熱度與五維雷達收在「詳細」裡，
/// 沿用 v2 的分數卡與雷達圖。只有判讀帶了關係狀態（伺服器開關開著）才畫，沒有的欄位不畫。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/dimension_radar_chart.dart';
import '../../../../shared/widgets/game_stage_indicator.dart';
import '../../../../shared/widgets/score_hero_card.dart';
import '../../domain/entities/guide_v3_result.dart';
import '../sections/guide_v3_result_section.dart' show guideV3LightColor;

/// 邀約進度的白話：還沒提過見面另外說（讀局面的類別名「沒機會」聽起來像判死刑），
/// 其他沿用 App 既有的標籤。
String guideV3InviteProgressLabel(GuideV3InviteReadiness readiness) =>
    readiness == GuideV3InviteReadiness.none ? '還沒提過見面' : readiness.label;

class GuideV3RelationCard extends StatefulWidget {
  const GuideV3RelationCard({
    super.key,
    required this.read,
    required this.relation,
    this.reconnectWording = false,
    this.showRadar = true,
  });

  final GuideV3Read read;
  final GuideV3Relation relation;

  /// 已是伴侶時 opening 的可見語意是「重新連線」（閉環規則 5），跟 v2 的階段卡同一條。
  final bool reconnectWording;

  /// 五維雷達照 v2 結果頁：只有付費方案看得到；分析紀錄不分方案。
  final bool showRadar;

  @override
  State<GuideV3RelationCard> createState() => _GuideV3RelationCardState();
}

class _GuideV3RelationCardState extends State<GuideV3RelationCard> {
  bool _detailOpen = false;

  @override
  Widget build(BuildContext context) {
    final relation = widget.relation;
    final light = widget.read.light;
    final invite = widget.read.inviteReadiness;
    final heat = relation.visibleHeat;
    final dimensions = widget.showRadar ? relation.dimensions : null;
    final rows = <Widget>[
      if (light != null) _row('燈號', _LightValue(light: light)),
      if (relation.herMove case final herMove?)
        _row('她這一輪在做什麼', _value(herMove.label)),
      if (relation.willingness case final willingness?)
        _row('回覆意願', _value(willingness.label)),
      if (invite != null)
        _row('邀約進度', _value(guideV3InviteProgressLabel(invite))),
    ];
    final stage = relation.stage;
    return Container(
      key: const ValueKey('guide-v3-relation'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.brandInk.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                TablerIcons.heart_handshake,
                size: 20,
                color: AppColors.coachAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '關係狀態',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (rows.isNotEmpty) const SizedBox(height: 8),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const _Hairline(),
            rows[i],
          ],
          if (stage != null) ...[
            const SizedBox(height: 12),
            Text(
              '關係階段',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
            const SizedBox(height: 8),
            GameStageIndicator(
              key: const ValueKey('guide-v3-relation-stage'),
              currentStage: stage,
              // v3 只有階段，沒有 v2 的「節奏」。
              status: null,
              reconnectWording: widget.reconnectWording,
            ),
          ],
          if (heat != null || dimensions != null) ...[
            const SizedBox(height: 8),
            _detailToggle(hasHeat: heat != null, hasRadar: dimensions != null),
            if (_detailOpen) ...[
              if (heat != null) ...[
                const SizedBox(height: 8),
                ScoreHeroCard(score: heat),
              ],
              if (dimensions != null) ...[
                const SizedBox(height: 12),
                DimensionRadarChart(
                  key: const ValueKey('guide-v3-relation-radar'),
                  scores: DimensionScores(
                    heat: dimensions['heat']!,
                    engagement: dimensions['engagement']!,
                    topicDepth: dimensions['topicDepth']!,
                    replyWillingness: dimensions['replyWillingness']!,
                    emotionalConnection: dimensions['emotionalConnection']!,
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  /// 「詳細」：點了展開熱度與五維雷達（跟 v2 的詳細分析一樣先收著）。點擊區至少 44 高。
  Widget _detailToggle({required bool hasHeat, required bool hasRadar}) {
    final contents = [if (hasHeat) '熱度', if (hasRadar) '五維雷達'].join('・');
    return Semantics(
      button: true,
      expanded: _detailOpen,
      label: '詳細：$contents',
      hint: _detailOpen ? '點兩下收起' : '點兩下展開',
      excludeSemantics: true,
      onTap: _toggleDetail,
      child: InkWell(
        key: const ValueKey('guide-v3-relation-detail'),
        onTap: _toggleDetail,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Text(
                '詳細',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.coachAccentBright,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  contents,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: _detailOpen ? 0.5 : 0,
                duration: AppMotion.state,
                curve: AppMotion.easeOut,
                child: const Icon(
                  Icons.expand_more,
                  size: 20,
                  color: AppColors.coachAccentBright,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleDetail() => setState(() => _detailOpen = !_detailOpen);

  /// 一列：左邊標籤、右邊值；讀屏念成一句（「回覆意願 她很想聊」）。
  Widget _row(String label, Widget value) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
            ),
            Expanded(child: value),
          ],
        ),
      ),
    );
  }

  Widget _value(String text) => Text(
        text,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.onBackgroundPrimary,
          fontWeight: FontWeight.w700,
        ),
      );
}

class _LightValue extends StatelessWidget {
  const _LightValue({required this.light});

  final GuideV3Light light;

  @override
  Widget build(BuildContext context) {
    final color = guideV3LightColor(light);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            light.label,
            style: AppTypography.bodyMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: Colors.white.withValues(alpha: 0.08));
}
