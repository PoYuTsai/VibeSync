import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis_history/data/providers/analysis_history_providers.dart';
import '../../../conversation/data/providers/conversation_archive_providers.dart';
import '../../../conversation/presentation/dialogs/conversation_reassign_picker.dart';
import '../../../conversation/presentation/widgets/new_conversation_sheet.dart';
import '../providers/partner_providers.dart';
import '../utils/conversation_archive_sections.dart';
import '../utils/conversation_record_actions.dart';
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
    final latestAnalysisAtFor = createLazyLatestAnalyzeAtLookup(
      () => ref.read(analysisHistoryRepositoryProvider),
    );
    final sections = partitionConversationsByArchive(
      conversations,
      entryFor: archiveStore.entryFor,
      latestAnalysisAtFor: latestAnalysisAtFor,
    );
    final grouped = _groupByMonth(sections.archived);

    return Scaffold(
      backgroundColor: AppColors.backgroundGradientStart,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
        title: Text(
          partner == null ? '已收起的對話' : '${partner.name}・已收起的對話',
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
                      '完成分析且沒有待處理的新訊息時，整段對話會收在這裡。',
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
                      '這裡收的是整段對話；要補新訊息時，可以重新開啟。每次獨立的 AI 分析片段請從分析頁右上角查看。',
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
                          onReassign: () => showConversationReassignPicker(
                            context,
                            conversation: item.conversation,
                            ref: ref,
                            preservedArchivedAt: item.archivedAt,
                          ),
                          onDelete: () => confirmDeleteConversation(
                            context,
                            ref,
                            item.conversation,
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
