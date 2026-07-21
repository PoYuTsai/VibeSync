// lib/features/partner/presentation/screens/partner_detail_screen.dart
//
// Partner detail — post-A2 visual polish (2026-04-28).
// Mood: 深夜陪你讀懂這段關係，不是冷冰冰的 dashboard。
//
// Visual pattern:
//  - Transparent Scaffold + extendBodyBehindAppBar so the dark navy
//    backdrop sits under the AppBar (mirrors the AddPartner screen).
//  - Background = vertical gradient (very dark navy) + 3 STATIC glow
//    bubbles (no AnimationController — keeps widget tests pumpAndSettle-safe).
//  - PartnerHeatHeroCard reads `aggregate.latestHeat` only —
//    NO synthesized score, NO AI insight (per scope lock).
//  - Spec 6D shifts the page from dashboard-first to command-center-first:
//    summary → heat → records → next step → coach/style → detailed data.
//
// Stable behavior:
//  - ⋮ menu (merge / edit / delete-即將推出) — see partner_detail_screen_test.
//  - FAB still opens NewConversationSheet(partnerId).
//  - Partner-bound entry starts one independent analysis fragment.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_dialog.dart';
import '../../../../shared/widgets/brand/brand_feedback_snack_bar.dart';
import '../../../analysis/data/providers/analysis_record_providers.dart';
import '../../../analysis/data/services/analysis_archive_lifecycle.dart';
import '../../../analysis/domain/entities/analysis_record.dart';
import '../../../analysis/presentation/screens/partner_analysis_records_screen.dart';
import '../../../analysis_history/data/providers/analysis_history_providers.dart';
import '../../../conversation/data/providers/conversation_archive_providers.dart';
import '../../../conversation/data/providers/conversation_write_controller.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/presentation/dialogs/conversation_reassign_picker.dart';
import '../../../analysis/data/providers/analysis_providers.dart';
import '../../../analysis/domain/entities/analysis_models.dart';
import '../../../coach_follow_up/domain/entities/coach_follow_up_phase.dart';
import '../../../coach_follow_up/presentation/widgets/coach_follow_up_section.dart';
import '../../../conversation/presentation/widgets/new_conversation_sheet.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../../user_profile/domain/entities/partner_data_quality_state.dart';
import '../../../user_profile/domain/services/name_candidate_extractor.dart';
import '../../../user_profile/presentation/widgets/partner_style_entry_card.dart';
import '../../data/providers/partner_write_controller.dart';
import '../../domain/entities/partner.dart';
import '../../domain/extensions/partner_aggregates.dart';
import '../../domain/mindmap/mind_map_builder.dart';
import '../../domain/mindmap/partner_insight_presentation.dart';
import '../dialogs/partner_settings_dialog.dart';
import '../providers/partner_providers.dart';
import '../utils/conversation_archive_sections.dart';
import '../utils/conversation_record_actions.dart';
import '../widgets/partner_conversation_tile.dart';
import '../widgets/partner_data_quality_banner.dart';
import '../widgets/partner_heat_hero_card.dart';
import '../widgets/partner_mind_map_entry_card.dart';
import '../widgets/partner_radar_summary_card.dart';
import '../widgets/partner_traits_card.dart';

class PartnerDetailScreen extends ConsumerStatefulWidget {
  static const focusQueryParam = 'focus';
  static const coachFollowUpFocusValue = 'coachFollowUp';
  static const focusActionQueryParam = 'focusAction';
  static const openCoachInputFocusActionValue = 'openCoachInput';

  final String partnerId;
  final bool focusCoachFollowUp;
  final bool openCoachInputOnFocus;

  const PartnerDetailScreen({
    super.key,
    required this.partnerId,
    this.focusCoachFollowUp = false,
    this.openCoachInputOnFocus = false,
  });

  @override
  ConsumerState<PartnerDetailScreen> createState() =>
      _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends ConsumerState<PartnerDetailScreen> {
  // Owned here (NOT created in build) so the controller + anchor handles
  // survive rebuilds. The mind-map「下一步」node routes in with
  // focusCoachFollowUp (and optionally openCoachInputOnFocus). Because the
  // body is a LAZY ListView, the coach section is not laid out while it sits
  // below the viewport + cacheExtent — so the scroll MUST be driven from
  // outside the list by a ScrollController that converges on the anchor even
  // before it is built. That orchestration, plus the "position before open"
  // invariant, lives in [_CoachFocusOrchestrator].
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _coachAnchorKey = GlobalKey();
  final GlobalKey _coachSectionKey = GlobalKey();

  // Phase E Task 7: deep-link focusAction=openCoachInput no longer opens the
  // legacy input sheet (it charged via the legacy controller while the new UI
  // renders no legacy result card). The orchestrator instead reports the
  // intent here after positioning; flipping this flag re-renders the section
  // with openCoachInputOnFirstBuild=true, whose false→true transition bumps
  // the CoachSurface focus token (section's existing focus mechanism).
  bool _openCoachInputRequested = false;

  @override
  void didUpdateWidget(covariant PartnerDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.partnerId != oldWidget.partnerId) {
      // New partner → the orchestrator restarts; don't leak a stale intent.
      _openCoachInputRequested = false;
    }
  }

