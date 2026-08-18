import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/analysis_record.dart';
import '../widgets/analysis_platform_picker.dart';
import 'analysis_record_detail_screen.dart';
import '../../../../core/services/app_haptics.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../shared/widgets/brand/app_sheet.dart';
import '../../../../shared/widgets/brand/brand_dialog.dart';

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

const _archiveAccent = AppColors.coachAccent;
const _archiveAccentBright = AppColors.coachAccentBright;
const _archivePink = AppColors.coachRecommendation;
const _archivePanel = AppColors.coachSurface;
const _archivePanelRaised = AppColors.coachSurfaceRaised;

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
  return showAppSheet<PartnerAnalysisRecordsSheetAction>(
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
                      fontSize: 12,
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

  /// 批次刪除的多選模式（2026-08-18 dogfood：之前只能點進詳情單筆刪）。
  bool _selecting = false;
  final Set<String> _selectedIds = <String>{};
  bool _isDeleting = false;

  bool get _canSelect => widget.onDelete != null && _records.isNotEmpty;

  bool get _allVisibleSelected {
    final visible = _visibleRecords;
    return visible.isNotEmpty &&
        visible.every((record) => _selectedIds.contains(record.id));
  }

  void _enterSelection([String? firstId]) {
    if (!_canSelect || _isDeleting) return;
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

  void _toggleSelected(AnalysisRecord record) {
    if (_isDeleting) return;
    AppHaptics.tap();
    setState(() {
      if (!_selectedIds.add(record.id)) _selectedIds.remove(record.id);
    });
  }

  /// 全選／取消全選只作用在目前篩選看得到的紀錄（篩到 LINE 就只選 LINE）。
  void _toggleSelectAllVisible() {
    if (_isDeleting) return;
    AppHaptics.tap();
    final visibleIds = _visibleRecords.map((record) => record.id).toSet();
    setState(() {
      if (_allVisibleSelected) {
        _selectedIds.removeAll(visibleIds);
      } else {
        _selectedIds.addAll(visibleIds);
      }
    });
  }

  /// 逐筆走呼叫端的 onDelete（沿用單筆刪的完整安全語義），刪一筆掉一筆；
  /// 中途失敗就停在原地，已刪的不回滾（跟單筆刪一樣是既成事實）。
  Future<void> _deleteSelected() async {
    final onDelete = widget.onDelete;
    if (onDelete == null || _selectedIds.isEmpty || _isDeleting) return;
    final targets =
        _records.where((record) => _selectedIds.contains(record.id)).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _BatchDeleteConfirmDialog(count: targets.length),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    var deleted = 0;
    var failed = false;
    for (final record in targets) {
      try {
        await Future<void>.sync(() => onDelete(record));
      } catch (_) {
        failed = true;
        break;
      }
      deleted += 1;
      if (!mounted) return;
      setState(() {
        _records.removeWhere((item) => item.id == record.id);
        _selectedIds.remove(record.id);
      });
    }
    if (!mounted) return;
    setState(() {
      _isDeleting = false;
      if (!failed) {
        _selecting = false;
        _selectedIds.clear();
      }
      if (_selectedPlatform != _allPlatforms &&
          !_knownPlatformCounts.containsKey(_selectedPlatform)) {
        _selectedPlatform = _allPlatforms;
      }
    });
    if (failed) {
      AppHaptics.failure();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刪除中斷：已刪 $deleted 筆，其餘保留，請再試一次')),
      );
    } else {
      AppHaptics.medium();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已刪除 $deleted 筆分析紀錄')),
      );
    }
  }

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
    // SharedAxis scaled（往內走一層）：sheet 留底、詳情放大浮現，pop 縮回
    // sheet 繼續逛。fillColor 透明讓底下 sheet/scrim 轉場中自然透出。
    final deleted = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: AppMotion.sharedAxisIn,
        reverseTransitionDuration: AppMotion.sharedAxisOut,
        pageBuilder: (context, animation, secondaryAnimation) =>
            AnalysisRecordDetailScreen(
          record: record,
          platform: _platformFor(record),
          onDelete: widget.onDelete == null
              ? null
              : () async {
                  await Future<void>.sync(() => widget.onDelete!(record));
                },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transitionType: SharedAxisTransitionType.scaled,
          fillColor: Colors.transparent,
          child: child,
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
              AppColors.coachBackgroundWarm,
              AppColors.coachBackgroundMid,
              AppColors.coachBackgroundInk,
            ],
            stops: [0, 0.46, 1],
          ),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
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
              // 對標示意稿（2026-08-14）：標題與副標靠左，認識平台改整寬列卡。
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$subjectName 的分析紀錄',
                      style: AppTypography.headlineMedium.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '每次分析獨立保存，不會串成逐字稿',
                      style: AppTypography.bodyMedium.copyWith(
                        color: _archiveAccentBright.withValues(alpha: 0.90),
                      ),
                    ),
                    if (_metVia != null || widget.onSetMetVia != null) ...[
                      const SizedBox(height: 14),
                      _MetViaRow(
                        value: _metVia,
                        enabled:
                            widget.onSetMetVia != null && !_isSettingMetVia,
                        isSaving: _isSettingMetVia,
                        onTap: _chooseMetVia,
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('partner-analysis-records-list'),
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, top: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selecting ? '已選 ${_selectedIds.length} 筆' : '分析紀錄',
                              style: AppTypography.titleSmall.copyWith(
                                color: AppColors.onBackgroundPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_selecting) ...[
                            _HeaderLinkButton(
                              key: const ValueKey(
                                'analysis-record-select-all',
                              ),
                              label: _allVisibleSelected ? '取消全選' : '全選',
                              onTap: _isDeleting ? null : _toggleSelectAllVisible,
                            ),
                            _HeaderLinkButton(
                              key: const ValueKey(
                                'analysis-record-select-cancel',
                              ),
                              label: '取消',
                              onTap: _isDeleting ? null : _exitSelection,
                            ),
                          ] else if (_canSelect)
                            _HeaderLinkButton(
                              key: const ValueKey('analysis-record-select'),
                              label: '選取',
                              onTap: _enterSelection,
                            ),
                        ],
                      ),
                    ),
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
                      const SizedBox(height: 16),
                    ],
                    if (_visibleRecords.isEmpty)
                      const _EmptyRecordsCard()
                    else
                      for (final record in _visibleRecords) ...[
                        _AnalysisRecordTile(
                          key: ValueKey('analysis-record-${record.id}'),
                          record: record,
                          platform: _platformFor(record),
                          selecting: _selecting,
                          selected: _selectedIds.contains(record.id),
                          onTap: _selecting
                              ? () => _toggleSelected(record)
                              : () => _openRecord(record),
                          onLongPress: _canSelect && !_selecting
                              ? () => _enterSelection(record.id)
                              : null,
                        ),
                        const SizedBox(height: 8),
                      ],
                    if (widget.archivedConversationCount > 0 &&
                        widget.onOpenArchivedConversations != null) ...[
                      const SizedBox(height: 6),
                      _ArchivedConversationsEntry(
                        count: widget.archivedConversationCount,
                        onTap: widget.onOpenArchivedConversations!,
                      ),
                    ],
                    if (_visibleRecords.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 17,
                            color: _archiveAccent.withValues(alpha: 0.72),
                          ),
                          const SizedBox(width: 8),
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
                  ],
                ),
              ),
              if (_selecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      key: const ValueKey('analysis-record-batch-delete'),
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
                      onPressed: _selectedIds.isEmpty || _isDeleting
                          ? null
                          : AppHaptics.onPress(() => _deleteSelected()),
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
                              '刪除（${_selectedIds.length}）',
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 批次刪除確認框：講清楚幾筆、不可復原（比照單筆刪的語氣）。
class _BatchDeleteConfirmDialog extends StatelessWidget {
  const _BatchDeleteConfirmDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return BrandAlertDialog(
      title: Text('刪除 $count 筆分析紀錄？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('選取的分析紀錄會永久刪除。'),
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
          key: const ValueKey('analysis-record-batch-delete-confirm'),
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

/// section 標題列右側的小文字鈕（選取／全選／取消）。
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
        foregroundColor: _archiveAccentBright,
      ),
      child: Text(
        label,
        style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 認識平台整寬列卡（對標示意稿）：粉紅愛心＋標籤＋鉛筆圓座＋chevron。
class _MetViaRow extends StatelessWidget {
  const _MetViaRow({
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
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: const ValueKey('analysis-record-met-via'),
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              if (isSaving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _archivePink,
                  ),
                )
              else
                const Icon(
                  Icons.favorite_rounded,
                  size: 20,
                  color: _archivePink,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (enabled && !isSaving) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Colors.white.withValues(alpha: 0.45),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    this.selecting = false,
    this.selected = false,
    this.onLongPress,
  });

  final AnalysisRecord record;
  final String? platform;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;
  final VoidCallback? onLongPress;

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
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        onLongPress: onLongPress,
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
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.95)
                  : accent.withValues(
                      alpha: platform == null ? 0.30 : 0.50,
                    ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                if (selecting) ...[
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    size: 22,
                    color: selected
                        ? accent
                        : Colors.white.withValues(alpha: 0.40),
                  ),
                  const SizedBox(width: 10),
                ],
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  color: _archiveAccent,
                  size: 21,
                ),
                const SizedBox(width: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    const SizedBox(height: 4),
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
          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 17,
                color: _archiveAccent.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '每筆都是獨立分析，可自行管理',
                  style: AppTypography.bodySmall.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ],
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
