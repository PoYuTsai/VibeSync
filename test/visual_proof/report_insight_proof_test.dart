import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/screens/my_report_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/shared/widgets/gradient_background.dart';

import 'proof_support.dart';

class _PaidSubscription extends SubscriptionNotifier {
  _PaidSubscription() {
    state = const SubscriptionState(tier: SubscriptionTierHelper.starter);
  }
}

class _ProofProfile extends UserProfileController {
  @override
  Future<UserProfile?> build() async => UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        secondaryStyle: InteractionStyle.humorous,
        practiceGoals: const [
          PracticeGoal.softInvite,
          PracticeGoal.explainLess,
        ],
        topicSeeds: const [TopicSeed.coffee, TopicSeed.travel, TopicSeed.pets],
        updatedAt: DateTime(2026, 7, 19),
      );
}

ReportData _report() => ReportData(
      trendPoints: const [],
      averageScore: 67,
      scoreDelta: 11,
      comparisons: const [
        ConversationComparison(name: '小雲', score: 76),
        ConversationComparison(name: '安安', score: 64),
        ConversationComparison(name: 'Vivi', score: 51),
      ],
      stageDistributions: const [
        StageDistribution(stageName: '破冰', count: 1),
        StageDistribution(stageName: '升溫', count: 3),
        StageDistribution(stageName: '深入', count: 1),
      ],
      totalConversations: 5,
    );

List<AnalysisHistoryEvent> _events() => [
      for (final entry in const [
        (id: 'a1', day: 1, score: 48),
        (id: 'a2', day: 5, score: 57),
        (id: 'a3', day: 9, score: 62),
        (id: 'a4', day: 15, score: 76),
      ])
        AnalysisHistoryEvent.analyze(
          id: entry.id,
          createdAt: DateTime(2026, 7, entry.day),
          conversationId: 'c-cloud',
          subjectName: '小雲',
          enthusiasmScore: entry.score,
          gameStageLabel: 'premise',
        ),
      AnalysisHistoryEvent.analyze(
        id: 'b1',
        createdAt: DateTime(2026, 7, 14),
        conversationId: 'c-an',
        subjectName: '安安',
        enthusiasmScore: 64,
        gameStageLabel: 'opening',
      ),
      for (final entry in const [
        (id: 'p1', day: 2, score: 34),
        (id: 'p2', day: 7, score: 46),
        (id: 'p3', day: 12, score: 58),
        (id: 'p4', day: 18, score: 69),
      ])
        AnalysisHistoryEvent.practice(
          id: entry.id,
          createdAt: DateTime(2026, 7, entry.day),
          profileId: 'practice_girl_001',
          roundIndex: 1,
          temperatureScore: entry.score,
        ),
    ];

List<Partner> _partners() => [
      Partner(
        id: 'p-cloud',
        name: '小雲',
        ownerUserId: 'u1',
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 18),
      ),
      Partner(
        id: 'p-an',
        name: '安安',
        ownerUserId: 'u1',
        createdAt: DateTime(2026, 7, 2),
        updatedAt: DateTime(2026, 7, 17),
      ),
    ];

void main() {
  setUpAll(loadProofFonts);

  testWidgets('我的報告資訊敘事視覺證據', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 3600),
      settle: const Duration(milliseconds: 700),
      child: GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: ProviderScope(
            overrides: [
              subscriptionProvider.overrideWith((ref) => _PaidSubscription()),
              reportDataProvider.overrideWithValue(_report()),
              analysisHistoryEventsProvider.overrideWithValue(_events()),
              partnerListProvider.overrideWithValue(_partners()),
              conversationsByPartnerProvider
                  .overrideWith((ref, id) => const []),
              userProfileControllerProvider.overrideWith(_ProofProfile.new),
            ],
            child: const MyReportScreen(),
          ),
        ),
      ),
      outPath: outPath('report_insight_after.png'),
    );
  });
}
