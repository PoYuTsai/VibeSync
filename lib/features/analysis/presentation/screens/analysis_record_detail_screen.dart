import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../conversation/presentation/widgets/message_bubble.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/analysis_record.dart';
import '../widgets/analysis_platform_picker.dart';

/// Read-only replay of one independent analysis case.
class AnalysisRecordDetailScreen extends StatelessWidget {
  const AnalysisRecordDetailScreen({
    super.key,
    required this.record,
    this.platform,
  });

  final AnalysisRecord record;
  final String? platform;

  AnalysisResult? _parseResult() {
    try {
      final decoded = jsonDecode(record.analysisSnapshotJson);
      if (decoded is! Map) return null;
      final json = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      return AnalysisResult.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      // A corrupt legacy snapshot should not expose raw JSON or block the
      // preserved chat fragment from being read.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _parseResult();
    final platformLabel = normalizeAnalysisPlatform(platform) ?? '未分類';
    return BrandScaffold(
      title: '分析紀錄',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            key: const ValueKey('analysis-record-detail'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _RecordContextHeader(
                subjectName: record.subjectName,
                platform: platformLabel,
                createdAt: record.createdAt,
              ),
              const SizedBox(height: 18),
              Text(
                '當時的聊天片段',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.ctaStart.withValues(alpha: 0.24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    for (final message in record.messages)
                      MessageBubble(message: message.toMessage()),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                '當時的建議',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (result == null)
                const _UnavailableAnalysisCard()
              else
                _SavedAnalysisCard(record: record, result: result),
              const SizedBox(height: 14),
              Text(
                '這是當時獨立保存的結果，不會隨後續聊天更新。',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordContextHeader extends StatelessWidget {
  const _RecordContextHeader({
    required this.subjectName,
    required this.platform,
    required this.createdAt,
  });

  final String subjectName;
  final String platform;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final displayName = subjectName.trim().isEmpty ? '對方' : subjectName.trim();
    return BrandSurfaceCard(
      elevated: false,
      borderRadius: 18,
      padding: const EdgeInsets.all(15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandIconBadge(
            icon: Icons.history_rounded,
            size: 38,
            iconSize: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$displayName・$platform',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('yyyy/MM/dd HH:mm').format(createdAt.toLocal()),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '每次分析獨立保存，不會串成逐字稿',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
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

class _SavedAnalysisCard extends StatelessWidget {
  const _SavedAnalysisCard({
    required this.record,
    required this.result,
  });

  final AnalysisRecord record;
  final AnalysisResult result;

  String get _recommendationContent {
    final content = result.recommendation.content.trim();
    if (content.isNotEmpty) return content;
    return result.recommendation.replySegments
        .map((segment) => segment.reply.trim())
        .where((reply) => reply.isNotEmpty)
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final recommendation = result.recommendation;
    final stage = record.gameStageLabel.trim().isNotEmpty
        ? record.gameStageLabel.trim()
        : result.gameStage.current.label;
    return BrandSurfaceCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AnalysisMetricChip(
                icon: Icons.local_fire_department_outlined,
                label: '熱度 ${record.enthusiasmScore}',
              ),
              if (stage.isNotEmpty)
                _AnalysisMetricChip(
                  icon: Icons.flag_outlined,
                  label: stage,
                ),
            ],
          ),
          if (result.strategy.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _AnalysisTextSection(
              title: '互動策略',
              content: result.strategy.trim(),
            ),
          ],
          if (result.psychology.subtext.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _AnalysisTextSection(
              title: '對話解讀',
              content: result.psychology.subtext.trim(),
            ),
          ],
          if (_recommendationContent.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.brandInk.withValues(alpha: 0.46),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.ctaStart.withValues(alpha: 0.28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '當時建議回覆',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.ctaStart,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _recommendationContent,
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (recommendation.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _AnalysisTextSection(
              title: '為什麼推薦',
              content: recommendation.reason.trim(),
            ),
          ],
          if (recommendation.psychology.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _AnalysisTextSection(
              title: '為什麼這樣接',
              content: recommendation.psychology.trim(),
            ),
          ],
          if (_recommendationContent.isEmpty &&
              result.strategy.trim().isEmpty &&
              result.psychology.subtext.trim().isEmpty)
            Text(
              '這筆紀錄沒有可顯示的文字建議。',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _AnalysisMetricChip extends StatelessWidget {
  const _AnalysisMetricChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.ctaStart.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.ctaStart),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisTextSection extends StatelessWidget {
  const _AnalysisTextSection({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.labelLarge.copyWith(
            color: AppColors.ctaStart,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _UnavailableAnalysisCard extends StatelessWidget {
  const _UnavailableAnalysisCard();

  @override
  Widget build(BuildContext context) {
    return BrandSurfaceCard(
      elevated: false,
      borderRadius: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.onBackgroundSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '這筆分析內容暫時無法顯示，但上方聊天片段仍完整保留。',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
