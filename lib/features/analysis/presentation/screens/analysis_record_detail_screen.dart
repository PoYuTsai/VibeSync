import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../../shared/widgets/dimension_radar_chart.dart';
import '../../../../shared/widgets/game_stage_indicator.dart';
import '../../domain/entities/analysis_models.dart';
import '../../domain/entities/analysis_record.dart';
import '../../domain/entities/enthusiasm_level.dart';
import '../widgets/analysis_platform_picker.dart';
import '../widgets/reply_style_card.dart';

enum _RecordDetailAction { delete }

const _detailAccent = Color(0xFF9D78F5);
const _detailAccentBright = Color(0xFFC68BFF);
const _detailPink = Color(0xFFFF5DA8);
const _detailPanel = Color(0xFF15152A);
const _detailPanelRaised = Color(0xFF24172F);

/// Read-only replay of one independent analysis case.
class AnalysisRecordDetailScreen extends StatefulWidget {
  const AnalysisRecordDetailScreen({
    super.key,
    required this.record,
    this.platform,
    this.onDelete,
  });

  final AnalysisRecord record;
  final String? platform;
  final Future<void> Function()? onDelete;

  @override
  State<AnalysisRecordDetailScreen> createState() =>
      _AnalysisRecordDetailScreenState();
}

class _AnalysisRecordDetailScreenState
    extends State<AnalysisRecordDetailScreen> {
  late final AnalysisResult? _result = _parseResult();
  bool _deleting = false;

  AnalysisResult? _parseResult() {
    try {
      final decoded = jsonDecode(widget.record.analysisSnapshotJson);
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

  Future<void> _requestDelete() async {
    if (_deleting || widget.onDelete == null) return;
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
          '會刪除這次分析的保存內容，不會影響其他紀錄；刪除後無法復原。',
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
    if (!mounted || confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await widget.onDelete!();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('刪除失敗，請再試一次')),
      );
    }
  }

  Future<void> _copyRecommendation(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已複製建議')),
    );
  }

  void _showReplyCopyFeedback(String _, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final localDate = record.createdAt.toLocal();
    final platform = normalizeAnalysisPlatform(widget.platform);
    final title = '${DateFormat('M 月 d 日').format(localDate)}的分析';

    return BrandScaffold(
      title: title,
      actions: [
        if (_deleting)
          const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _detailAccentBright,
              ),
            ),
          )
        else if (widget.onDelete != null)
          PopupMenuButton<_RecordDetailAction>(
            key: const ValueKey('analysis-record-detail-menu'),
            tooltip: '管理這筆分析',
            onSelected: (action) {
              if (action == _RecordDetailAction.delete) {
                _requestDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                key: ValueKey('analysis-record-delete-action'),
                value: _RecordDetailAction.delete,
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, color: AppColors.error),
                    SizedBox(width: 10),
                    Text('刪除這筆分析'),
                  ],
                ),
              ),
            ],
          ),
      ],
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            key: const ValueKey('analysis-record-detail'),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              _RecordContextHeader(
                subjectName: record.subjectName,
                platform: platform,
                createdAt: localDate,
                messageCount: record.messages.length,
              ),
              const SizedBox(height: 12),
              _ScoreSnapshotCard(
                score: record.enthusiasmScore,
                stage: record.gameStageLabel,
              ),
              const SizedBox(height: 22),
              const _DetailSectionTitle(title: '保存的對話片段'),
              const SizedBox(height: 9),
              _ConversationSnapshotCard(record: record),
              const SizedBox(height: 22),
              const _DetailSectionTitle(title: '當次分析'),
              const SizedBox(height: 9),
              if (_result == null)
                const _UnavailableAnalysisCard()
              else
                _SavedAnalysisCard(
                  result: _result,
                  onCopyRecommendation: _copyRecommendation,
                  onReplyCopied: _showReplyCopyFeedback,
                ),
              const SizedBox(height: 18),
              Text(
                '這是當次分析的快照，不會和其他紀錄混在一起',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary.withValues(
                    alpha: 0.72,
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

class _RecordContextHeader extends StatelessWidget {
  const _RecordContextHeader({
    required this.subjectName,
    required this.platform,
    required this.createdAt,
    required this.messageCount,
  });

  final String subjectName;
  final String? platform;
  final DateTime createdAt;
  final int messageCount;

  @override
  Widget build(BuildContext context) {
    final displayName = subjectName.trim().isEmpty ? '對方' : subjectName.trim();
    return _ArchivePanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _detailPink.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _detailPink.withValues(alpha: 0.34),
              ),
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              color: _detailPink,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('M 月 d 日 · HH:mm').format(createdAt)} · $messageCount 則訊息',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    const _DetailBadge(
                      label: '獨立分析',
                      accent: _detailPink,
                    ),
                    if (platform != null)
                      _DetailBadge(
                        label: platform!,
                        accent: _detailAccentBright,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreSnapshotCard extends StatelessWidget {
  const _ScoreSnapshotCard({
    required this.score,
    required this.stage,
  });

  final int score;
  final String stage;

  String _descriptionFor(EnthusiasmLevel level) {
    switch (level) {
      case EnthusiasmLevel.cold:
        return '這次投入訊號偏少';
      case EnthusiasmLevel.warm:
        return '這次有一定回應';
      case EnthusiasmLevel.hot:
        return '這次投入訊號明顯';
      case EnthusiasmLevel.veryHot:
        return '這次投入訊號很多';
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = EnthusiasmLevel.fromScore(score);
    final normalizedStage = stage.trim();
    return Container(
      key: const ValueKey('analysis-record-score-card'),
      padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _detailPanelRaised.withValues(alpha: 0.96),
            const Color(0xFF11152D),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _detailPink.withValues(alpha: 0.64),
        ),
        boxShadow: [
          BoxShadow(
            color: _detailPink.withValues(alpha: 0.10),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$score',
            style: AppTypography.headlineLarge.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontSize: 58,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本次投入 · ${level.label}',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _descriptionFor(level),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onBackgroundSecondary,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '只反映這次互動中的文字訊號',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary.withValues(
                      alpha: 0.72,
                    ),
                  ),
                ),
                if (normalizedStage.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _DetailBadge(
                    label: normalizedStage,
                    accent: _detailAccentBright,
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

class _ConversationSnapshotCard extends StatelessWidget {
  const _ConversationSnapshotCard({required this.record});

  final AnalysisRecord record;

  @override
  Widget build(BuildContext context) {
    return _ArchivePanel(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '共 ${record.messages.length} 則訊息',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final message in record.messages)
            _ArchivedMessageBubble(message: message),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 15,
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.62),
              ),
              const SizedBox(width: 6),
              Text(
                '保留當次送出的內容',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary.withValues(
                    alpha: 0.66,
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

class _ArchivedMessageBubble extends StatelessWidget {
  const _ArchivedMessageBubble({required this.message});

  final AnalysisRecordMessage message;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isFromMe;
    final accent = isMe ? const Color(0xFFFF8B68) : _detailAccentBright;
    final quote = message.quotedReplyPreview?.trim();
    final quoteLabel = message.quotedReplyPreviewIsFromMe == true
        ? '引用我說的'
        : message.quotedReplyPreviewIsFromMe == false
            ? '引用對方說的'
            : '引用訊息';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.74,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14).copyWith(
            bottomRight: isMe ? const Radius.circular(5) : null,
            bottomLeft: isMe ? null : const Radius.circular(5),
          ),
          border: Border.all(color: accent.withValues(alpha: 0.34)),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              isMe ? '我說' : '她說',
              style: AppTypography.bodySmall.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            if (quote != null && quote.isNotEmpty) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                  border: Border(
                    left: BorderSide(
                      color: accent.withValues(alpha: 0.72),
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  '$quoteLabel：$quote',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onBackgroundSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            Text(
              message.content,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundPrimary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedAnalysisCard extends StatelessWidget {
  const _SavedAnalysisCard({
    required this.result,
    required this.onCopyRecommendation,
    required this.onReplyCopied,
  });

  final AnalysisResult result;
  final Future<void> Function(String content) onCopyRecommendation;
  final void Function(String text, String message) onReplyCopied;

  static const _replyOrder = <String>[
    'extend',
    'resonate',
    'tease',
    'humor',
    'coldRead',
  ];

  String get _recommendationContent {
    final content = result.recommendation.content.trim();
    if (content.isNotEmpty) return content;
    return result.recommendation.replySegments
        .map((segment) => segment.reply.trim())
        .where((reply) => reply.isNotEmpty)
        .join('\n');
  }

  List<String> get _availableReplyTypes => _replyOrder
      .where((type) => result.replies[type]?.trim().isNotEmpty == true)
      .toList();

  @override
  Widget build(BuildContext context) {
    final psychology = result.psychology.subtext.trim();
    final strategy = result.strategy.trim();
    final recommendation = _recommendationContent;
    final reason = result.recommendation.reason.trim();
    final explanation = result.recommendation.psychology.trim();
    final reminder = result.reminder?.trim() ?? '';
    final dimensions = result.dimensionScores;
    final healthCheck = result.healthCheck;
    final replyTypes = _availableReplyTypes;
    final rawGameStage = result.rawResponse?['gameStage'];
    final rawTopicDepth = result.rawResponse?['topicDepth'];
    final hasGameStage =
        rawGameStage is Map && rawGameStage['current'] is String;
    final hasPsychology = psychology.isNotEmpty ||
        result.psychology.shitTest?.trim().isNotEmpty == true ||
        result.psychology.qualificationSignal;
    final hasStrategy = strategy.isNotEmpty;
    final hasTopicDepth =
        rawTopicDepth is Map && rawTopicDepth['current'] is String;
    final hasHealthCheck = healthCheck != null &&
        (healthCheck.issues.isNotEmpty || healthCheck.suggestions.isNotEmpty);
    final hasReplies = replyTypes.isNotEmpty;
    final hasRecommendation = recommendation.isNotEmpty ||
        reason.isNotEmpty ||
        explanation.isNotEmpty;
    final hasReminder = reminder.isNotEmpty;
    final hasContentAfterWarning = dimensions != null ||
        hasGameStage ||
        hasPsychology ||
        hasStrategy ||
        hasTopicDepth ||
        hasHealthCheck ||
        hasReplies ||
        hasRecommendation ||
        hasReminder;
    final hasAnyContent = result.shouldGiveUp ||
        dimensions != null ||
        hasGameStage ||
        hasPsychology ||
        hasStrategy ||
        hasTopicDepth ||
        hasHealthCheck ||
        hasReplies ||
        hasRecommendation ||
        hasReminder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.shouldGiveUp) ...[
          Container(
            key: const ValueKey('analysis-record-give-up-warning'),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.34),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '這段互動目前不建議再投入，先保護自己的時間與情緒成本。',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasContentAfterWarning) const SizedBox(height: 12),
        ],
        if (dimensions != null)
          DimensionRadarChart(
            key: const ValueKey('analysis-record-dimensions'),
            scores: DimensionScores(
              heat: dimensions['heat'] ?? 50,
              engagement: dimensions['engagement'] ?? 50,
              topicDepth: dimensions['topicDepth'] ?? 50,
              replyWillingness: dimensions['replyWillingness'] ?? 50,
              emotionalConnection: dimensions['emotionalConnection'] ?? 50,
            ),
          ),
        if (dimensions != null && hasGameStage) const SizedBox(height: 12),
        if (hasGameStage)
          GameStageIndicator(
            key: const ValueKey('analysis-record-game-stage'),
            currentStage: result.gameStage.current,
            status: result.gameStage.status,
            nextStep: result.gameStage.nextStep.trim().isEmpty
                ? null
                : result.gameStage.nextStep.trim(),
          ),
        if ((dimensions != null || hasGameStage) && hasPsychology)
          const SizedBox(height: 12),
        if (hasPsychology)
          _ArchivePanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🧠', style: TextStyle(fontSize: 19)),
                    const SizedBox(width: 8),
                    Text(
                      '她話裡的意思',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (psychology.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Text(
                    psychology,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
                if (result.psychology.shitTest?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.34),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '互動測試訊號',
                          style: AppTypography.labelLarge.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.psychology.shitTest!.trim(),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.onBackgroundSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (result.psychology.qualificationSignal) ...[
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 17,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '她有主動投入訊號',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        if ((dimensions != null || hasGameStage || hasPsychology) &&
            hasStrategy)
          const SizedBox(height: 12),
        if (hasStrategy)
          _ArchivePanel(
            padding: const EdgeInsets.all(14),
            child: _AnalysisTextBlock(
              icon: Icons.route_outlined,
              title: '互動策略',
              content: strategy,
            ),
          ),
        if ((dimensions != null ||
                hasGameStage ||
                hasPsychology ||
                hasStrategy) &&
            hasTopicDepth)
          const SizedBox(height: 12),
        if (hasTopicDepth)
          _ArchivePanel(
            padding: const EdgeInsets.all(14),
            child: _AnalysisTextBlock(
              icon: Icons.layers_outlined,
              title: '話題深度・${result.topicDepth.current.label}',
              content: result.topicDepth.suggestion.trim().isEmpty
                  ? '這次對話停留在${result.topicDepth.current.label}。'
                  : result.topicDepth.suggestion.trim(),
            ),
          ),
        if ((dimensions != null ||
                hasGameStage ||
                hasPsychology ||
                hasStrategy ||
                hasTopicDepth) &&
            hasHealthCheck)
          const SizedBox(height: 12),
        if (hasHealthCheck)
          _ArchivePanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🩺', style: TextStyle(fontSize: 19)),
                    const SizedBox(width: 8),
                    Text(
                      '對話健檢',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.onBackgroundPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (healthCheck.issues.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final issue in healthCheck.issues)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 17,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              issue,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.onBackgroundSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (healthCheck.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    '改善建議',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final suggestion in healthCheck.suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 17,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              suggestion,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.onBackgroundSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        if ((dimensions != null ||
                hasGameStage ||
                hasPsychology ||
                hasStrategy ||
                hasTopicDepth ||
                hasHealthCheck) &&
            hasReplies)
          const SizedBox(height: 20),
        if (hasReplies) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '接法建議・${replyTypes.length} 種風格',
                  style: AppTypography.titleLarge.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '← 左右滑動',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onBackgroundSecondary.withValues(
                    alpha: 0.66,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            key: const ValueKey('analysis-record-reply-styles'),
            height: 360,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final type in replyTypes)
                  ReplyStyleCard(
                    type: type,
                    content: result.replies[type]!,
                    option: result.replyOptions[type],
                    isRecommended: result.recommendation.pick.trim() == type,
                    onCopy: onReplyCopied,
                  ),
              ],
            ),
          ),
        ],
        if (hasReplies && hasRecommendation) const SizedBox(height: 16),
        if (hasRecommendation) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _detailPink.withValues(alpha: 0.13),
                  _detailAccent.withValues(alpha: 0.09),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _detailPink.withValues(alpha: 0.62),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '建議接法',
                  style: AppTypography.titleSmall.copyWith(
                    color: _detailPink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (recommendation.isNotEmpty)
                  Text(
                    recommendation,
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '為什麼這樣回',
                    style: AppTypography.labelLarge.copyWith(
                      color: _detailPink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reason,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
                if (explanation.isNotEmpty && explanation != reason) ...[
                  const SizedBox(height: 8),
                  Text(
                    explanation,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary.withValues(
                        alpha: 0.82,
                      ),
                      height: 1.45,
                    ),
                  ),
                ],
                if (recommendation.isNotEmpty) ...[
                  const SizedBox(height: 13),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey(
                        'analysis-record-copy-recommendation',
                      ),
                      onPressed: () => onCopyRecommendation(recommendation),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _detailAccentBright,
                        side: BorderSide(
                          color: _detailAccent.withValues(alpha: 0.72),
                        ),
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('複製這段'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if ((result.shouldGiveUp ||
                dimensions != null ||
                hasGameStage ||
                hasPsychology ||
                hasStrategy ||
                hasTopicDepth ||
                hasHealthCheck ||
                hasReplies ||
                hasRecommendation) &&
            hasReminder)
          const SizedBox(height: 12),
        if (hasReminder)
          _ArchivePanel(
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💬', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    reminder,
                    key: const ValueKey('analysis-record-reminder'),
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onBackgroundSecondary,
                      fontStyle: FontStyle.italic,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (!hasAnyContent)
          _ArchivePanel(
            padding: const EdgeInsets.all(14),
            child: Text(
              '這筆紀錄沒有可顯示的文字建議。',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _AnalysisTextBlock extends StatelessWidget {
  const _AnalysisTextBlock({
    required this.icon,
    required this.title,
    required this.content,
  });

  final IconData icon;
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _detailAccent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: _detailAccent.withValues(alpha: 0.28),
            ),
          ),
          child: Icon(icon, size: 18, color: _detailAccentBright),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
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
          ),
        ),
      ],
    );
  }
}

class _DetailSectionTitle extends StatelessWidget {
  const _DetailSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.titleLarge.copyWith(
        color: AppColors.onBackgroundPrimary,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _DetailBadge extends StatelessWidget {
  const _DetailBadge({
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.42)),
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ArchivePanel extends StatelessWidget {
  const _ArchivePanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _detailPanelRaised.withValues(alpha: 0.88),
            _detailPanel.withValues(alpha: 0.96),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }
}

class _UnavailableAnalysisCard extends StatelessWidget {
  const _UnavailableAnalysisCard();

  @override
  Widget build(BuildContext context) {
    return _ArchivePanel(
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
