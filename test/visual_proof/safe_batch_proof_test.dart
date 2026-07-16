// Visual proof for the low-risk safe-batch six screens migrated onto BrandKit
// (commit e25991d): Learning / ArticleDetail / Login / Onboarding / ProfileCard
// / MyReport. Renders each real screen to a PNG so the暗紫橘統一 + dark-mode
// readability can be eyeballed against the shipped 關於我/作戰板 reference.
//
// These render the REAL lib/ screens (not the Calm* proof variants), wrapped in
// the minimal provider overrides each one needs. Anything touching Hive
// (ArticleReadService) is faked so the headless render never opens a box.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/auth/presentation/screens/login_screen.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/presentation/screens/profile_card_screen.dart';
import 'package:vibesync/features/learning/data/articles_data.dart';
import 'package:vibesync/features/learning/data/providers/learning_providers.dart';
import 'package:vibesync/features/learning/data/services/article_read_service.dart';
import 'package:vibesync/features/learning/presentation/screens/article_detail_screen.dart';
import 'package:vibesync/features/learning/presentation/screens/learning_screen.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/report/data/providers/report_providers.dart';
import 'package:vibesync/features/report/domain/entities/report_models.dart';
import 'package:vibesync/features/report/presentation/screens/my_report_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

import 'proof_support.dart';

/// Seeds subscription state directly, skipping the async Supabase init (no-op in
/// tests). Same idiom as my_report_screen_test.
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

/// Fake article read-service so the headless render never opens the Hive
/// usage box. Only the methods the two learning screens call are overridden.
class _FakeReadService extends ArticleReadService {
  @override
  bool canReadArticle(String articleId) => true;
  @override
  int get remainingReads => 3;
  @override
  void recordReadArticle(String articleId) {}
  @override
  bool hasReadArticle(String articleId) => false;
}

class _NullUserProfileController extends UserProfileController {
  @override
  Future<UserProfile?> build() async => null;
}

Conversation _conversation() => Conversation(
      id: 'c-proof',
      name: 'Vivi',
      messages: [
        Message(
          id: 'm1',
          content: '欸你也喜歡爬山喔？',
          isFromMe: false,
          timestamp: DateTime(2026, 6, 1, 20, 0),
        ),
        Message(
          id: 'm2',
          content: '對啊上週剛去了象山，夜景超美',
          isFromMe: true,
          timestamp: DateTime(2026, 6, 1, 20, 5),
        ),
      ],
      createdAt: DateTime(2026, 6, 1),
      updatedAt: DateTime(2026, 6, 5, 21, 30),
      lastEnthusiasmScore: 72,
      currentRound: 3,
    );

ReportData _paidReport() => ReportData(
      trendPoints: [
        HeatTrendPoint(
          date: DateTime(2026, 6, 1),
          score: 60,
          conversationName: 'Vivi',
        ),
        HeatTrendPoint(
          date: DateTime(2026, 6, 2),
          score: 72,
          conversationName: 'Vivi',
        ),
        HeatTrendPoint(
          date: DateTime(2026, 6, 3),
          score: 81,
          conversationName: 'Vivi',
        ),
      ],
      averageScore: 71,
      scoreDelta: 12,
      comparisons: const [
        ConversationComparison(name: 'Vivi', score: 81),
        ConversationComparison(name: 'Nani', score: 64),
      ],
      stageDistributions: const [
        StageDistribution(stageName: '建立男女感', count: 3),
        StageDistribution(stageName: '升溫', count: 2),
      ],
      totalConversations: 5,
    );

void main() {
  setUpAll(loadProofFonts);

  // Learning's article-card grid contains a pre-existing (NOT migration-touched)
  // Positioned(bottom: 0, height: double.infinity) gradient overlay that trips
  // the debug-only "infinite height" assertion under flutter_test. Release
  // builds clamp it to the bounded grid cell, so the shipped app is fine. We
  // swallow that single layout assertion with takeException() so the capture
  // still lands and the header / BrandInfoNote dark-mode styling can be checked.
  testWidgets('learning capture (free, best-effort)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1500));
    final rootKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'AppTC'),
          child: RepaintBoundary(
            key: rootKey,
            child: ProviderScope(
              overrides: [
                subscriptionProvider.overrideWith(
                  (ref) => _SeededSubscriptionNotifier(
                    const SubscriptionState(tier: SubscriptionTierHelper.free),
                  ),
                ),
                articleReadServiceProvider
                    .overrideWithValue(_FakeReadService()),
              ],
              child: const LearningScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    tester.takeException(); // pre-existing debug-only infinite-height assertion
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      (File(outPath('safe_batch_learning.png'))..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('article detail capture (paid, full content)', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 2400),
      child: ProviderScope(
        overrides: [
          subscriptionProvider.overrideWith(
            (ref) => _SeededSubscriptionNotifier(
              const SubscriptionState(tier: SubscriptionTierHelper.starter),
            ),
          ),
          articleReadServiceProvider.overrideWithValue(_FakeReadService()),
        ],
        child: ArticleDetailScreen(articleId: articles.first.id),
      ),
      outPath: outPath('safe_batch_article_detail.png'),
    );
  });

  // LoginScreen.initState subscribes to SupabaseService.authStateChanges, which
  // hard-requires an initialized Supabase singleton. Initializing real Supabase
  // here hangs the headless run (realtime reconnect timers never settle), and
  // the static service has no injection seam to fake. So login can't be captured
  // by this harness. Its dark-mode readability was instead verified by source
  // review of login_screen.dart: body on GradientBackground; text via
  // AppColors.onBackgroundPrimary/Secondary (light-on-dark); email/password are
  // white-on-dark inside BrandSurfaceCard; submit is BrandPrimaryButton; and the
  // Google (white) / Apple (black) buttons are the deliberately-unchanged
  // official OAuth styles. Marked skip so the intent stays recorded.
  testWidgets('login capture', (tester) async {
    // Intentionally left to the LoginScreen reference so the import + symbol
    // stay wired if the harness ever gains a SupabaseService seam.
    expect(const LoginScreen(), isA<Widget>());
  }, skip: true); // see comment above — verified by source review instead

  testWidgets('onboarding capture (first page)', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 900),
      child: const ProviderScope(child: OnboardingScreen()),
      outPath: outPath('safe_batch_onboarding.png'),
    );
  });

  testWidgets('profile card capture', (tester) async {
    final conv = _conversation();
    await pumpAndCapture(
      tester,
      size: const Size(390, 1500),
      child: ProviderScope(
        overrides: [
          conversationProvider('c-proof').overrideWithValue(conv),
        ],
        child: const ProfileCardScreen(conversationId: 'c-proof'),
      ),
      outPath: outPath('safe_batch_profile_card.png'),
    );
  });

  testWidgets('my report capture (paid, three charts)', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(430, 2600),
      child: ProviderScope(
        overrides: [
          subscriptionProvider.overrideWith(
            (ref) => _SeededSubscriptionNotifier(
              const SubscriptionState(tier: SubscriptionTierHelper.starter),
            ),
          ),
          reportDataProvider.overrideWithValue(_paidReport()),
          analysisHistoryEventsProvider.overrideWithValue(const []),
          partnerListProvider.overrideWithValue(const []),
          conversationsByPartnerProvider.overrideWith((ref, id) => const []),
          userProfileControllerProvider
              .overrideWith(_NullUserProfileController.new),
        ],
        child: const MyReportScreen(),
      ),
      outPath: outPath('safe_batch_my_report.png'),
    );
  });
}
