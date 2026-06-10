import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/mindmap/mind_map_builder.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_mind_map_view.dart';

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
    final conversations =
        ref.watch(conversationsByPartnerProvider(partnerId));

    final map = buildPartnerMindMap(
      partnerName: partner.name,
      aggregate: aggregate,
      conversations: conversations,
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '${partner.name} 的作戰板',
          style: AppTypography.titleMedium
              .copyWith(color: AppColors.onBackgroundPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.partnerDetailBgTop,
              AppColors.partnerDetailBgBottom,
            ],
          ),
        ),
        child: SafeArea(
          child: map.hasAnalysisData
              ? PartnerMindMapView(map: map)
              : const _EmptyState(),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗺️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              '完成一次對話分析，解鎖她的作戰板',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}