  void _handleOpenCoachInputRequested() {
    if (!mounted || _openCoachInputRequested) return;
    setState(() => _openCoachInputRequested = true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final partnerId = widget.partnerId;
    final partner = ref.watch(partnerByIdProvider(partnerId));
    final aggregate = ref.watch(partnerAggregateProvider(partnerId));
    final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
    ref.watch(conversationArchiveControllerProvider);
    final archiveStore = ref.watch(conversationArchiveStoreProvider);
    final latestAnalysisAtFor = createLazyLatestAnalyzeAtLookup(
      () => ref.read(analysisHistoryRepositoryProvider),
    );
    final conversationSections = partitionConversationsByArchive(
      conversations,
      entryFor: archiveStore.entryFor,
      latestAnalysisAtFor: latestAnalysisAtFor,
    );
    final analysisRecordOwner = ref.watch(analysisRecordOwnerProvider)?.trim();
    final archivedAnalysisRecords = _listArchivedAnalysisRecords(
      conversations: conversations,
      ownerUserId: analysisRecordOwner,
    );
    final legacyArchivedConversationCount = conversationSections.archived
        .where(
          (item) => !AnalysisArchiveLifecycle.hasStandaloneFragmentRecord(
            conversation: item.conversation,
            records: archivedAnalysisRecords,
          ),
        )
        .length;
    final partners = ref.watch(partnerListProvider);
    final hasOtherPartner = partners.any((p) => p.id != partnerId);

    if (partner == null) {
      return const Scaffold(
        body: Center(child: Text('找不到對象（可能已被合併或刪除）')),
      );
    }

    // Read AFTER the null-check: when the partner has been deleted/merged,
    // there's no surface to show the banner on, so we avoid touching the
    // data-quality repo (and the Hive box) entirely. Mirrors the no-op
    // shape of the partnerStyleEntryCard placement.
    final dataQualityFlag = ref.watch(dataQualityFlagProvider(partnerId));

    if (conversations.isEmpty) {
      return _buildEmptyStateScaffold(
        context: context,
        ref: ref,
        partner: partner,
        dataQualityFlag: dataQualityFlag,
        hasOtherPartner: hasOtherPartner,
        archivedAnalysisCount: archivedAnalysisRecords.length,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: AppColors.onBackgroundPrimary,
        ),
        title: Text(
          partner.name,
          style: const TextStyle(color: AppColors.onBackgroundPrimary),
        ),
        actions: [
          AnalysisRecordsEntryButton(
            key: const ValueKey('partner-analysis-records-entry'),
            archivedCount: archivedAnalysisRecords.length,
            onPressed: () => _openPartnerAnalysisRecords(
              partner: partner,
              conversations: conversations,
              archivedConversationCount: legacyArchivedConversationCount,
            ),
          ),
          IconButton(
            tooltip: '對象設定',
            onPressed: () => _onEditPartnerSettings(context, ref, partner),
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.onBackgroundPrimary,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              color: AppColors.onBackgroundPrimary,
            ),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'merge',
                enabled: hasOtherPartner,
                child: Text(hasOtherPartner ? '合併重複對象' : '合併重複對象（需至少 2 個對象）'),
              ),
            ],
            onSelected: (v) {
              if (v == 'merge') context.push('/partner/$partnerId/merge');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _PartnerDetailBackground()),
          SafeArea(
            child: ListView(
              controller: _scrollController,
              // SafeArea already keeps the content out of the transparent
              // toolbar zone on device. Do not add another top inset here, or
              // the hero card leaves a visible dead shelf under the title.
              // Bottom inset clears the extended FAB (pill ~48 + 16 margin) so
              // the last card / banner is never hidden behind it.
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              children: [
                _PartnerCommandSummaryCard(
                  partner: partner,
                  aggregate: aggregate,
                  conversations: conversations,
                ),
                const SizedBox(height: 14),
                PartnerHeatHeroCard(heat: aggregate.latestHeat),
                const SizedBox(height: 12),
                PartnerMindMapEntryCard(
                  map: buildPartnerMindMap(
                    partnerName: partner.name,
                    aggregate: aggregate,
                    conversations: conversations,
                  ),
                  onTap: () => context.push('/partner/$partnerId/mindmap'),
                ),
                const SizedBox(height: 12),
                ..._conversationRecordWidgets(
                  context,
                  ref,
                  conversationSections,
                ),
                const SizedBox(height: 12),
                _PartnerNextStepCard(
                  latestInsight: _PartnerLatestInsight.fromConversations(
                    conversations,
                  ),
                  hasConversations: conversations.isNotEmpty,
                ),
                const SizedBox(height: 16),
                _PartnerDetailSection(
                  child: KeyedSubtree(
                    key: _coachSectionKey,
                    child: CoachFollowUpSection(
                      partnerId: partnerId,
                      onTelemetry: _logCoachFollowUpTelemetry,
                      onQuotaExceeded: () async => context.push('/paywall'),
                      openCoachEntryAnchorKey: _coachAnchorKey,
                      openCoachInputOnFirstBuild: _openCoachInputRequested,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                PartnerStyleEntryCard(
                  partnerId: partnerId,
                  partnerName: partner.name,
                ),
                const SizedBox(height: 16),
                _PartnerExpandableDetailSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PartnerTraitsCard(
                        view: aggregate,
                        customNote: partner.customNote,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '這些特質會綜合同一張對象卡裡的互動紀錄；若某段聊天不是同一個人，請從該紀錄的 ⋮ 移到其他對象',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onBackgroundSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      PartnerRadarSummaryCard(
                        latestConversation:
                            conversations.isEmpty ? null : conversations.first,
                      ),
                    ],
                  ),
                ),
                if (dataQualityFlag.isFlagged &&
                    dataQualityFlag.conflictingPair != null) ...[
                  const SizedBox(height: 16),
                  PartnerDataQualityBanner(
                    nameA: _displayNameForCanonical(
                      conversations,
                      dataQualityFlag.conflictingPair!.first,
                      fallback: _fallbackDisplayName(
                        dataQualityFlag.conflictingPair!.first,
                      ),
                    ),
                    nameB: _displayNameForCanonical(
                      conversations,
                      dataQualityFlag.conflictingPair!.second,
                      fallback: _fallbackDisplayName(
                        dataQualityFlag.conflictingPair!.second,
                      ),
                    ),
                    onMarkSamePerson: () => _handleMarkSamePerson(
                      ref,
                      partner.id,
                      dataQualityFlag.conflictingPair!,
                    ),
                    onSplit: () => _handleSplit(
                      context,
                      ref,
                      partner,
                      dataQualityFlag.conflictingPair!,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.focusCoachFollowUp)
            _CoachFocusOrchestrator(
              scrollController: _scrollController,
              anchorKey: _coachAnchorKey,
              sectionKey: _coachSectionKey,
              openInputAfterFocus: widget.openCoachInputOnFocus,
              partnerId: partnerId,
              onOpenCoachInput: _handleOpenCoachInputRequested,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          // Keep conversations created from this screen attached to the
          // current Partner, including the manual-entry route.
          builder: (_) => NewConversationSheet(partnerId: partnerId),
        ),
        backgroundColor: AppColors.ctaStart,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: const StadiumBorder(),
        label: const Text(
          '+ 分析新片段',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  List<AnalysisRecord> _listArchivedAnalysisRecords({
    required List<Conversation> conversations,
    required String? ownerUserId,
  }) {
    final owner = ownerUserId?.trim();
    if (owner == null || owner.isEmpty || conversations.isEmpty) {
      return const [];
    }
    return AnalysisArchiveLifecycle.recordsFor(
      store: ref.read(analysisRecordStoreProvider),
      ownerUserId: owner,
      conversations: conversations,
    );
  }

  Future<void> _openPartnerAnalysisRecords({
    required Partner partner,
    required List<Conversation> conversations,
    required int archivedConversationCount,
  }) async {
    final ownerUserId = ref.read(analysisRecordOwnerProvider)?.trim();
    final store = ref.read(analysisRecordStoreProvider);
    if (ownerUserId != null && ownerUserId.isNotEmpty) {
      final promoted =
          await AnalysisArchiveLifecycle.promoteCompletedCurrentRecords(
        store: store,
        ownerUserId: ownerUserId,
        conversations: conversations,
      );
      if (!promoted || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('分析紀錄整理失敗，請再試一次。')),
          );
        }
        return;
      }
    }
    final records = _listArchivedAnalysisRecords(
      conversations: conversations,
      ownerUserId: ownerUserId,
    );
    final metVia = ownerUserId == null || ownerUserId.isEmpty
        ? null
        : store.partnerMetVia(
            ownerUserId: ownerUserId,
            partnerId: partner.id,
          );

    final action = await showPartnerAnalysisRecordsSheet(
      context,
      subjectName: partner.name,
      records: records,
      metVia: metVia,
      platformForRecord: (record) => record.sourcePlatform,
      archivedConversationCount: archivedConversationCount,
      onSetMetVia: ownerUserId == null || ownerUserId.isEmpty
          ? null
          : (platform) async {
              final saved = await store.setPartnerMetVia(
                ownerUserId: ownerUserId,
                partnerId: partner.id,
                sourcePlatform: platform,
              );
              if (!saved) throw StateError('met-via write rejected');
            },
      onDelete: ownerUserId == null || ownerUserId.isEmpty
          ? null
          : (record) async {
              Conversation? recordConversation;
              for (final candidate in conversations) {
                if (candidate.id == record.conversationId) {
                  recordConversation = candidate;
                  break;
                }
              }
              if (recordConversation != null &&
                  AnalysisArchiveLifecycle.isStandaloneFragmentRecord(
                    record: record,
                    conversation: recordConversation,
                    records: records,
                  )) {
                await ref
                    .read(conversationWriteControllerProvider.notifier)
                    .delete(recordConversation);
                return;
              }

              final deleted = await store.deleteRecord(
                ownerUserId: ownerUserId,
                conversationId: record.conversationId,
                recordId: record.id,
              );
              if (!deleted) throw StateError('record delete rejected');
            },
    );

    if (!mounted) return;
    if (action == PartnerAnalysisRecordsSheetAction.openArchivedConversations) {
      await context.push('/partner/${partner.id}/analysis-archive');
    }
    if (mounted) setState(() {});
  }

  Widget _buildEmptyStateScaffold({
    required BuildContext context,
    required WidgetRef ref,
    required Partner partner,
    required DataQualityFlag dataQualityFlag,
    required bool hasOtherPartner,
    required int archivedAnalysisCount,
  }) {
    final partnerId = partner.id;
    const conversations = <Conversation>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
        title: Text(
          partner.name,
          style: const TextStyle(color: AppColors.onBackgroundPrimary),
        ),
        actions: [
          AnalysisRecordsEntryButton(
            key: const ValueKey('partner-analysis-records-entry'),
            archivedCount: archivedAnalysisCount,
            onPressed: () => _openPartnerAnalysisRecords(
              partner: partner,
              conversations: conversations,
              archivedConversationCount: 0,
            ),
          ),
          IconButton(
            tooltip: '對象設定',
            onPressed: () => _onEditPartnerSettings(context, ref, partner),
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.onBackgroundPrimary,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              color: AppColors.onBackgroundPrimary,
            ),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'merge',
                enabled: hasOtherPartner,
                child: Text(
                  hasOtherPartner ? '合併重複對象' : '合併重複對象（需至少 2 個對象）',
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'merge') context.push('/partner/$partnerId/merge');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _PartnerDetailBackground()),
          SafeArea(
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                widget.focusCoachFollowUp ? 120 : 36,
              ),
              children: [
                _PartnerEmptyStateCard(
                  onAddConversation: () => showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (_) => NewConversationSheet(partnerId: partnerId),
                  ),
                ),
                const SizedBox(height: 14),
                _PartnerDetailSection(
                  child: KeyedSubtree(
                    key: _coachSectionKey,
                    child: CoachFollowUpSection(
                      partnerId: partnerId,
                      onTelemetry: _logCoachFollowUpTelemetry,
                      onQuotaExceeded: () async => context.push('/paywall'),
                      openCoachEntryAnchorKey: _coachAnchorKey,
                      openCoachInputOnFirstBuild: _openCoachInputRequested,
                      compactPracticePresentation: !widget.focusCoachFollowUp,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const _LockedFeatureCard(
                  icon: Icons.explore_outlined,
                  title: '對象作戰板',
                  subtitle: '完成第一次分析後解鎖',
                ),
                const SizedBox(height: 12),
                const _LockedFeatureCard(
                  icon: Icons.auto_awesome_outlined,
                  title: '關係下一步',
                  subtitle: '完成第一次分析後解鎖',
                ),
                const SizedBox(height: 20),
                Text(
                  '我的風格・對 ${partner.name}　沿用全域預設 →',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.45),
                  ),
                ),
                if (dataQualityFlag.isFlagged &&
                    dataQualityFlag.conflictingPair != null) ...[
                  const SizedBox(height: 16),
                  PartnerDataQualityBanner(
                    nameA: _displayNameForCanonical(
                      conversations,
                      dataQualityFlag.conflictingPair!.first,
                      fallback: _fallbackDisplayName(
                        dataQualityFlag.conflictingPair!.first,
                      ),
                    ),
                    nameB: _displayNameForCanonical(
                      conversations,
                      dataQualityFlag.conflictingPair!.second,
                      fallback: _fallbackDisplayName(
                        dataQualityFlag.conflictingPair!.second,
                      ),
                    ),
                    onMarkSamePerson: () => _handleMarkSamePerson(
                      ref,
                      partner.id,
                      dataQualityFlag.conflictingPair!,
                    ),
                    onSplit: () => _handleSplit(
                      context,
                      ref,
                      partner,
                      dataQualityFlag.conflictingPair!,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.focusCoachFollowUp)
            _CoachFocusOrchestrator(
              scrollController: _scrollController,
              anchorKey: _coachAnchorKey,
              sectionKey: _coachSectionKey,
              openInputAfterFocus: widget.openCoachInputOnFocus,
              partnerId: partnerId,
              onOpenCoachInput: _handleOpenCoachInputRequested,
            ),
        ],
      ),
    );
  }

  List<Widget> _conversationRecordWidgets(
    BuildContext context,
    WidgetRef ref,
    ConversationArchiveSections sections,
  ) {
    if (sections.active.isEmpty && sections.archived.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '還沒有分析片段\n截圖、貼上文字或手動輸入，都從「+ 分析新片段」開始',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ),
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '待分析片段',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '尚未完成的片段留在這裡；分析完成後會收進右上角的分析紀錄。',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
      if (sections.active.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '目前沒有待整理的對話',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        )
      else
        ...sections.active.map(
          (conversation) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PartnerConversationTile(
              conversation: conversation,
              onTap: () => context.push('/conversation/${conversation.id}'),
              onReassign: () => showConversationReassignPicker(
                context,
                conversation: conversation,
                ref: ref,
              ),
              onDelete: () =>
                  confirmDeleteConversation(context, ref, conversation),
            ),
          ),
        ),
    ];
  }

  Future<void> _handleMarkSamePerson(
    WidgetRef ref,
    String partnerId,
    NamePair pair,
  ) async {
    await ref
        .read(partnerDataQualityRepoProvider)
        .markSamePerson(partnerId, pair);
    ref.invalidate(dataQualityFlagProvider(partnerId));
  }

  Future<void> _handleSplit(
    BuildContext context,
    WidgetRef ref,
    Partner partner,
    NamePair pair,
  ) async {
    final conversations = ref.read(conversationsByPartnerProvider(partner.id));
    final splitTarget = _resolveSplitTarget(partner, conversations, pair);
    final confirmed = await _showSplitConfirmDialog(context, splitTarget);
    if (!confirmed) return;
    if (!context.mounted) return;

    final matchedIds = _filterConvIdsMatchingName(
      conversations,
      splitTarget.movingCanonicalName,
    );
    // Defensive: extractor mapping changed since the banner was rendered, or
    // the matching conversation was just deleted. No-op rather than create an
    // empty new partner.
    if (matchedIds.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(partnerWriteControllerProvider.notifier).split(
            sourcePartnerId: partner.id,
            newPartnerName: splitTarget.movingDisplayName,
            matchedConversationIds: matchedIds,
          );
      messenger.showSnackBar(
        buildBrandFeedbackSnackBar(
          title: '已把「${splitTarget.movingDisplayName}」拆成新對象',
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        buildBrandFeedbackSnackBar(
          title: '拆卡失敗，稍後再試',
          icon: Icons.error_outline_rounded,
          accentColor: AppColors.error,
        ),
      );
    }
  }

  /// [canonicalName] is the lowercased + trimmed form (i.e. `pair.second`),
  /// since `NamePair.canonical` normalises both sides. Extractor output is
  /// raw, so we normalise here for comparison.
  List<String> _filterConvIdsMatchingName(
    List<Conversation> convs,
    String canonicalName,
  ) {
    final extractor = NameCandidateExtractor();
    final ids = <String>[];
    for (final c in convs) {
      final name = extractor.fromConversationName(c.name) ??
          extractor.fromMessages(c.messages);
      if (name != null && name.trim().toLowerCase() == canonicalName) {
        ids.add(c.id);
      }
    }
    return ids;
  }

  _SplitTarget _resolveSplitTarget(
    Partner partner,
    List<Conversation> conversations,
    NamePair pair,
  ) {
    final currentPartnerName = _canonicalName(partner.name);
    final keepCanonicalName =
        currentPartnerName == pair.second ? pair.second : pair.first;
    final movingCanonicalName =
        keepCanonicalName == pair.first ? pair.second : pair.first;
    final partnerDisplayName = partner.name.trim();

    return _SplitTarget(
      keptDisplayName: currentPartnerName == keepCanonicalName
          ? partnerDisplayName
          : _displayNameForCanonical(
              conversations,
              keepCanonicalName,
              fallback: _fallbackDisplayName(keepCanonicalName),
            ),
      movingCanonicalName: movingCanonicalName,
      movingDisplayName: _displayNameForCanonical(
        conversations,
        movingCanonicalName,
        fallback: _fallbackDisplayName(movingCanonicalName),
      ),
    );
  }

  String _displayNameForCanonical(
    List<Conversation> conversations,
    String canonicalName, {
    required String fallback,
  }) {
    final extractor = NameCandidateExtractor();
    for (final c in conversations) {
      final conversationName = c.name.trim();
      final fromConversationName =
          extractor.fromConversationName(conversationName);
      if (fromConversationName != null &&
          _canonicalName(fromConversationName) == canonicalName) {
        return conversationName;
      }

      final fromMessages = extractor.fromMessages(c.messages);
      if (fromMessages != null &&
          _canonicalName(fromMessages) == canonicalName) {
        return _fallbackDisplayName(fromMessages);
      }
    }
    return fallback;
  }

  String _canonicalName(String name) => name.trim().toLowerCase();

  String _fallbackDisplayName(String canonicalName) {
    final s = canonicalName.trim();
    if (!RegExp(r'^[a-z ]+$').hasMatch(s)) return s;
    return s
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Future<bool> _showSplitConfirmDialog(
    BuildContext context,
    _SplitTarget splitTarget,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => BrandAlertDialog(
        title: const Text('拆成新對象？'),
        content: Text(
          '「${splitTarget.keptDisplayName}」會留在這張卡；含「${splitTarget.movingDisplayName}」的對話會搬到新的對象卡。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('確認拆卡'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Drives the mind-map「下一步」landing on partner detail. Lives OUTSIDE the
/// lazy body ListView (so it always mounts and runs, unlike a widget pinned at
/// the off-screen coach section) and owns the only invariant that matters:
///
///   position the coach section into view, THEN focus the coach input.
///
/// Because the body is a lazy `ListView`, the coach anchor is not laid out
/// while it sits below the viewport + cacheExtent, so `Scrollable.ensureVisible`
/// alone cannot reach it (its `currentContext` is null). We converge instead:
/// step the [scrollController] down by ~viewport chunks until the anchor (or,
/// for the with-result layout that has no anchor, the section) is built, then
/// `ensureVisible` aligns it near the top — no animation, per the spec. Only
/// after positioning settles do we hand the open-input intent to the section
/// (Phase E Task 7 — no legacy sheet, no pre-prompted consent).
class _CoachFocusOrchestrator extends StatefulWidget {
  final ScrollController scrollController;
  final GlobalKey anchorKey;
  final GlobalKey sectionKey;
  final bool openInputAfterFocus;
  final String partnerId;

  /// Phase E Task 7: called (once) after positioning when the deep-link
  /// carries focusAction=openCoachInput. The parent flips the section's
  /// openCoachInputOnFirstBuild flag, which bumps the CoachSurface focus
  /// token. The legacy sheet → consent → generate chain is gone: it charged
  /// through the legacy controller while the new UI renders no legacy result
  /// card, and consent is gated inside CoachSurface at ask time.
  final VoidCallback onOpenCoachInput;

  const _CoachFocusOrchestrator({
    required this.scrollController,
    required this.anchorKey,
    required this.sectionKey,
    required this.openInputAfterFocus,
    required this.partnerId,
    required this.onOpenCoachInput,
  });

  @override
  State<_CoachFocusOrchestrator> createState() =>
      _CoachFocusOrchestratorState();
}

class _CoachFocusOrchestratorState extends State<_CoachFocusOrchestrator> {
  // Upper bound on convergence frames. Generous: even a long page is a handful
  // of viewport hops. Guards against an unterminated loop if the target never
  // builds (degrades to "open without positioning", never to a hang).
  static const _maxSteps = 16;

  bool _started = false;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _scheduleStart();
  }

  @override
  void didUpdateWidget(covariant _CoachFocusOrchestrator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.partnerId != oldWidget.partnerId) {
      _started = false;
      _opened = false;
      _scheduleStart();
    }
  }

  void _scheduleStart() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _step(0);
    });
  }

  void _step(int step) {
    if (!mounted) return;

    // Prefer the precise input row; fall back to the whole section (the
    // with-result layout renders no open-coach entry, so the anchor is absent).
    final target =
        widget.anchorKey.currentContext ?? widget.sectionKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: Duration.zero,
        alignment: 0.08,
      );
      // Let the aligned offset paint before the input grabs focus (keyboard).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openIfRequested();
      });
      return;
    }

    // Target not built yet. Advance the scroll to inflate more slivers, then
    // re-check next frame. Stop at the bottom or the step cap.
    final controller = widget.scrollController;
    if (!controller.hasClients) {
      _retryOrGiveUp(step);
      return;
    }
    final position = controller.position;
    if (step >= _maxSteps || position.pixels >= position.maxScrollExtent) {
      // Could not locate the section (e.g. it never built). Honor the open
      // request anyway rather than leaving the user with nothing.
      _openIfRequested();
      return;
    }
    final next = (position.pixels + position.viewportDimension * 0.9)
        .clamp(0.0, position.maxScrollExtent);
    controller.jumpTo(next);
    _retryOrGiveUp(step);
  }

  void _retryOrGiveUp(int step) {
    if (step >= _maxSteps) {
      _openIfRequested();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _step(step + 1);
    });
  }

