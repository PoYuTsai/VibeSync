// lib/features/report/presentation/screens/my_report_screen.dart
//
// 2026-06-17 暗紫橘統一 (BrandKit migration): the Free-tier locked card and the
// three fl_chart surfaces (HeatTrendChart / ConversationComparisonChart /
// StageDistributionChart) moved off the light warm-glass GlassmorphicContainer
// onto the shared dark BrandKit surfaces (BrandSurfaceCard + BrandPrimaryButton),
// with chart labels/legends/lines recolored white / onBackgroundSecondary /
// orange for legibility on the dark brand surface. No report gating, provider,
// or navigation behavior changed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../../analysis/domain/entities/game_stage.dart';
import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../../user_profile/presentation/widgets/about_me_card.dart';
import '../../domain/entities/report_models.dart';
import '../../data/providers/report_providers.dart';
import '../widgets/heat_trend_chart.dart';
import '../widgets/conversation_comparison_chart.dart';
import '../widgets/partner_mindmap_card_list.dart';
import '../widgets/practice_temperature_chart.dart';
import '../widgets/report_overview_card.dart';
import '../widgets/report_subject_selector.dart';
import '../widgets/stage_distribution_chart.dart';

class MyReportScreen extends ConsumerWidget {
  const MyReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(subscriptionProvider);
    final report = ref.watch(reportDataProvider);
    final partners = ref.watch(partnerListProvider);
    // Stage labels 必須在 build 階段 eager 解析：ListView 的 itemBuilder 在
    // layout 階段執行，callback 裡用 ref.watch 會逸出 build contract。
    final stageLabels = {
      for (final p in partners) p.id: _latestStageLabel(ref, p.id),
    };

