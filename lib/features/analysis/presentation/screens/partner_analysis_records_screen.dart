import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
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

/// Read-only archive for a partner's completed, independent analysis cases.
///
/// The caller owns persistence and must pass archived records only; the current
/// record intentionally stays on the analyze-chat screen.
class PartnerAnalysisRecordsScreen extends StatefulWidget {
  const PartnerAnalysisRecordsScreen({
    super.key,
    required this.subjectName,
    required this.records,
    required this.platformForRecord,
    this.metVia,
    this.onSetMetVia,
    this.onDelete,
  });

  final String subjectName;
  final String? metVia;
  final List<AnalysisRecord> records;
  final AnalysisRecordPlatformResolver platformForRecord;
  final SetAnalysisPlatformCallback? onSetMetVia;
  final DeleteAnalysisRecordCallback? onDelete;

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
  final Set<String> _deletingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _records = _latestFirst(widget.records);
    _metVia = normalizeAnalysisPlatform(widget.metVia);
  }

  @override
  void didUpdateWidget(covariant PartnerAnalysisRecordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _records = _latestFirst(widget.records);
    _metVia = normalizeAnalysisPlatform(widget.metVia);
    if (_selectedPlatform != _allPlatforms &&
        !_platforms.contains(_selectedPlatform)) {
      _selectedPlatform = _allPlatforms;
    }
  }

  static List<AnalysisRecord> _latestFirst(List<AnalysisRecord> source) {
    final records = List<AnalysisRecord>.of(source);
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records;
  }

  String _platformLabel(AnalysisRecord record) =>
      normalizeAnalysisPlatform(widget.platformForRecord(record)) ?? '未分類';

  List<String> get _platforms {
    final result = <String>[];
    for (final record in _records) {
      final label = _platformLabel(record);
      if (!result.contains(label)) result.add(label);
    }
    return result;
  }

  List<AnalysisRecord> get _visibleRecords => _selectedPlatform == _allPlatforms
      ? _records
      : _records
          .where((record) => _platformLabel(record) == _selectedPlatform)
          .toList();

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

  Future<void> _confirmDelete(AnalysisRecord record) async {
    if (widget.onDelete == null || _deletingIds.contains(record.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.brandSurface2,
        title: Text(
          '刪除這筆分析？',
          style: AppTypography.titleLarge.copyWith(
            color: AppColors.onBackgroundPrimary,
          ),
        ),
        content: Text(
          '只會刪除這次獨立保存的聊天片段與分析，不會影響其他紀錄。',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('analysis-record-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '刪除',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingIds.add(record.id));
    try {
      await Future<void>.sync(() => widget.onDelete!(record));
      if (!mounted) return;
      setState(() {
        _records.removeWhere((item) => item.id == record.id);
        _deletingIds.remove(record.id);
        if (_selectedPlatform != _allPlatforms &&
            !_platforms.contains(_selectedPlatform)) {
          _selectedPlatform = _allPlatforms;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _deletingIds.remove(record.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('刪除失敗，請再試一次')),
      );
    }
  }

  void _openRecord(AnalysisRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnalysisRecordDetailScreen(
          record: record,
          platform: normalizeAnalysisPlatform(
            widget.platformForRecord(record),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjectName =
        widget.subjectName.trim().isEmpty ? '對方' : widget.subjectName.trim();
    return BrandScaffold(
      title: '$subjectName的分析紀錄',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            key: const ValueKey('partner-analysis-records-list'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              BrandSurfaceCard(
                elevated: false,
                borderRadius: 20,
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandIconBadge(
                      icon: Icons.inventory_2_outlined,
                      size: 38,
                      iconSize: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '每次分析獨立保存，不會串成逐字稿',
                            style: AppTypography.titleSmall.copyWith(
                              color: AppColors.onBackgroundPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '你可以從平台篩選舊紀錄，也可以單獨刪除不需要的分析。',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.onBackgroundSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _MetViaCard(
                value: _metVia,
                enabled: widget.onSetMetVia != null && !_isSettingMetVia,
                isSaving: _isSettingMetVia,
                onTap: _chooseMetVia,
              ),
              const SizedBox(height: 20),
              if (_records.isNotEmpty) ...[
                Text(
                  '分析來源',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    key: const ValueKey('analysis-record-platform-filters'),
                    scrollDirection: Axis.horizontal,
                    itemCount: _platforms.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final value =
                          index == 0 ? _allPlatforms : _platforms[index - 1];
                      final label = index == 0 ? '全部' : value;
                      return _PlatformFilterChip(
                        key: ValueKey('analysis-record-filter-$label'),
                        label: label,
                        selected: _selectedPlatform == value,
                        onSelected: () =>
                            setState(() => _selectedPlatform = value),
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
                    platform: _platformLabel(record),
                    deleting: _deletingIds.contains(record.id),
                    canDelete: widget.onDelete != null,
                    onTap: () => _openRecord(record),
                    onDelete: () => _confirmDelete(record),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetViaCard extends StatelessWidget {
  const _MetViaCard({
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
    return BrandSurfaceCard(
      elevated: false,
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: enabled ? onTap : null,
      child: Row(
        children: [
          const Icon(
            Icons.favorite_outline_rounded,
            color: AppColors.ctaStart,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '認識平台',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value == null ? '尚未設定' : '認識於 $value',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isSaving)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.ctaStart,
              ),
            )
          else if (enabled)
            const Icon(
              Icons.edit_outlined,
              color: AppColors.onBackgroundSecondary,
              size: 20,
            ),
        ],
      ),
    );
  }
}

class _PlatformFilterChip extends StatelessWidget {
  const _PlatformFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      selectedColor: AppColors.ctaStart,
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      side: BorderSide(
        color: selected
            ? AppColors.ctaStart
            : Colors.white.withValues(alpha: 0.14),
      ),
      labelStyle: AppTypography.labelLarge.copyWith(
        color: selected ? Colors.white : AppColors.onBackgroundSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _AnalysisRecordTile extends StatelessWidget {
  const _AnalysisRecordTile({
    super.key,
    required this.record,
    required this.platform,
    required this.deleting,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
  });

  final AnalysisRecord record;
  final String platform;
  final bool deleting;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final localDate = record.createdAt.toLocal();
    return BrandSurfaceCard(
      borderRadius: 18,
      padding: EdgeInsets.zero,
      onTap: deleting ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _MiniBadge(label: platform),
                      Text(
                        DateFormat('yyyy/MM/dd HH:mm').format(localDate),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.onBackgroundSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    record.previewText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        '熱度 ${record.enthusiasmScore}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.ctaStart,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (record.gameStageLabel.trim().isNotEmpty)
                        Text(
                          record.gameStageLabel,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onBackgroundSecondary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (deleting)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.ctaStart,
                  ),
                ),
              )
            else if (canDelete)
              IconButton(
                key: ValueKey('analysis-record-delete-${record.id}'),
                tooltip: '刪除這筆分析',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.onBackgroundSecondary,
                  size: 21,
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.ctaStart,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyRecordsCard extends StatelessWidget {
  const _EmptyRecordsCard();

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      elevated: false,
      borderRadius: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 34,
              color: AppColors.onBackgroundSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              '還沒有舊的分析紀錄',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '目前這次分析會留在主畫面，下一次完成後才會收進來。',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
