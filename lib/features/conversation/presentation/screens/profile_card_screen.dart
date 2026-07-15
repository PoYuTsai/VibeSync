// lib/features/conversation/presentation/screens/profile_card_screen.dart
//
// 2026-06-17 暗紫橘統一 (BrandKit migration): the info cards / section titles /
// tag chips now use the shared BrandKit primitives (BrandSurfaceCard +
// BrandSectionHeader) and brand tokens instead of the light warm-glass
// GlassmorphicContainer + glassText* system, matching the shipped 關於我/作戰板
// dark surface look. The animated GradientBackground (dynamic bokeh) and
// BubbleAvatar are intentionally kept as-is — only the surfaces on top migrate.
// Display tag chips have no BrandKit equivalent (BrandChoiceChip is for
// selectable chips), so their styling is replicated inline with brand tokens.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../data/providers/conversation_providers.dart';
import '../../domain/entities/conversation.dart';
import '../../../analysis/domain/entities/enthusiasm_level.dart';
import '../../../analysis/domain/entities/game_stage.dart';

class ProfileCardScreen extends ConsumerWidget {
  final String conversationId;

  const ProfileCardScreen({
    super.key,
    required this.conversationId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref.watch(conversationProvider(conversationId));

    if (conversation == null) {
      return GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: brandAppBar(title: '對方檔案'),
          body: const Center(
            child: Text(
              '找不到對話',
              style: TextStyle(color: AppColors.onBackgroundSecondary),
            ),
          ),
        ),
      );
    }

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: brandAppBar(title: '對方檔案'),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Avatar + Name
              Center(
                child: Column(
                  children: [
                    BubbleAvatar(
                      label: conversation.name.isNotEmpty
                          ? conversation.name.characters.first
                          : '?',
                      isMe: false,
                      size: 80,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      conversation.name,
                      style: AppTypography.headlineMedium.copyWith(
                        color: AppColors.onBackgroundPrimary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Info Card 1: Basic Info
              BrandSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandSectionHeader(title: '基本資訊'),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      '認識場景',
                      conversation.sessionContext?.meetingContext.label ?? '--',
                    ),
                    _buildInfoRow(
                      '交往時長',
                      conversation.sessionContext?.duration.label ?? '--',
                    ),
                    _buildInfoRow(
                      '目前階段',
                      _stageLabel(conversation.currentGameStage),
                    ),
                    _buildHeatRow(conversation.lastEnthusiasmScore),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Info Card 2: Trend
              BrandSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandSectionHeader(title: '互動趨勢'),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      '對話輪數',
                      '${conversation.currentRound}',
                    ),
                    _buildInfoRow(
                      '總訊息數',
                      '${conversation.messages.length}',
                    ),
                    _buildInfoRow(
                      '最後互動',
                      DateFormat('yyyy/MM/dd HH:mm')
                          .format(conversation.updatedAt),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Info Card 2.5: Target Profile (if available)
              _buildTargetProfileCard(conversation),

              // Info Card 3: AI Summary
              _buildSummaryCard(conversation.summaries),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _extractTargetProfile(Conversation conversation) {
    final snapshotJson = conversation.lastAnalysisSnapshotJson;
    if (snapshotJson == null || snapshotJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(snapshotJson);
      if (decoded is! Map) return null;
      return decoded['targetProfile'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Widget _buildTargetProfileCard(Conversation conversation) {
    final targetProfile = _extractTargetProfile(conversation);
    if (targetProfile == null) return const SizedBox.shrink();

    final interests =
        (targetProfile['interests'] as List?)?.cast<String>() ?? [];
    final traits = (targetProfile['traits'] as List?)?.cast<String>() ?? [];
    final notes = (targetProfile['notes'] as List?)?.cast<String>() ?? [];

    if (interests.isEmpty && traits.isEmpty && notes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        BrandSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandSectionHeader(title: '她的特質'),
              if (interests.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '興趣',
                  style: AppTypography.labelMedium.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: interests
                      .map((interest) => _buildColoredChip(
                            interest,
                            AppColors.ctaStart.withValues(alpha: 0.16),
                            AppColors.ctaStart,
                          ))
                      .toList(),
                ),
              ],
              if (traits.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '性格',
                  style: AppTypography.labelMedium.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: traits
                      .map((trait) => _buildColoredChip(
                            trait,
                            AppColors.primaryLight.withValues(alpha: 0.18),
                            AppColors.onBackgroundSecondary,
                          ))
                      .toList(),
                ),
              ],
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '備註',
                  style: AppTypography.labelMedium.copyWith(
                    color:
                        AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: notes
                      .map((note) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '  •  ',
                                  style: TextStyle(color: Colors.white),
                                ),
                                Expanded(
                                  child: Text(
                                    note,
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildColoredChip(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        text,
        style: AppTypography.labelMedium.copyWith(
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatRow(int? score) {
    if (score == null) {
      return _buildInfoRow('本次投入', '--');
    }
    final level = EnthusiasmLevel.fromScore(score);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '本次投入',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.75),
            ),
          ),
          Text(
            '$score ${level.emoji} ${level.label}',
            style: AppTypography.bodyMedium.copyWith(
              color: level.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(List<dynamic>? summaries) {
    if (summaries != null && summaries.isNotEmpty) {
      return BrandSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandSectionHeader(title: 'AI 記住的重點'),
            const SizedBox(height: 12),
            for (final summary in summaries) ...[
              Text(
                summary.content,
                style: AppTypography.bodyMedium.copyWith(
                  color:
                      AppColors.onBackgroundSecondary.withValues(alpha: 0.82),
                ),
              ),
              if (summary.keyTopics.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final topic in summary.keyTopics) _buildChip(topic),
                  ],
                ),
              ],
              if (summary.sharedInterests.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final interest in summary.sharedInterests)
                      _buildChip(interest),
                  ],
                ),
              ],
              const SizedBox(height: 12),
            ],
          ],
        ),
      );
    }

    return BrandSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandSectionHeader(title: 'AI 記住的重點'),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '對話超過 15 輪後，AI 會自動整理重點',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ctaStart.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        text,
        style: AppTypography.labelMedium.copyWith(
          color: AppColors.ctaStart,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _stageLabel(String? stageStr) {
    if (stageStr == null || stageStr.isEmpty) return '--';
    final stage = GameStage.fromString(stageStr);
    switch (stage) {
      case GameStage.opening:
        return '破冰';
      case GameStage.premise:
        return '升溫';
      case GameStage.qualification:
        return '深入';
      case GameStage.narrative:
        return '連結';
      case GameStage.close:
        return '邀約';
    }
  }
}
