import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/analysis_record.dart';
import '../widgets/analysis_platform_picker.dart';
import 'analysis_record_detail_screen.dart';

typedef AnalysisRecordPlatformResolver = String? Function(
  AnalysisRecord record,
);
typedef SetAnalysisPlatformCallback = FutureOr<void> Function(
  String? platform,
);
typedef DeleteAnalysisRecordCallback = FutureOr<void> Function(
  AnalysisRecord record,
);

enum PartnerAnalysisRecordsSheetAction {
  openArchivedConversations,
}

const _archiveAccent = Color(0xFF9D78F5);
const _archiveAccentBright = Color(0xFFC68BFF);
const _archivePink = Color(0xFFFF5DA8);
const _archivePanel = Color(0xFF15152A);
const _archivePanelRaised = Color(0xFF24172F);

/// Opens the partner-level archive with the same presentation from both the
/// partner page and the analyze-chat shortcut.
Future<PartnerAnalysisRecordsSheetAction?> showPartnerAnalysisRecordsSheet(
  BuildContext context, {
  required String subjectName,
  required List<AnalysisRecord> records,
  required AnalysisRecordPlatformResolver platformForRecord,
  String? metVia,
  SetAnalysisPlatformCallback? onSetMetVia,
  DeleteAnalysisRecordCallback? onDelete,
  int archivedConversationCount = 0,
}) {
  return showModalBottomSheet<PartnerAnalysisRecordsSheetAction>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final availableHeight = MediaQuery.sizeOf(sheetContext).height;
      final heightFactor = availableHeight < 700 ? 0.90 : 0.74;
      return FractionallySizedBox(
        heightFactor: heightFactor,
        alignment: Alignment.bottomCenter,
        child: PartnerAnalysisRecordsScreen(
          subjectName: subjectName,
          records: records,
          platformForRecord: platformForRecord,
          metVia: metVia,
          onSetMetVia: onSetMetVia,
          onDelete: onDelete,
          archivedConversationCount: archivedConversationCount,
          onOpenArchivedConversations: archivedConversationCount > 0
              ? () => Navigator.of(sheetContext).pop(
                    PartnerAnalysisRecordsSheetAction.openArchivedConversations,
                  )
              : null,
        ),
      );
    },
  );
}

/// Compact app-bar entry shared by the partner page and analyze-chat page.
class AnalysisRecordsEntryButton extends StatelessWidget {
  const AnalysisRecordsEntryButton({
    super.key,
    required this.archivedCount,
    required this.onPressed,
  });

  final int archivedCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final badgeText = archivedCount > 99 ? '99+' : '$archivedCount';
    return Semantics(
      button: true,
      label: archivedCount == 0 ? '分析紀錄' : '分析紀錄，$archivedCount 筆',
      child: IconButton(
        tooltip: '分析紀錄',
        onPressed: onPressed,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              color: archivedCount > 0
                  ? _archiveAccentBright
                  : AppColors.onBackgroundPrimary,
            ),
            if (archivedCount > 0)
              Positioned(
                key: const ValueKey('analysis-record-count-badge'),
                right: -8,
                top: -8,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _archivePink,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF120B1F),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: AppTypography.labelMedium.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Partner-level archive content. The parent presents this widget as a modal
/// bottom sheet so the user keeps spatial context with the partner page.
class PartnerAnalysisRecordsScreen extends StatefulWidget {
  const PartnerAnalysisRecordsScreen({
    super.key,
    required this.subjectName,
    required this.records,
    required this.platformForRecord,
    this.metVia,
    this.onSetMetVia,
    this.onDelete,
    this.archivedConversationCount = 0,
    this.onOpenArchivedConversations,
    this.scrollController,
  });

  final String subjectName;
  final String? metVia;
  final List<AnalysisRecord> records;
  final AnalysisRecordPlatformResolver platformForRecord;
  final SetAnalysisPlatformCallback? onSetMetVia;
  final DeleteAnalysisRecordCallback? onDelete;
  final int archivedConversationCount;
  final VoidCallback? onOpenArchivedConversations;
  final ScrollController? scrollController;

  @override
  State<PartnerAnalysisRecordsScreen> createState() =>
      _PartnerAnalysisRecordsScreenState();
}

class _PartnerAnalysisRecordsScreenState
    extends State<PartnerAnalysisRecordsScreen> {
  static const _allPlatforms = '__all__';

  late List<AnalysisRecord> _records;
  late String? _metVia;
  String _selectedPlatform = _allPlatforms;
  bool _isSettingMetVia = false;

  @override
  void initState() {
    super.initState();
    _records = _latestFirst(widget.records);
    _metVia = normalizeAnalysisPlatform(widget.metVia);
  }

  @override
  void didUpdateWidget(covariant PartnerAnalysisRecordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.records, widget.records)) {
      _records = _latestFirst(widget.records);
    }
    if (oldWidget.metVia != widget.metVia) {
      _metVia = normalizeAnalysisPlatform(widget.metVia);
    }
    if (_selectedPlatform != _allPlatforms &&
        !_knownPlatformCounts.containsKey(_selectedPlatform)) {
      _selectedPlatform = _allPlatforms;
    }
  }