    // 對象選擇器＋單對象歷史序列。折線、平均與 delta 必須全部來自同一位
    // 對象的最近七次事件，不能混入 Conversation 全體摘要。
    final subjects = ref.watch(analysisSubjectsProvider);
    final requestedSubject = ref.watch(selectedReportSubjectProvider);
    final selectedSubject = requestedSubject != null &&
            subjects
                .any((subject) => subject.conversationId == requestedSubject)
        ? requestedSubject
        : (subjects.isEmpty ? null : subjects.first.conversationId);
    final selectedSubjectName = selectedSubject == null
        ? null
        : subjects
            .where((subject) => subject.conversationId == selectedSubject)
            .firstOrNull
            ?.name;
    final subjectPoints = selectedSubject == null
        ? const <HeatTrendPoint>[]
        : ref.watch(subjectHeatTrendProvider(selectedSubject));
    final subjectSummary = HeatTrendSummary.fromPoints(subjectPoints);
    final practicePoints = ref.watch(practiceTemperatureTrendProvider);
    // 歷史事件與 Conversation 最新快照是兩條合法資料流：只要任一條有資料，
    // 報告就應顯示。舊邏輯只看 Conversation，會把「只有練習紀錄」或仍保留
    // analyze 歷史的使用者誤判成全空。
    final hasConversationReport = report.totalConversations > 0;
    final hasInteractionHistory = subjects.isNotEmpty;
    final hasPracticeHistory = practicePoints.isNotEmpty;
    final hasAnyReport =
        hasConversationReport || hasInteractionHistory || hasPracticeHistory;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        const AboutMeCard(),
        const SizedBox(height: 24),
        if (subscription.isFreeUser)
          _lockedReportCard(context)
        else if (!hasAnyReport)
          ..._emptyStateContents()
        else ...[
          Text(
            '我的報告',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.ctaStart,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '把互動變化看懂',
            style: AppTypography.headlineLarge.copyWith(
              color: AppColors.onBackgroundPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '真實對話與練習分開計算：先看整體方向，再回到單一對象找原因。',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.76),
              height: 1.45,
            ),
          ),
          if (hasConversationReport) ...[
            const SizedBox(height: 20),
            ReportOverviewCard(
              averageScore: report.averageScore,
              scoreDelta: report.scoreDelta,
              totalConversations: report.totalConversations,
              stageDistributions: report.stageDistributions,
            ),
          ],
          if (hasConversationReport || hasInteractionHistory) ...[
            const SizedBox(height: 28),
            const _ReportStoryHeader(
              number: '01',
              title: '看一位對象的變化',
              body: '切換對象後，只比較同一個人的近期分析，不把不同人的分數混在一起。',
            ),
            const SizedBox(height: 12),
            if (subjects.isNotEmpty) ...[
              ReportSubjectSelector(
                subjects: subjects,
                selectedConversationId: selectedSubject,
                onSelected: (id) =>
                    ref.read(selectedReportSubjectProvider.notifier).state = id,
              ),
              const SizedBox(height: 12),
            ],
            HeatTrendChart(
              trendPoints: subjectSummary.points,
              averageScore: subjectSummary.averageScore,
              scoreDelta: subjectSummary.scoreDelta,
              contextLabel: selectedSubjectName,
              sampleCount: subjectSummary.sampleCount,
              emptyMessage: '再多分析幾次，就能比較對方每次互動的投入度',
            ),
          ],
          const SizedBox(height: 28),
          _ReportStoryHeader(
            number:
                hasConversationReport || hasInteractionHistory ? '02' : '01',
            title: '看自己的練習成長',
            body: '練習室量的是你的升溫能力，獨立於真實對話，不拿來猜對方心意。',
          ),
          const SizedBox(height: 12),
          PracticeTemperatureChart(points: practicePoints),
          if (hasConversationReport) ...[
            const SizedBox(height: 28),
            const _ReportStoryHeader(
              number: '03',
              title: '回到整體版圖',
              body: '最後再比較各段對話的最新訊號，以及目前最常停留的互動階段。',
            ),
            const SizedBox(height: 12),
            ConversationComparisonChart(
              comparisons: report.comparisons,
            ),
            const SizedBox(height: 16),
            StageDistributionChart(
              distributions: report.stageDistributions,
              totalConversations: report.totalConversations,
            ),
          ],
        ],
        const SizedBox(height: 32),
        // dogfood 決策 A：作戰板入口全 tier 可見，與上方報告 gating 無關
        PartnerMindMapCardList(
          partners: partners,
          stageLabelOf: (id) => stageLabels[id],
          onTapPartner: (id) => context.push('/partner/$id/mindmap'),
        ),
      ],
    );
  }

  /// 最新階段標籤：conversationsByPartnerProvider 由 repo `listByPartner`
  /// 保證 updatedAt desc，掃到第一個非空 currentGameStage 即最新。
  String? _latestStageLabel(WidgetRef ref, String partnerId) {
    final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
    for (final c in conversations) {
      final raw = c.currentGameStage?.trim();
      if (raw != null && raw.isNotEmpty) {
        final stage = GameStage.fromString(raw);
        return '${stage.emoji} ${stage.label}';
      }
    }
    return null;
  }

  Widget _lockedReportCard(BuildContext context) {
    return BrandSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandIconBadge(
              icon: Icons.lock_outline, size: 40, iconSize: 22),
          const SizedBox(height: 12),
          Text(
            '我的報告會在 Starter 解鎖',
            style: AppTypography.titleLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '升級後可以看互動雷達圖、歷史趨勢與不同對話的比較，知道自己哪裡正在進步。',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          BrandPrimaryButton(
            label: '查看升級方案',
            icon: Icons.workspace_premium,
            onPressed: () => context.push('/paywall'),
          ),
        ],
      ),
    );
  }

  List<Widget> _emptyStateContents() {
    return [
      const SizedBox(height: 80),
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart,
              size: 64,
              color: AppColors.onBackgroundSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              '還沒有分析數據',
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.onBackgroundPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '開始分析對話後，這裡會顯示你的進展報告',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ];
  }
}

class _ReportStoryHeader extends StatelessWidget {
  const _ReportStoryHeader({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.ctaStart.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: AppColors.ctaStart.withValues(alpha: 0.24),
            ),
          ),
          child: Text(
            number,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.ctaStart,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.titleLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: AppTypography.bodySmall.copyWith(
                  color:
                      AppColors.onBackgroundSecondary.withValues(alpha: 0.70),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
