import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/mindmap/mind_map_builder.dart';
import '../../domain/mindmap/mind_map_models.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_mind_map_view.dart';
import 'partner_detail_screen.dart';

/// 對象作戰板全螢幕頁。dogfood 期全 tier 免費（決策 A），
/// 送審前 gating 另案（動訂閱區 → Codex 雙審）。
class PartnerMindMapScreen extends ConsumerWidget {
  final String partnerId;

  const PartnerMindMapScreen({super.key, required this.partnerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerByIdProvider(partnerId));

    if (partner == null) {
      return const Scaffold(
        body: Center(child: Text('找不到對象（可能已被合併或刪除）')),
      );
    }

    final aggregate = ref.watch(partnerAggregateProvider(partnerId));
    final conversations = ref.watch(conversationsByPartnerProvider(partnerId));

    final map = buildPartnerMindMap(
      partnerName: partner.name,
      aggregate: aggregate,
      conversations: conversations,
    );

    return _MindMapBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: Text(
            '${partner.name} 的作戰板',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
        ),
        body: Container(
          decoration: BoxDecoration(
            color: AppColors.brandInk.withValues(alpha: 0.34),
          ),
          child: SafeArea(
            child: map.hasAnalysisData
                ? Column(
                    children: [
                      Expanded(
                        child: PartnerMindMapView(
                          map: map,
                          // nextStep 葉節點 → 對象頁教練跟進區。文案維持「問教練」
                          // affordance，但目的地改到 partner-level 跟進。
                          onNextStepTap: (_) =>
                              _pushCoachFollowUp(context, partnerId),
                        ),
                      ),
                      // 內頁拆解 panel：關係信號 / 可接話題 / 下一步行動全文。
                      // 圖節點只放短標籤，整句教練建議在這裡完整呈現（而非重貼
                      // 詳情頁外層那一句）。
                      _MindMapDetailPanel(
                        map: map,
                        onAskCoach: () => _pushCoachFollowUp(context, partnerId),
                      ),
                    ],
                  )
                : const _EmptyState(),
          ),
        ),
      ),
    );
  }
}

/// 作戰板「問教練」統一導向：回對象頁的教練跟進區並直接開輸入。
/// 圖節點單擊與詳情 panel 的「問教練」按鈕共用同一目的地。
void _pushCoachFollowUp(BuildContext context, String partnerId) {
  context.push(
    Uri(
      path: '/partner/$partnerId',
      queryParameters: {
        PartnerDetailScreen.focusQueryParam:
            PartnerDetailScreen.coachFollowUpFocusValue,
        PartnerDetailScreen.focusActionQueryParam:
            PartnerDetailScreen.openCoachInputFocusActionValue,
      },
    ).toString(),
  );
}

/// 作戰板內頁底部的拆解面板。把「下一步行動全文」與關係信號、可接話題拆開
/// 呈現，而不是在圖節點重貼整句。圖節點只負責導航（問教練）。
class _MindMapDetailPanel extends StatelessWidget {
  final PartnerMindMap map;
  final VoidCallback onAskCoach;

  const _MindMapDetailPanel({required this.map, required this.onAskCoach});

  @override
  Widget build(BuildContext context) {
    final topicsLine = map.topics.isEmpty ? null : map.topics.join(' / ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎯', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                '作戰重點',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (map.relationshipSignal != null) ...[
            const SizedBox(height: 12),
            _DetailRow(label: '關係信號', value: map.relationshipSignal!),
          ],
          if (topicsLine != null) ...[
            const SizedBox(height: 10),
            _DetailRow(label: '可接話題', value: topicsLine),
          ],
          if (map.fullNextStep != null) ...[
            const SizedBox(height: 10),
            _DetailRow(
              label: '下一步行動',
              value: map.fullNextStep!,
              emphasize: true,
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAskCoach,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ctaStart,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  backgroundColor: AppColors.ctaStart.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.forum_outlined, size: 16),
                label: const Text('問教練'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundPrimary,
            height: 1.4,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _MindMapBackground extends StatelessWidget {
  const _MindMapBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.brandInk,
            AppColors.partnerDetailBgTop,
            AppColors.brandSurface,
          ],
          stops: [0.0, 0.48, 1.0],
        ),
      ),
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.brandSurface.withValues(alpha: 0.94),
                AppColors.brandSurface2.withValues(alpha: 0.90),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.ctaStart, AppColors.brandBlush],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.account_tree_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '完成一次對話分析，解鎖她的作戰板',
                textAlign: TextAlign.center,
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
