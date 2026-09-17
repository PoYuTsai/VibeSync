// 開場救星兩段式的畫面區塊（附件 §4.2–§4.6、§9.3）：分析卡、回答區、採用說明、
// 再生成列、到期卡。沿用品牌元件，不重新設計整頁；不放人格分類、好感分數。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/reveal_pill.dart';
import '../../domain/opener_flow_models.dart';

/// 這次可以怎麼開：一句判斷、最多三個可用線索、必要時兩點先避開、判斷依據收合。
class OpenerAnalysisCard extends StatelessWidget {
  const OpenerAnalysisCard({super.key, required this.analysis});

  final OpenerAnalysis analysis;

  static String modeLabel(String mode) => switch (mode) {
        'fresh_topic' => '另開話題',
        'low_info' => '線索不多',
        _ => '接她的線索',
      };

  @override
  Widget build(BuildContext context) {
    final evidence = analysis.cues.where((c) => c.evidence != null).toList(growable: false);
    return BrandSurfaceCard(
      tone: BrandVisualTone.coach,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.explore_outlined, size: 18, color: AppColors.coachAccent),
              const SizedBox(width: 8),
              Text(
                '這次可以怎麼開',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                modeLabel(analysis.approach.mode),
                key: const ValueKey('opener-approach-mode'),
                style: AppTypography.caption.copyWith(color: AppColors.coachAccentBright),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            analysis.approach.summary,
            key: const ValueKey('opener-approach-summary'),
            style: AppTypography.bodyMedium.copyWith(color: AppColors.onBackgroundPrimary, height: 1.5),
          ),
          if (analysis.cues.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('可用線索', style: AppTypography.caption.copyWith(color: AppColors.onBackgroundSecondary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cue in analysis.cues.take(3))
                  Container(
                    key: ValueKey('opener-cue-${cue.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.coachAccent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.coachAccent.withValues(alpha: 0.35)),
                    ),
                    child: Text(cue.label, style: AppTypography.bodySmall.copyWith(color: AppColors.onBackgroundPrimary)),
                  ),
              ],
            ),
          ],
          if (analysis.approach.avoid.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('這次先避開', style: AppTypography.caption.copyWith(color: AppColors.onBackgroundSecondary)),
            const SizedBox(height: 4),
            for (final item in analysis.approach.avoid.take(2))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('・$item', style: AppTypography.bodySmall.copyWith(color: AppColors.onBackgroundSecondary, height: 1.4)),
              ),
          ],
          if (evidence.isNotEmpty) ...[
            const SizedBox(height: 12),
            RevealPill(
              label: '判斷依據',
              children: [
                for (final cue in evidence)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${cue.label}：${cue.evidence!.describe()}',
                      key: ValueKey('opener-evidence-${cue.id}'),
                      style: AppTypography.caption.copyWith(color: AppColors.onBackgroundSecondary, height: 1.4),
                    ),
                  ),
                Text(
                  '看錯了？回上方修改對方資料後重新分析。',
                  style: AppTypography.caption.copyWith(color: AppColors.onBackgroundSecondary.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 回答區：最多一題（不預選）、自由補充（300 字）、可修改的一行摘要、
/// 伺服器報價，與「生成回覆」「略過，直接生成」。
class OpenerContributionCard extends StatelessWidget {
  const OpenerContributionCard({
    super.key,
    required this.analysis,
    required this.draft,
    required this.freeTextController,
    required this.onSelectOption,
    required this.onFreeTextChanged,
    required this.onGenerate,
    required this.onSkip,
    required this.generationsRemaining,
    required this.quotaCharged,
    this.busy = false,
    this.isRegenerating = false,
  });

  final OpenerAnalysis analysis;
  final OpenerContributionDraft draft;
  final TextEditingController freeTextController;
  final ValueChanged<String?> onSelectOption;
  final ValueChanged<String> onFreeTextChanged;
  final VoidCallback onGenerate;
  final VoidCallback onSkip;
  final int generationsRemaining;
  final bool quotaCharged;
  final bool busy;

  /// 從結果回來調整：按鈕文案改「再生成」，且不再提供「略過」。
  final bool isRegenerating;

  /// 生成前的費用提示：伺服器報價（0 或 3），已扣費的同局不再扣。
  static String costHint({
    required int firstGenerationCost,
    required bool quotaCharged,
    required int generationsRemaining,
    required int includedGenerationCount,
  }) {
    if (quotaCharged) {
      return '本局已扣費，還可以再生成 $generationsRemaining 組（共 $includedGenerationCount 組），不會再扣額度';
    }
    if (firstGenerationCost <= 0) {
      return '對方資料不足，這局不扣額度；共 $includedGenerationCount 組回覆';
    }
    return '第一次生成扣 $firstGenerationCost 則，這局共 $includedGenerationCount 組回覆（改想法再生成不再扣）';
  }

  @override
  Widget build(BuildContext context) {
    final question = analysis.question;
    final summary = OpenerContributionSummary.compose(question: question, draft: draft, cues: analysis.cues);
    final count = freeTextController.text.characters.length;
    return BrandSurfaceCard(
      tone: BrandVisualTone.coach,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question != null) ...[
            Text(
              question.text,
              key: const ValueKey('opener-question-text'),
              style: AppTypography.titleSmall.copyWith(color: AppColors.onBackgroundPrimary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in question.options)
                  BrandChoiceChip(
                    key: ValueKey('opener-option-${option.id}'),
                    tone: BrandVisualTone.coach,
                    label: option.label,
                    selected: draft.selectedOptionId == option.id,
                    onTap: busy ? () {} : () => onSelectOption(option.id),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ] else ...[
            Text(
              '原料已經足夠，想補一句也可以',
              style: AppTypography.titleSmall.copyWith(color: AppColors.onBackgroundPrimary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            key: const ValueKey('opener-free-text'),
            controller: freeTextController,
            enabled: !busy,
            maxLines: 3,
            inputFormatters: [
              LengthLimitingTextInputFormatter(OpenerFlowContract.freeTextMaxGraphemes),
            ],
            onChanged: onFreeTextChanged,
            cursorColor: AppColors.coachAccentBright,
            style: AppTypography.bodyMedium.copyWith(color: Colors.white),
            decoration: brandInputDecoration(
              hintText: '寫一句就好，例如你注意到的地方、你知道的事，或你本來想傳的話',
              tone: BrandVisualTone.coach,
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$count / ${OpenerFlowContract.freeTextMaxGraphemes}',
              key: const ValueKey('opener-free-text-counter'),
              style: AppTypography.caption.copyWith(color: AppColors.onBackgroundSecondary.withValues(alpha: 0.7)),
            ),
          ),
          if (summary != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.subject_rounded, size: 16, color: AppColors.coachAccentBright),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    summary,
                    key: const ValueKey('opener-contribution-summary'),
                    style: AppTypography.bodySmall.copyWith(color: AppColors.onBackgroundSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            costHint(
              firstGenerationCost: analysis.firstGenerationCost,
              quotaCharged: quotaCharged,
              generationsRemaining: generationsRemaining,
              includedGenerationCount: analysis.includedGenerationCount,
            ),
            key: const ValueKey('opener-cost-hint'),
            style: AppTypography.caption.copyWith(color: AppColors.onBackgroundSecondary),
          ),
          const SizedBox(height: 10),
          BrandPrimaryButton(
            key: const ValueKey('opener-generate-button'),
            label: busy ? '生成中…' : (isRegenerating ? '用這個想法再生成' : '生成回覆'),
            isLoading: false,
            onPressed: busy || generationsRemaining <= 0 ? null : onGenerate,
          ),
          if (!isRegenerating && !busy && generationsRemaining > 0)
            Center(
              child: TextButton(
                key: const ValueKey('opener-skip-button'),
                onPressed: onSkip,
                style: TextButton.styleFrom(foregroundColor: AppColors.onBackgroundSecondary),
                child: const Text('略過，直接生成'),
              ),
            ),
        ],
      ),
    );
  }
}

/// 推薦句下方的採用說明：只在來源核對 matched 且有 displayNote 時顯示。
class OpenerMaterialUseNote extends StatelessWidget {
  const OpenerMaterialUseNote({super.key, required this.materialUse});

  final OpenerMaterialUse materialUse;

  @override
  Widget build(BuildContext context) {
    final note = materialUse.displayNote;
    if (!materialUse.matched || note == null) return const SizedBox.shrink();
    return BrandSurfaceCard(
      tone: BrandVisualTone.coach,
      padding: const EdgeInsets.all(12),
      elevated: false,
      child: Row(
        children: [
          const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.coachAccentBright),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              key: const ValueKey('opener-material-use-note'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.onBackgroundSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 結果下方的再生成入口（附件 §4.6）：調整想法再生成／不改再抽一組／新的一局。
class OpenerRegenerateBar extends StatelessWidget {
  const OpenerRegenerateBar({
    super.key,
    required this.generationsRemaining,
    required this.includedGenerationCount,
    required this.onAdjust,
    required this.onRegenerate,
    required this.onNewSession,
  });

  final int generationsRemaining;
  final int includedGenerationCount;
  final VoidCallback onAdjust;
  final VoidCallback onRegenerate;
  final VoidCallback onNewSession;

  static String remainingLabel({required int remaining, required int included}) {
    return remaining > 0
        ? '這局還可以再生成 $remaining 組（共 $included 組，不再扣額度）'
        : '這局的 $included 組回覆已用完；重新分析可開始新的一局（3 則）';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          remainingLabel(remaining: generationsRemaining, included: includedGenerationCount),
          key: const ValueKey('opener-generations-remaining'),
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: AppColors.onBackgroundSecondary),
        ),
        const SizedBox(height: 8),
        if (generationsRemaining > 0) ...[
          BrandPrimaryButton(
            key: const ValueKey('opener-adjust-button'),
            label: '調整想法再生成',
            icon: Icons.edit_note_rounded,
            onPressed: onAdjust,
          ),
          Center(
            child: TextButton(
              key: const ValueKey('opener-regenerate-button'),
              onPressed: onRegenerate,
              style: TextButton.styleFrom(foregroundColor: AppColors.ctaStart),
              child: const Text('不改想法，再抽一組'),
            ),
          ),
        ] else
          Center(
            child: TextButton(
              key: const ValueKey('opener-new-session-button'),
              onPressed: onNewSession,
              style: TextButton.styleFrom(foregroundColor: AppColors.ctaStart),
              child: const Text('重新分析，開始新的一局'),
            ),
          ),
      ],
    );
  }
}

/// 分析到期：看已存結果、重新分析；不在背景重新扣費。
class OpenerExpiredCard extends StatelessWidget {
  const OpenerExpiredCard({super.key, required this.onReanalyze});

  final VoidCallback onReanalyze;

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      tone: BrandVisualTone.coach,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '這份分析已到期',
            key: const ValueKey('opener-expired-title'),
            style: AppTypography.titleSmall.copyWith(color: AppColors.onBackgroundPrimary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '已生成的結果還可以看；想再生成請重新分析（新的一局會再計費一次）。',
            style: AppTypography.bodySmall.copyWith(color: AppColors.onBackgroundSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          BrandPrimaryButton(
            key: const ValueKey('opener-reanalyze-button'),
            label: '重新分析',
            onPressed: onReanalyze,
          ),
        ],
      ),
    );
  }
}
