import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis_history/data/providers/analysis_history_providers.dart';
import '../../../conversation/data/providers/conversation_archive_providers.dart';
import '../../../conversation/presentation/widgets/new_conversation_sheet.dart';
import '../providers/partner_providers.dart';
import '../utils/conversation_archive_sections.dart';
import '../widgets/partner_conversation_tile.dart';

class PartnerAnalysisArchiveScreen extends ConsumerWidget {
  const PartnerAnalysisArchiveScreen({
    super.key,
    required this.partnerId,
  });

  final String partnerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerByIdProvider(partnerId));
    final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
    ref.watch(conversationArchiveControllerProvider);
    final archiveStore = ref.watch(conversationArchiveStoreProvider);
    final sections = partitionConversationsByArchive(
      conversations,
      entryFor: archiveStore.entryFor,
      latestAnalysisAtFor: (conversationId) {
        try {
          return latestAnalyzeEventAt(
            ref
                .read(analysisHistoryRepositoryProvider)
                .listByConversation(conversationId, limit: 1),
          );
        } catch (_) {
          // Fail open: unavailable legacy history must never hide a current
          // conversation from the partner page.
          return null;
        }
      },
    );
    final grouped = _groupByMonth(sections.archived);

    return Scaffold(
      backgroundColor: AppColors.backgroundGradientStart,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
        title: Text(
          partner == null ? '分析紀錄' : '${partner.name}的分析紀錄',
          style: const TextStyle(color: AppColors.onBackgroundPrimary),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.backgroundGradientStart,
              AppColors.backgroundGradientMid,
              AppColors.backgroundGradientEnd,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: grouped.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '完成一次分析後，對話會自動收在這裡。',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.onBackgroundSecondary,
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    Text(
                      '已完成的分析與目前對話分開保存；要補新訊息時，可重新開啟該段。',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final group in grouped.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Text(
                          group.key,
                          style: AppTypography.titleSmall.copyWith(
                            color: AppColors.onBackgroundPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (final item in group.value) ...[
                        PartnerConversationTile(
                          conversation: item.conversation,
                          onTap: () => context.push(
                            '/conversation/${item.conversation.id}',
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: ValueKey(
                              'archive-continue-${item.conversation.id}',
                            ),
                            onPressed: () async {
                              await ref
                                  .read(conversationArchiveControllerProvider
                                      .notifier)
                                  .markActive(item.conversation);
                              if (context.mounted) {
                                context.push(
                                  '/conversation/${item.conversation.id}',
                                );
                              }
                            },
                            icon: const Icon(Icons.edit_note_rounded),
                            label: const Text('繼續這一段'),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('archive-new-conversation'),
        onPressed: partner == null
            ? null
            : () => showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) => NewConversationSheet(partnerId: partnerId),
                ),
        backgroundColor: AppColors.ctaStart,
        foregroundColor: Colors.white,
        label: const Text('+ 新增對話'),
      ),
    );
  }

  static Map<String, List<ArchivedConversation>> _groupByMonth(
    List<ArchivedConversation> archived,
  ) {
    final grouped = <String, List<ArchivedConversation>>{};
    for (final item in archived) {
      final date = item.archivedAt.toLocal();
      final label = '${date.year} 年 ${date.month} 月';
      grouped.putIfAbsent(label, () => []).add(item);
    }
    return grouped;
  }
}