  void _openIfRequested() {
    if (!widget.openInputAfterFocus || _opened) return;
    _opened = true;
    // 「開啟教練輸入」意圖事件：沿用既有 stub telemetry 通道（不新增
    // schema）。意圖時點即記錄——不再有 sheet 送出可等，hasOptionalText
    // 恆為 false（自由文字只存在於 CoachSurface 輸入框內，絕不外流）。
    _logCoachFollowUpTelemetry(const CoachFollowUpInvokedEvent(
      phase: CoachFollowUpPhase.openCoach,
      hasOptionalText: false,
    ));
    widget.onOpenCoachInput();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _PartnerLatestInsight {
  final String? nextStep;
  final String? recentInsight;
  final String? interactionAction;
  final DateTime? analyzedAt;

  const _PartnerLatestInsight({
    this.nextStep,
    this.recentInsight,
    this.interactionAction,
    this.analyzedAt,
  });

  factory _PartnerLatestInsight.fromConversations(
    List<Conversation> conversations,
  ) {
    final sorted = [...conversations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    for (final conversation in sorted) {
      final raw = conversation.lastAnalysisSnapshotJson;
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final result = AnalysisResult.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
        final hint = result.coachActionHint;
        final hintInsight = (hint != null && hint.isUsable)
            ? '她丟出的球：${hint.catchablePoint}。${hint.read}'
            : null;
        final hintAction =
            (hint != null && hint.isUsable) ? hint.microMove : null;
        final segmentAction = _replySegmentAction(
          result.recommendation.replySegments,
        );
        final segmentCue = _replySegmentCue(
          result.recommendation.replySegments,
        );
        return _PartnerLatestInsight(
          nextStep: _firstNonEmpty([
            result.gameStage.nextStep,
            result.strategy,
            result.recommendation.reason,
          ]),
          recentInsight: _firstNonEmpty([
            hintInsight,
            segmentCue,
            result.psychology.subtext,
            result.recommendation.psychology,
            result.strategy,
          ]),
          interactionAction: _firstNonEmpty([
            segmentAction,
            result.recommendation.content,
            hintAction,
            result.topicDepth.suggestion,
            result.recommendation.reason,
          ]),
          analyzedAt: conversation.updatedAt,
        );
      } catch (_) {
        continue;
      }
    }

    return const _PartnerLatestInsight();
  }
}

String? _replySegmentAction(List<ReplySegment> segments) {
  for (final segment in segments) {
    final reply = segment.reply.trim();
    if (reply.isEmpty) continue;
    final source = segment.sourceMessage.trim();
    if (source.isNotEmpty) {
      return '接「$source」：$reply';
    }
    return '${segment.displayLabel}：$reply';
  }
  return null;
}

String? _replySegmentCue(List<ReplySegment> segments) {
  for (final segment in segments) {
    final source = segment.sourceMessage.trim();
    if (source.isNotEmpty) {
      return '她剛提到：$source';
    }
  }
  return null;
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

class _PartnerCommandSummaryCard extends StatelessWidget {
  final Partner partner;
  final PartnerAggregateView aggregate;
  final List<Conversation> conversations;

  const _PartnerCommandSummaryCard({
    required this.partner,
    required this.aggregate,
    required this.conversations,
  });

  @override
  Widget build(BuildContext context) {
    final state = PartnerHeatMessaging.labelFor(aggregate.latestHeat);
    // 總覽卡只放「短抓手」，不再重貼完整下一步（資訊架構去重：完整建議只在
    // 下方主卡出現一次）。抓手由特質/興趣衍生，與 nextStep 解耦。
    final hook = PartnerInsightPresentation.derive(
          interests: aggregate.unionInterests,
          traits: aggregate.unionTraits,
        ).tacticalHook ??
        _emptyHook(conversations);
    final tags = _highValueTags(aggregate, state);

    return _PartnerDetailSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name,
                      style: const TextStyle(
                        color: AppColors.onBackgroundPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '最近一次：$state',
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _StateBadge(label: state),
            ],
          ),
          const SizedBox(height: 14),
          _SummaryLine(
            icon: Icons.schedule_outlined,
            label: '最近互動',
            value: _formatInteractionTime(aggregate.lastInteraction),
          ),
          const SizedBox(height: 8),
          _SummaryLine(
            icon: Icons.tips_and_updates_outlined,
            label: '接法',
            value: hook,
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags.map((tag) => _PartnerTag(tag)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  static String _emptyHook(List<Conversation> conversations) {
    if (conversations.isEmpty) {
      return '先新增第一段互動，這裡會整理出聊天抓手。';
    }
    return '先分析最近一段互動，這裡會冒出可接的話題抓手。';
  }

  static List<String> _highValueTags(
    PartnerAggregateView aggregate,
    String state,
  ) {
    final result = <String>['本次投入：$state'];
    final maxLength =
        aggregate.unionInterests.length > aggregate.unionTraits.length
            ? aggregate.unionInterests.length
            : aggregate.unionTraits.length;
    for (var i = 0; i < maxLength && result.length < 4; i++) {
      if (i < aggregate.unionTraits.length) {
        result.add(aggregate.unionTraits[i]);
      }
      if (i < aggregate.unionInterests.length && result.length < 4) {
        result.add(aggregate.unionInterests[i]);
      }
    }
    return result;
  }
}

class _PartnerNextStepCard extends StatelessWidget {
  final _PartnerLatestInsight latestInsight;
  final bool hasConversations;

  const _PartnerNextStepCard({
    required this.latestInsight,
    required this.hasConversations,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = latestInsight.nextStep ??
        (hasConversations ? '先分析最近一段互動，讓這裡變成關係下一步。' : '先新增第一段互動紀錄，再回來看下一步。');
    final action = latestInsight.interactionAction ?? fallback;
    final insight = latestInsight.recentInsight;
    final actionLabel =
        latestInsight.interactionAction == null ? '關係下一步' : '建議接法';

    return _PartnerDetailSection(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.ctaStart.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.assistant_direction_outlined,
              color: AppColors.ctaStart,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '下一步行動',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                if (insight != null) ...[
                  Text(
                    '互動摘錄',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.ctaStart,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    insight,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  actionLabel,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    height: 1.42,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.onBackgroundSecondary),
        const SizedBox(width: 8),
        Text(
          '$label：',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundPrimary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _StateBadge extends StatelessWidget {
  final String label;

  const _StateBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.24),
        ),
      ),
      child: Text(
        label,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PartnerTag extends StatelessWidget {
  final String label;

  const _PartnerTag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundPrimary,
        ),
      ),
    );
  }
}

class _PartnerEmptyStateCard extends StatelessWidget {
  final VoidCallback onAddConversation;

  const _PartnerEmptyStateCard({required this.onAddConversation});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.075),
            Colors.white.withValues(alpha: 0.025),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.ctaStart, AppColors.bokehPink],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ctaStart.withValues(alpha: 0.2),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '還沒有分析片段',
            textAlign: TextAlign.center,
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '截圖、貼上文字，或手動輸入\n開始你們的第一次分析',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              key: const Key('partner-empty-add-conversation'),
              onPressed: onAddConversation,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ctaStart,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('+ 分析新片段'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _LockedFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title，$subtitle',
      enabled: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
        ),
        child: Opacity(
          opacity: 0.48,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: AppColors.onBackgroundSecondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onBackgroundSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.lock_outline_rounded,
                size: 20,
                color: AppColors.onBackgroundSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartnerExpandableDetailSection extends StatefulWidget {
  final Widget child;

  const _PartnerExpandableDetailSection({required this.child});

  @override
  State<_PartnerExpandableDetailSection> createState() =>
      _PartnerExpandableDetailSectionState();
}

class _PartnerExpandableDetailSectionState
    extends State<_PartnerExpandableDetailSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return _PartnerDetailSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _expanded ? Icons.insights : Icons.insights_outlined,
                      color: AppColors.onBackgroundPrimary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '詳細特質與趨勢',
                          style: AppTypography.titleSmall.copyWith(
                            color: AppColors.onBackgroundPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '長期資料與雷達圖，給想確認依據時展開。',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onBackgroundSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _expanded ? '收起' : '展開',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.onBackgroundSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 14),
            widget.child,
          ],
        ],
      ),
    );
  }
}

