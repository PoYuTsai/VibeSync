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
// Behavior unchanged:
//  - ⋮ menu (merge / edit / delete-即將推出) — see partner_detail_screen_test.
//  - FAB still opens NewConversationSheet(partnerId).
//  - FAB label STAYS "+ 新增對話" per ADR-15 vocabulary contract
//    (see test/widget/features/copy_sweep_snapshot_test.dart).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../conversation/data/providers/conversation_write_controller.dart';
import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/presentation/dialogs/conversation_reassign_picker.dart';
import '../../../conversation/presentation/dialogs/delete_conversation_confirm_dialog.dart';
import '../../../analysis/data/providers/analysis_providers.dart';
import '../../../analysis/domain/entities/analysis_models.dart';
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
import '../dialogs/partner_settings_dialog.dart';
import '../providers/partner_providers.dart';
import '../widgets/partner_conversation_tile.dart';
import '../widgets/partner_data_quality_banner.dart';
import '../widgets/partner_heat_hero_card.dart';
import '../widgets/partner_mind_map_entry_card.dart';
import '../widgets/partner_radar_summary_card.dart';
import '../widgets/partner_traits_card.dart';

class PartnerDetailScreen extends ConsumerWidget {
  final String partnerId;
  const PartnerDetailScreen({super.key, required this.partnerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerByIdProvider(partnerId));
    final aggregate = ref.watch(partnerAggregateProvider(partnerId));
    final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
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
              // SafeArea already keeps the content out of the transparent
              // toolbar zone on device. Do not add another top inset here, or
              // the hero card leaves a visible dead shelf under the title.
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
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
                ..._conversationRecordWidgets(context, ref, conversations),
                const SizedBox(height: 12),
                _PartnerNextStepCard(
                  latestInsight: _PartnerLatestInsight.fromConversations(
                    conversations,
                  ),
                  hasConversations: conversations.isNotEmpty,
                ),
                const SizedBox(height: 16),
                _PartnerDetailSection(
                  child: CoachFollowUpSection(
                    partnerId: partnerId,
                    onTelemetry: _logCoachFollowUpTelemetry,
                    onQuotaExceeded: () async => context.push('/paywall'),
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
        // ADR-15 vocabulary lock — copy stays "+ 新增對話" verbatim
        // (Path A 2026-04-28). Visual is the only thing that changed:
        // pill shape + warm orange + amplified elevation. Subtle warm
        // glow comes from the bottom-left bubble in the backdrop.
        label: const Text(
          '+ 新增對話',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  List<Widget> _conversationRecordWidgets(
    BuildContext context,
    WidgetRef ref,
    List<Conversation> conversations,
  ) {
    if (conversations.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '還沒有互動紀錄\n第一次聊天、截圖或手動輸入，都從「+ 新增對話」開始',
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
              '互動紀錄',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '要接續同一段聊天，請點進原本那段紀錄；同一個人換日期或換平台，才建議再新增一段，保持對話的分析品質乾淨',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
      ...conversations.map(
        (c) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PartnerConversationTile(
            conversation: c,
            onTap: () => context.push('/conversation/${c.id}'),
            onReassign: () => showConversationReassignPicker(
              context,
              conversation: c,
              ref: ref,
            ),
            onDelete: () => _confirmDeleteConversation(context, ref, c),
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
        SnackBar(content: Text('已把「${splitTarget.movingDisplayName}」拆成新對象')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('拆卡失敗，稍後再試')),
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
      builder: (ctx) => AlertDialog(
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

class _PartnerLatestInsight {
  final String? nextStep;
  final String? recentInsight;
  final DateTime? analyzedAt;

  const _PartnerLatestInsight({
    this.nextStep,
    this.recentInsight,
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
        return _PartnerLatestInsight(
          nextStep: _firstNonEmpty([
            result.gameStage.nextStep,
            result.strategy,
            result.recommendation.reason,
          ]),
          recentInsight: _firstNonEmpty([
            hintInsight,
            result.strategy,
            result.psychology.subtext,
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
    final insight = _PartnerLatestInsight.fromConversations(conversations);
    final state = PartnerHeatMessaging.labelFor(aggregate.latestHeat);
    final suggestion = insight.nextStep ?? _emptySuggestion(conversations);
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
                      '目前：$state',
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
            icon: Icons.flag_outlined,
            label: '最近建議',
            value: suggestion,
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

  static String _emptySuggestion(List<Conversation> conversations) {
    if (conversations.isEmpty) {
      return '先新增第一段互動，VibeSync 會把這裡整理成下一步。';
    }
    return '先分析最近一段互動，這裡會顯示下一步。';
  }

  static List<String> _highValueTags(
    PartnerAggregateView aggregate,
    String state,
  ) {
    final result = <String>['狀態：$state'];
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
    final nextStep = latestInsight.nextStep ??
        (hasConversations ? '先分析最近一段互動，讓這裡變成關係下一步。' : '先新增第一段互動紀錄，再回來看下一步。');
    final insight = latestInsight.recentInsight;

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
                  '下一步',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  nextStep,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    height: 1.42,
                  ),
                ),
                if (insight != null && insight != nextStep) ...[
                  const SizedBox(height: 8),
                  Text(
                    '本回合怎麼接：$insight',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
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
        color: AppColors.primaryLight.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.primaryLight.withValues(alpha: 0.24),
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
    messenger.showSnackBar(const SnackBar(content: Text('已更新對象設定')));
  } catch (e, st) {
    debugPrint('PartnerDetailScreen settings edit failed: $e\n$st');
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('更新失敗，請稍後再試')),
    );
  }
}

Future<void> _confirmDeleteConversation(
  BuildContext context,
  WidgetRef ref,
  Conversation c,
) async {
  final dateLabel = DateFormat('MM/dd').format(c.updatedAt);
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(conversationWriteControllerProvider.notifier);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => DeleteConversationConfirmDialog(
      dateLabel: dateLabel,
      messageCount: c.messages.length,
    ),
  );
  if (confirmed != true) return;
  try {
    await controller.delete(c);
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('已刪除這段互動紀錄')),
    );
  } catch (e, st) {
    debugPrint('PartnerDetailScreen conversation delete failed: $e\n$st');
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('刪除失敗，請稍後再試')),
    );
  }
}
