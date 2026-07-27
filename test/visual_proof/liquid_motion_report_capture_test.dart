import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/screens/my_report_screen.dart';
import 'package:vibesync/features/report/presentation/widgets/heat_trend_chart.dart';
import 'package:vibesync/features/report/presentation/widgets/practice_temperature_chart.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/shared/widgets/gradient_background.dart';

import 'proof_support.dart';

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

class _NullUserProfileController extends UserProfileController {
  @override
  Future<UserProfile?> build() async => null;
}

const _emptyReport = ReportData(
  trendPoints: [],
  averageScore: 0,
  scoreDelta: 0,
  comparisons: [],
  stageDistributions: [],
  totalConversations: 0,
);

void main() {
  setUpAll(loadProofFonts);

  testWidgets('free report liquid upgrade card', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(430, 1200),
      settle: const Duration(milliseconds: 2100),
      child: ProviderScope(
        overrides: [
          subscriptionProvider.overrideWith(
            (_) => _SeededSubscriptionNotifier(
              const SubscriptionState(tier: SubscriptionTierHelper.free),
            ),
          ),
          reportDataProvider.overrideWithValue(_emptyReport),
          analysisHistoryEventsProvider
              .overrideWithValue(const <AnalysisHistoryEvent>[]),
          conversationsProvider.overrideWithValue(const []),
          partnerListProvider.overrideWithValue(const []),
          conversationsByPartnerProvider.overrideWith((_, __) => const []),
          userProfileControllerProvider
              .overrideWith(_NullUserProfileController.new),
        ],
        child: const MyReportScreen(),
      ),
      outPath: outPath('liquid_upgrade_card.png'),
    );
  });

  testWidgets('practice growth arrival signal', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 430),
      settle: const Duration(milliseconds: 2050),
      child: GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PracticeTemperatureChart(
              points: [
                HeatTrendPoint(
                  date: DateTime(2026, 7, 2),
                  score: 42,
                  conversationName: '',
                ),
                HeatTrendPoint(
                  date: DateTime(2026, 7, 8),
                  score: 55,
                  conversationName: '',
                ),
                HeatTrendPoint(
                  date: DateTime(2026, 7, 14),
                  score: 51,
                  conversationName: '',
                ),
                HeatTrendPoint(
                  date: DateTime(2026, 7, 21),
                  score: 68,
                  conversationName: '',
                ),
              ],
            ),
          ),
        ),
      ),
      outPath: outPath('liquid_practice_growth.png'),
    );
  });

  testWidgets('engagement trend signal reveal', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 420),
      settle: const Duration(milliseconds: 720),
      child: GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: HeatTrendChart(
              trendPoints: [
                HeatTrendPoint(
                  date: DateTime(2026, 7, 2),
                  score: 44,
                  conversationName: '安安',
                ),
                HeatTrendPoint(
                  date: DateTime(2026, 7, 8),
                  score: 58,
                  conversationName: '安安',
                ),
                HeatTrendPoint(
                  date: DateTime(2026, 7, 14),
                  score: 62,
                  conversationName: '安安',
                ),
              ],
              averageScore: 54.7,
              scoreDelta: 4,
              contextLabel: '安安',
              sampleCount: 3,
            ),
          ),
        ),
      ),
      outPath: outPath('engagement_trend_motion.png'),
    );
  });
}
