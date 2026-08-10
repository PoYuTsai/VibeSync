// lib/features/learning/presentation/widgets/ebook_stage_funnel.dart
//
// 階段漏斗：五層之中點一層，下方給出診斷與跳章入口。
//
// 為什麼有這個元件（2026-07-26 夥伴回饋）：原本第一章要讀者先記錄六個數字、
// 再讀一段教練示範對話、再答一題算術型 quiz 才知道自己卡在哪。這裡把同一個
// 診斷收斂成一次點選。
//
// 無障礙與韌性約束：
//   - 每一層是 InkWell（點擊與鍵盤 activate 都可選），Semantics 帶 selected。
//   - 層級不能只用寬度差異表達：每層都有可見層號與階段名文字。
//   - 選取狀態除了配色，還加「你在這裡」文字標籤，不只靠顏色。
//   - 寬度用比例而非固定值，窄螢幕與大字級都不裁字；最窄不低於 56%。
//   - 選擇刻意不持久化，這是當下的自我定位而不是進度。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/ebook_block.dart';

class EbookStageFunnelView extends StatefulWidget {
  const EbookStageFunnelView({
    super.key,
    required this.block,
    required this.onOpenTarget,
  });

  final EbookStageFunnelBlock block;

  /// 讀者按下「前往該章節」時呼出。導覽由呼叫端負責，這個 widget 不碰 route。
  final void Function(EbookFunnelStage stage) onOpenTarget;

  /// 選取層的標籤文字。測試與呼叫端共用同一份字串。
  static const String youAreHereLabel = '你在這裡';

  @override
  State<EbookStageFunnelView> createState() => _EbookStageFunnelViewState();
}

class _EbookStageFunnelViewState extends State<EbookStageFunnelView> {
  String? _selectedStageId;

  EbookFunnelStage? get _selected {
    final id = _selectedStageId;
    if (id == null) return null;
    for (final stage in widget.block.stages) {
      if (stage.id == id) return stage;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final stages = widget.block.stages;
    final selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.block.title,
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.block.intro,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundSecondary,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < stages.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.center,
              child: FractionallySizedBox(
                widthFactor: _widthFactorFor(index, stages.length),
                child: _StageRow(
                  stage: stages[index],
                  isSelected: stages[index].id == _selectedStageId,
                  onTap: () => setState(
                    () => _selectedStageId = stages[index].id,
                  ),
                ),
              ),
            ),
          ),
        if (selected != null) ...[
          const SizedBox(height: 6),
          _VerdictCard(
            stage: selected,
            onOpenTarget: () => widget.onOpenTarget(selected),
          ),
        ],
      ],
    );
  }

  /// 漏斗形狀：一層比一層窄，但保留下限避免最後一層被壓成細條。
  static double _widthFactorFor(int index, int total) {
    if (total <= 1) return 1;
    const minFactor = 0.56;
    final step = (1 - minFactor) / (total - 1);
    return 1 - step * index;
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.isSelected,
    required this.onTap,
  });

  final EbookFunnelStage stage;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isSelected ? AppColors.ctaStart : AppColors.onBackgroundSecondary;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${stage.stageName}：${stage.symptom}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.ctaStart.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected
                    ? AppColors.ctaStart.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.14),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    stage.number,
                    style: AppTypography.headlineMedium.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stage.stageName,
                        style: AppTypography.caption.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stage.symptom,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onBackgroundPrimary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.ctaStart.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        EbookStageFunnelView.youAreHereLabel,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({
    required this.stage,
    required this.onOpenTarget,
  });

  final EbookFunnelStage stage;
  final VoidCallback onOpenTarget;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ctaStart.withValues(alpha: 0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location_outlined,
                  size: 16, color: AppColors.ctaStart),
              const SizedBox(width: 6),
              Text(
                '診斷',
                style: AppTypography.caption.copyWith(
                  color: AppColors.ctaStart,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stage.verdictTitle,
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            stage.verdictText,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            button: true,
            label: stage.targetLabel,
            child: Material(
              color: AppColors.ctaStart.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onOpenTarget,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          stage.targetLabel,
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 18, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