class _PartnerDetailSection extends StatelessWidget {
  final Widget child;

  const _PartnerDetailSection({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

String _formatInteractionTime(DateTime? value) {
  if (value == null) return '尚未有互動';
  final now = DateTime.now();
  if (value.year == now.year &&
      value.month == now.month &&
      value.day == now.day) {
    return '今天 ${DateFormat('HH:mm').format(value)}';
  }
  return DateFormat('MM/dd HH:mm').format(value);
}

class _SplitTarget {
  final String keptDisplayName;
  final String movingCanonicalName;
  final String movingDisplayName;

  const _SplitTarget({
    required this.keptDisplayName,
    required this.movingCanonicalName,
    required this.movingDisplayName,
  });
}

/// Static dark-navy backdrop with 3 brand-colored glow bubbles.
///
/// Bubbles are intentionally STATIC (no AnimationController). This mirrors
/// `AddPartnerScreen._AddPartnerBackground` for the same reason: animated
/// controllers cause `pumpAndSettle` hangs in widget tests, and detail-screen
/// tests rely on it. The mood is provided by gradient + tinted glows alone.
class _PartnerDetailBackground extends StatelessWidget {
  const _PartnerDetailBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.partnerDetailBgTop,
            AppColors.partnerDetailBgBottom,
          ],
        ),
      ),
      child: IgnorePointer(
        child: Stack(
          children: [
            // Top-right purple halo — sits behind the hero card.
            Positioned(
              top: -60,
              right: -60,
              child: _GlowBubble(
                color: AppColors.primaryLight,
                size: 220,
                opacity: 0.32,
              ),
            ),
            // Bottom-left warm-pink halo — sits near the FAB region.
            Positioned(
              bottom: -40,
              left: -40,
              child: _GlowBubble(
                color: AppColors.ctaStart,
                size: 180,
                opacity: 0.22,
              ),
            ),
            // Mid-right faint pink — ambient warmth between cards.
            Positioned(
              top: 320,
              right: -80,
              child: _GlowBubble(
                color: AppColors.bokehPink,
                size: 140,
                opacity: 0.18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowBubble extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;
  const _GlowBubble({
    required this.color,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: opacity),
            blurRadius: 80,
            spreadRadius: 30,
          ),
        ],
      ),
    );
  }
}

/// Stub telemetry sink for Spec 5 coach-follow-up events. Phase X25 will
/// swap this for a real analytics SDK call; until then we log in debug so
/// the contract is exercised end-to-end without leaking free-text answers.
void _logCoachFollowUpTelemetry(CoachFollowUpTelemetryEvent event) {
  switch (event) {
    case CoachFollowUpInvokedEvent(:final phase, :final hasOptionalText):
      debugPrint(
        'coach_follow_up_invoked phase=${phase.name} hasOptionalText=$hasOptionalText',
      );
    case CoachFollowUpRegeneratedEvent(:final phase, :final sinceLast):
      debugPrint(
        'coach_follow_up_regenerated phase=${phase.name} secondsSinceLast=${sinceLast.inSeconds}',
      );
    case CoachFollowUpPhaseSwitchedEvent(
        :final fromPhase,
        :final toPhase,
        :final hadResultBefore,
      ):
      debugPrint(
        'coach_follow_up_phase_switched from=${fromPhase.name} to=${toPhase.name} hadResultBefore=$hadResultBefore',
      );
  }
}

Future<void> _onEditPartnerSettings(
  BuildContext context,
  WidgetRef ref,
  Partner partner,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(partnerWriteControllerProvider.notifier);
  final result = await showDialog<PartnerSettingsResult>(
    context: context,
    builder: (_) => PartnerSettingsDialog(
      initialName: partner.name,
      initialNote: partner.customNote ?? '',
    ),
  );
  if (result == null) return;

  final shouldUpdateName = result.name.trim() != partner.name.trim();
  final shouldUpdateNote =
      result.note.trim() != (partner.customNote ?? '').trim();
  if (!shouldUpdateName && !shouldUpdateNote) return;

  try {
    if (shouldUpdateName) {
      await controller.updateName(partner, result.name);
    }
    if (shouldUpdateNote) {
      await controller.updateCustomNote(partner, result.note);
    }
    if (!context.mounted) return;
    messenger.showSnackBar(
      buildBrandFeedbackSnackBar(title: '已更新對象設定'),
    );
  } catch (e, st) {
    debugPrint('PartnerDetailScreen settings edit failed: $e\n$st');
    if (!context.mounted) return;
    messenger.showSnackBar(
      buildBrandFeedbackSnackBar(
        title: '更新失敗，請稍後再試',
        icon: Icons.error_outline_rounded,
        accentColor: AppColors.error,
      ),
    );
  }
}
