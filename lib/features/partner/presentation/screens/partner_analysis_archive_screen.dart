import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_dialog.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../analysis/data/providers/analysis_record_providers.dart';
import '../../../analysis/data/services/analysis_archive_lifecycle.dart';
import '../../../analysis/domain/entities/analysis_record.dart';
import '../../../analysis_history/data/providers/analysis_history_providers.dart';
import '../../../conversation/data/providers/conversation_archive_providers.dart';
import '../../../conversation/data/providers/conversation_write_controller.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/presentation/dialogs/conversation_reassign_picker.dart';
import '../../../conversation/presentation/widgets/new_conversation_sheet.dart';
import '../providers/partner_providers.dart';
import '../utils/conversation_archive_sections.dart';
import '../utils/conversation_record_actions.dart';
import '../widgets/partner_conversation_tile.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_icons.dart';

class PartnerAnalysisArchiveScreen extends ConsumerStatefulWidget {
  const PartnerAnalysisArchiveScreen({
    super.key,
    required this.partnerId,
  });

  final String partnerId;

  @override
  ConsumerState<PartnerAnalysisArchiveScreen> createState() =>
      _PartnerAnalysisArchiveScreenState();
}

class _PartnerAnalysisArchiveScreenState
    extends ConsumerState<PartnerAnalysisArchiveScreen> {
  /// 批次刪除多選模式（沿用分析紀錄/最近練習的同一套互動）。
  bool _selecting = false;
  final Set<String> _selectedIds = <String>{};
  bool _isDeleting = false;

  void _enterSelection([String? firstId]) {
    if (_isDeleting) return;
    AppHaptics.light();
    setState(() {
      _selecting = true;
      if (firstId != null) _selectedIds.add(firstId);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    if (_isDeleting) return;
    AppHaptics.tap();
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _toggleSelectAll(List<ArchivedConversation> visible) {
    if (_isDeleting) return;
    AppHaptics.tap();
    final ids = visible.map((item) => item.conversation.id).toSet();
    setState(() {
      if (ids.every(_selectedIds.contains)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  /// 逐段走 ConversationWriteController.delete（沿用單段刪的安全語義）；
  /// 中途失敗停在原地，已刪的不回滾（既成事實，跟其他兩處批次刪同規則）。
  Future<void> _deleteSelected(List<Conversation> targets) async {
    if (targets.isEmpty || _isDeleting) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _BatchDeleteArchivedConfirmDialog(count: targets.length),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    final controller = ref.read(conversationWriteControllerProvider.notifier);
    var deleted = 0;
    var failed = false;
    for (final conversation in targets) {
      try {
        await controller.delete(conversation);
      } catch (_) {
        failed = true;
        break;
      }
      deleted += 1;
      if (!mounted) return;
      setState(() => _selectedIds.remove(conversation.id));
    }
    if (!mounted) return;
    setState(() {
      _isDeleting = false;
      if (!failed) {
        _selecting = false;
        _selectedIds.clear();
      }
    });
    if (failed) {
      AppHaptics.failure();
      messenger.showSnackBar(
        SnackBar(content: Text('刪除中斷：已刪 $deleted 段，其餘保留，請再試一次')),
      );
    } else {
      AppHaptics.medium();
      messenger.showSnackBar(
        SnackBar(content: Text('已刪除 $deleted 段互動紀錄')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final partnerId = widget.partnerId;
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
    final ownerUserId = ref.watch(analysisRecordOwnerProvider)?.trim();
    final List<AnalysisRecord> records =
        ownerUserId == null || ownerUserId.isEmpty
            ? const <AnalysisRecord>[]
            : AnalysisArchiveLifecycle.recordsFor(
                store: ref.read(analysisRecordStoreProvider),
                ownerUserId: ownerUserId,
                conversations: conversations,
              );
    final legacyArchived = sections.archived
        .where(
          (item) => !AnalysisArchiveLifecycle.hasStandaloneFragmentRecord(
            conversation: item.conversation,
            records: records,
          ),
        )
        .toList(growable: false);
    final grouped = _groupByMonth(legacyArchived);
    // 清單是 provider 派生的：刪除/改派後 id 會消失，選取集只保留還在的。
    final visibleIds =
        legacyArchived.map((item) => item.conversation.id).toSet();
    final selectedCount = _selectedIds.where(visibleIds.contains).length;
    final allSelected =
        visibleIds.isNotEmpty && visibleIds.every(_selectedIds.contains);

    return BrandScaffold(
      title: _selecting
          ? '已選 $selectedCount 段'
          : partner == null
              ? '已收起的對話'
              : '${partner.name}・已收起的對話',
      actions: [
        if (_selecting) ...[
          _HeaderLinkButton(
            key: const ValueKey('archive-select-all'),
            label: allSelected ? '取消全選' : '全選',
            onTap: _isDeleting ? null : () => _toggleSelectAll(legacyArchived),
          ),
          _HeaderLinkButton(
            key: const ValueKey('archive-select-cancel'),
            label: '取消',
            onTap: _isDeleting ? null : _exitSelection,
          ),
        ] else if (legacyArchived.isNotEmpty)
          _HeaderLinkButton(
            key: const ValueKey('archive-select'),
            label: '選取',
            onTap: _enterSelection,
          ),
      ],
      body: grouped.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '這裡保留舊版整段對話供查看；新內容請另開分析片段。',
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
                  '這裡收的是舊版整段對話，只供查看。新內容請使用「分析新片段」，不會接回舊紀錄。',
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
                      selecting: _selecting,
                      selected: _selectedIds.contains(item.conversation.id),
                      onToggleSelect: () =>
                          _toggleSelected(item.conversation.id),
                      onLongPress: !_selecting && !_isDeleting
                          ? () => _enterSelection(item.conversation.id)
                          : null,
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
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
      bottomNavigationBar: _selecting
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const ValueKey('archive-batch-delete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    disabledBackgroundColor:
                        Colors.white.withValues(alpha: 0.06),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: selectedCount == 0 || _isDeleting
                      ? null
                      : AppHaptics.onPress(() => _deleteSelected([
                            for (final item in legacyArchived)
                              if (_selectedIds.contains(item.conversation.id))
                                item.conversation,
                          ])),
                  child: _isDeleting
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '刪除中…',
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          '刪除（$selectedCount）',
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            )
          : null,
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('archive-new-conversation'),
              onPressed: AppHaptics.onPress(partner == null
                  ? null
                  : () => showAppSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) =>
                            NewConversationSheet(partnerId: widget.partnerId),
                      )),
              backgroundColor: AppColors.ctaStart,
              foregroundColor: AppColors.onCta,
              label: const Text('+ 分析新片段'),
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

/// 標題列右側的小文字鈕（選取／全選／取消），比照分析紀錄 sheet。
class _HeaderLinkButton extends StatelessWidget {
  const _HeaderLinkButton({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: AppColors.ctaStart,
      ),
      child: Text(
        label,
        style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 批次刪除確認框：講清楚幾段、不可復原（比照單段刪的語氣）。
class _BatchDeleteArchivedConfirmDialog extends StatelessWidget {
  const _BatchDeleteArchivedConfirmDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return BrandAlertDialog(
      title: Text('刪除 $count 段互動紀錄？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('選取的整段對話與訊息會永久刪除。'),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(TablerIcons.alert_triangle,
                  size: 15, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 5),
              Text(
                '此操作不可復原',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          key: const ValueKey('archive-batch-delete-confirm'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: AppHaptics.onPress(() => Navigator.of(context).pop(true)),
          child: const Text('確認刪除'),
        ),
      ],
    );
  }
}