  static List<AnalysisRecord> _latestFirst(List<AnalysisRecord> source) {
    final records = List<AnalysisRecord>.of(source);
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records;
  }

  String? _platformFor(AnalysisRecord record) =>
      normalizeAnalysisPlatform(widget.platformForRecord(record));

  Map<String, int> get _knownPlatformCounts {
    final counts = <String, int>{};
    for (final record in _records) {
      final platform = _platformFor(record);
      if (platform == null) continue;
      counts.update(platform, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  bool get _showPlatformFilters => _knownPlatformCounts.length >= 2;

  List<AnalysisRecord> get _visibleRecords {
    if (_selectedPlatform == _allPlatforms) return _records;
    return _records
        .where((record) => _platformFor(record) == _selectedPlatform)
        .toList();
  }

  Future<void> _chooseMetVia() async {
    if (_isSettingMetVia || widget.onSetMetVia == null) return;
    final result = await showAnalysisPlatformPicker(
      context,
      currentValue: _metVia,
      title: '你們在哪裡認識？',
    );
    if (!mounted || result == null) return;

    setState(() => _isSettingMetVia = true);
    try {
      await Future<void>.sync(() => widget.onSetMetVia!(result.platform));
      if (!mounted) return;
      setState(() => _metVia = normalizeAnalysisPlatform(result.platform));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('認識平台儲存失敗，請再試一次')),
      );
    } finally {
      if (mounted) setState(() => _isSettingMetVia = false);
    }
  }

  Future<void> _openRecord(AnalysisRecord record) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AnalysisRecordDetailScreen(
          record: record,
          platform: _platformFor(record),
          onDelete: widget.onDelete == null
              ? null
              : () async {
                  await Future<void>.sync(() => widget.onDelete!(record));
                },
        ),
      ),
    );
    if (!mounted || deleted != true) return;
    setState(() {
      _records.removeWhere((item) => item.id == record.id);
      if (_selectedPlatform != _allPlatforms &&
          !_knownPlatformCounts.containsKey(_selectedPlatform)) {
        _selectedPlatform = _allPlatforms;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final subjectName =
        widget.subjectName.trim().isEmpty ? '對方' : widget.subjectName.trim();
    final counts = _knownPlatformCounts;

    return Material(
      color: Colors.transparent,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2A1831),
              Color(0xFF111329),
              Color(0xFF090C1B),
            ],
            stops: [0, 0.46, 1],
          ),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(30),
          ),
          border: Border.all(
            color: _archivePink.withValues(alpha: 0.58),
          ),
          boxShadow: [
            BoxShadow(
              color: _archivePink.withValues(alpha: 0.16),
              blurRadius: 34,
              spreadRadius: 2,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: _archiveAccentBright.withValues(alpha: 0.46),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Column(
                  children: [
                    Text(
                      '$subjectName 的分析紀錄',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineMedium.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_metVia != null || widget.onSetMetVia != null)
                      _MetViaPill(
                        value: _metVia,
                        enabled:
                            widget.onSetMetVia != null && !_isSettingMetVia,
                        isSaving: _isSettingMetVia,
                        onTap: _chooseMetVia,
                      ),
                    const SizedBox(height: 10),
                    Text(
                      '每次分析獨立保存，不會串成逐字稿',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: _archiveAccentBright.withValues(alpha: 0.90),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('partner-analysis-records-list'),
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                  children: [
                    if (_showPlatformFilters) ...[
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          key: const ValueKey(
                            'analysis-record-platform-filters',
                          ),
                          scrollDirection: Axis.horizontal,
                          itemCount: counts.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final platform = index == 0
                                ? _allPlatforms
                                : counts.keys.elementAt(index - 1);
                            final label = index == 0 ? '全部' : platform;
                            final count = index == 0
                                ? _records.length
                                : counts[platform]!;
                            return _PlatformFilterChip(
                              key: ValueKey(
                                'analysis-record-filter-$label',
                              ),
                              label: label,
                              count: count,
                              selected: _selectedPlatform == platform,
                              accent: index == 0
                                  ? _archiveAccentBright
                                  : _platformAccent(platform),
                              onSelected: () => setState(
                                () => _selectedPlatform = platform,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_visibleRecords.isEmpty)
                      const _EmptyRecordsCard()
                    else
                      for (final record in _visibleRecords) ...[
                        _AnalysisRecordTile(
                          key: ValueKey('analysis-record-${record.id}'),
                          record: record,
                          platform: _platformFor(record),
                          onTap: () => _openRecord(record),
                        ),
                        const SizedBox(height: 10),
                      ],
                    if (widget.archivedConversationCount > 0 &&
                        widget.onOpenArchivedConversations != null) ...[
                      const SizedBox(height: 6),
                      _ArchivedConversationsEntry(
                        count: widget.archivedConversationCount,
                        onTap: widget.onOpenArchivedConversations!,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 17,
                          color: _archiveAccent.withValues(alpha: 0.72),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            '每筆都是獨立分析，可自行管理',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.onBackgroundSecondary
                                  .withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetViaPill extends StatelessWidget {
  const _MetViaPill({
    required this.value,
    required this.enabled,
    required this.isSaving,
    required this.onTap,
  });

  final String? value;
  final bool enabled;
  final bool isSaving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = value == null ? '設定認識平台' : '認識於 $value';
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: const ValueKey('analysis-record-met-via'),
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _archivePink.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _archivePink.withValues(alpha: 0.72),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSaving)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _archivePink,
                  ),
                )
              else
                const Icon(
                  Icons.favorite_outline_rounded,
                  size: 16,
                  color: _archivePink,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: const Color(0xFFFFAA8C),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (enabled && !isSaving) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: Color(0xFFFFAA8C),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformFilterChip extends StatelessWidget {
  const _PlatformFilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.accent,
    required this.onSelected,
  });

  final String label;
  final int count;
  final bool selected;
  final Color accent;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onSelected,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.18)
                  : const Color(0xFF111225),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.78)
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Text(
              '$label $count',
              style: AppTypography.labelMedium.copyWith(
                color: selected ? accent : AppColors.onBackgroundSecondary,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalysisRecordTile extends StatelessWidget {
  const _AnalysisRecordTile({
    super.key,
    required this.record,
    required this.platform,
    required this.onTap,
  });

  final AnalysisRecord record;
  final String? platform;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localDate = record.createdAt.toLocal();
    final accent = _platformAccent(platform);
    final stage = record.gameStageLabel.trim();
    final metadata = StringBuffer(
      '${record.messages.length} 則訊息 · 本次投入 ${record.enthusiasmScore}',
    );
    if (stage.isNotEmpty) metadata.write(' · $stage');

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _archivePanelRaised.withValues(alpha: 0.92),
                _archivePanel.withValues(alpha: 0.96),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent.withValues(alpha: platform == null ? 0.30 : 0.50),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.34),
                    ),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: accent,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 7,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            DateFormat('M 月 d 日 · HH:mm').format(localDate),
                            style: AppTypography.bodySmall.copyWith(
                              color: platform == null
                                  ? AppColors.onBackgroundSecondary
                                  : accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (platform != null)
                            _PlatformBadge(
                              label: platform!,
                              accent: accent,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        record.archiveTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.onBackgroundPrimary,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        metadata.toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: accent.withValues(alpha: 0.90),
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.40)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelMedium.copyWith(
          color: accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ArchivedConversationsEntry extends StatelessWidget {
  const _ArchivedConversationsEntry({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: const ValueKey('archived-conversations-secondary-entry'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  color: _archiveAccent,
                  size: 21,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    '已收起的對話 $count',
                    style: AppTypography.titleSmall.copyWith(
                      color: _archiveAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _archiveAccent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRecordsCard extends StatelessWidget {
  const _EmptyRecordsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 24,
            color: _archiveAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '還沒有舊的分析紀錄',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '每次完成的分析片段都會獨立收進這裡，可依平台篩選或單獨刪除。',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.45,
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

Color _platformAccent(String? platform) {
  switch (platform?.trim().toLowerCase()) {
    case 'omi':
      return const Color(0xFFFF5F91);
    case 'line':
      return const Color(0xFF55D884);
    case 'ig':
    case 'instagram':
      return const Color(0xFFFF7A72);
    case 'threads':
      return const Color(0xFFE2D8EA);
    case 'tinder':
      return const Color(0xFFFF5A65);
    case 'bumble':
      return const Color(0xFFFFC857);
    default:
      return _archiveAccent;
  }
}
