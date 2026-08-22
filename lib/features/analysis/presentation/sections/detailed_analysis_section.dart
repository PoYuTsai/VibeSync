import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/dimension_radar_chart.dart';
import '../../../../shared/widgets/game_stage_indicator.dart';
import '../../../../shared/widgets/score_hero_card.dart';
import '../../domain/entities/analysis_models.dart';

/// 詳細分析折疊卡（收合狀態的入口）。
///
/// 展開/收起狀態由 screen 持有；本卡只渲染標頭、pills 與展開箭頭，
/// 點擊回呼 [onToggle]。
class DetailedAnalysisToggleCard extends StatelessWidget {
  const DetailedAnalysisToggleCard({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.enthusiasmScore,
    required this.stageLabel,
    required this.hasRadar,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final int? enthusiasmScore;
  final String? stageLabel;
  final bool hasRadar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: expanded ? '收起詳細分析' : '展開詳細分析',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: BrandSurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.ctaStart.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.insights_outlined,
                      color: AppColors.ctaStart,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '詳細分析',
                          style: AppTypography.titleMedium.copyWith(
                            color: AppColors.onBackgroundPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '本次投入、階段、心理訊號與互動雷達',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onBackgroundSecondary,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.ctaStart,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          expanded ? '收起' : '展開',
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: AppMotion.state,
                          curve: AppMotion.easeOut,
                          child: const Icon(
                            Icons.expand_more,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (enthusiasmScore != null)
                    _DetailedAnalysisPill(label: '本次投入 $enthusiasmScore'),
                  if (stageLabel != null)
                    _DetailedAnalysisPill(label: stageLabel!),
                  if (hasRadar) const _DetailedAnalysisPill(label: '互動雷達'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailedAnalysisPill extends StatelessWidget {
  const _DetailedAnalysisPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: AppColors.onBackgroundSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 詳細分析展開內容：本次投入、互動雷達、對話階段、她話裡的意思、
/// 策略、話題深度與對話健檢。
///
/// 訂閱層級以布林旗標傳入（radar 需 premium、健檢需 essential），
/// section 不觸碰 subscription provider。
class DetailedAnalysisContent extends StatelessWidget {
  const DetailedAnalysisContent({
    super.key,
    required this.enthusiasmScore,
    required this.dimensionScores,
    required this.isPremium,
    required this.isEssential,
    required this.gameStage,
    required this.psychology,
    required this.strategy,
    required this.topicDepth,
    required this.healthCheck,
  });

  final int enthusiasmScore;
  final Map<String, int>? dimensionScores;
  final bool isPremium;
  final bool isEssential;
  final GameStageInfo? gameStage;
  final PsychologyAnalysis? psychology;
  final String? strategy;
  final TopicDepth? topicDepth;
  final HealthCheck? healthCheck;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        ScoreHeroCard(
          score: enthusiasmScore,
          // previousScore: null for now
        ),

        // 五維度剖析 (Starter / Essential only)
        if (dimensionScores != null && isPremium) ...[
          const SizedBox(height: 16),
          DimensionRadarChart(
            scores: DimensionScores(
              heat: dimensionScores!['heat'] ?? 50,
              engagement: dimensionScores!['engagement'] ?? 50,
              topicDepth: dimensionScores!['topicDepth'] ?? 50,
              replyWillingness: dimensionScores!['replyWillingness'] ?? 50,
              emotionalConnection:
                  dimensionScores!['emotionalConnection'] ?? 50,
            ),
          ),
        ],

        // 對話階段指示器
        if (gameStage != null) ...[
          const SizedBox(height: 16),
          GameStageIndicator(
            currentStage: gameStage!.current,
            status: gameStage!.status,
            nextStep: gameStage!.nextStep,
          ),
        ],

        // 她話裡的意思
        if (psychology != null) ...[
          const SizedBox(height: 16),
          BrandSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(TablerIcons.brain,
                        size: 18, color: AppColors.primaryLight),
                    const SizedBox(width: 8),
                    Text('她話裡的意思',
                        style: AppTypography.titleMedium
                            .copyWith(color: AppColors.onBackgroundPrimary)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(psychology!.subtext,
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.onBackgroundPrimary)),
                if (psychology!.shitTest != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(TablerIcons.alert_triangle,
                            size: 14, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '互動測試訊號: ${psychology!.shitTest}',
                            style: AppTypography.caption.copyWith(
                                color: AppColors.onBackgroundPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (psychology!.qualificationSignal) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          size: 16, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text('她有主動投入訊號',
                          style: AppTypography.caption.copyWith(
                              color: AppColors.onBackgroundPrimary)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],

        // Strategy
        if (strategy != null && strategy!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          BrandSurfaceCard(
            child: Row(
              children: [
                const Icon(TablerIcons.bulb,
                    size: 20, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strategy!,
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.onBackgroundPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Topic Depth (話題深度)
        if (topicDepth != null) ...[
          const SizedBox(height: 16),
          BrandSurfaceCard(
            child: Row(
              children: [
                Icon(
                    switch (topicDepth!.current) {
                      TopicDepthLevel.event => TablerIcons.news,
                      TopicDepthLevel.personal => TablerIcons.user,
                      TopicDepthLevel.intimate => TablerIcons.hearts,
                    },
                    size: 20,
                    color: AppColors.primaryLight),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('話題深度: ${topicDepth!.current.label}',
                          style: AppTypography.bodyMedium
                              .copyWith(color: AppColors.onBackgroundPrimary)),
                      if (topicDepth!.suggestion.isNotEmpty)
                        Text(topicDepth!.suggestion,
                            style: AppTypography.caption.copyWith(
                                color: AppColors.onBackgroundSecondary
                                    .withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Health Check (對話健檢 - Essential 專屬)
        if (healthCheck != null &&
            isEssential &&
            healthCheck!.issues.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(TablerIcons.stethoscope,
                        size: 18, color: AppColors.info),
                    const SizedBox(width: 8),
                    Text('對話健檢', style: AppTypography.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                ...healthCheck!.issues.map((issue) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber,
                              size: 16, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Expanded(
                              child:
                                  Text(issue, style: AppTypography.bodyMedium)),
                        ],
                      ),
                    )),
                if (healthCheck!.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...healthCheck!.suggestions.map((suggestion) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline,
                                size: 16, color: AppColors.success),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(suggestion,
                                    style: AppTypography.caption)),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
