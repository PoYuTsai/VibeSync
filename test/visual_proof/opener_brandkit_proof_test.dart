// Visual proof for the high-risk Opener (開場救星) screen migrated onto BrandKit
// 暗紫橘 (opening_rescue_screen.dart). Renders the REAL screen to PNG so the
// dark-mode readability + 暗紫橘統一 can be eyeballed against the shipped
// 關於我/作戰板 reference — NOT a Calm* mock (that lives in opener_proof_test).
//
// initState → _reloadDrafts() reads StorageService.settingsBox, so we open a
// real (empty) Hive 'settings' box; drafts are plain JSON strings under a key,
// so an empty box makes loadDrafts() return [] gracefully (no adapters needed).
// subscriptionProvider is seeded free (same idiom as safe_batch_proof_test).
//
// Result-state cards (_buildResults: opener cards / 推薦理由 / 先鋒備案 /
// 下一步) require _result != null, which is only set by the live generate
// network call and has no headless injection seam. Those were converted in the
// same sweep (every GlassmorphicContainer → BrandSurfaceCard; every
// glassText*/glassWhite/glassBorder → onBackground*/brandInk/white-alpha) and
// verified by source review; opener_proof_test.dart visualizes that result
// layout. Here we capture the two interactive entry tabs for real.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_typography.dart';
import 'package:vibesync/features/new_topic/domain/entities/new_topic_result.dart';
import 'package:vibesync/features/new_topic/presentation/widgets/new_topic_idea_card.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';

import 'proof_support.dart';

/// Seeds subscription state directly, skipping the async Supabase init (no-op in
/// tests). Same idiom as safe_batch_proof_test / my_report_screen_test.
class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

Widget _opener({
  OpeningRescueMode initialMode = OpeningRescueMode.opener,
}) =>
    ProviderScope(
      overrides: [
        subscriptionProvider.overrideWith(
          (ref) => _SeededSubscriptionNotifier(
            const SubscriptionState(tier: SubscriptionTierHelper.free),
          ),
        ),
      ],
      child: OpeningRescueScreen(initialMode: initialMode),
    );

const _newTopicIdea = NewTopicIdea(
  id: 'nt_1',
  direction: '接住她上次提到的旅行',
  openingLine: '妳上次說想去花東走走，最後有找到那間海邊咖啡店嗎？',
  whyItWorks: '延續她自己提過的內容，不需要突然另開一個完全無關的話題。',
  nextMove: '她回覆後先接她最有感的一段，再分享一個短短的相關經驗。',
);

Widget _newTopicResultCard() => BrandPageBackground(
      tone: BrandVisualTone.coach,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '新話題建議',
                  style: AppTypography.titleLarge.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 18,
                      color: AppColors.coachRecommendation,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI 推薦理由：她先前主動提過旅行，從這裡接回去自然又沒有壓力。',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.onBackgroundSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                NewTopicIdeaCard(
                  idea: _newTopicIdea,
                  isRecommended: true,
                  onCopyOpeningLine: _noop,
                ),
              ],
            ),
          ),
        ),
      ),
    );

void _noop() {}

void main() {
  setUpAll(() async {
    await loadProofFonts();
    Hive.init(Directory.systemTemp.createTempSync('opener_proof').path);
    if (!Hive.isBoxOpen(AppConstants.settingsBox)) {
      await Hive.openBox(AppConstants.settingsBox);
    }
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('opener screenshot tab capture (real screen, free)',
      (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 1180),
      child: _opener(),
      outPath: outPath('opener_brandkit_screenshot_tab.png'),
    );
  });

  testWidgets('opener manual tab capture (real screen, fields + chips)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1180));
    final rootKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
        home: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'AppTC'),
          child: RepaintBoundary(key: rootKey, child: _opener()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('手動輸入'));
    // Settle the BrandSegmentedButton's 180ms AnimatedContainer fully so the
    // capture shows the final state (background is a static DecoratedBox now,
    // so pumpAndSettle can't hang on a perpetual animation).
    await tester.pumpAndSettle();
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      (File(outPath('opener_brandkit_manual_tab.png'))
            ..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('new topic entry capture (real screen, free)', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 1180),
      child: _opener(initialMode: OpeningRescueMode.newTopic),
      outPath: outPath('new_topic_coach_entry.png'),
    );
  });

  testWidgets('new topic recommended result card capture', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 844),
      child: _newTopicResultCard(),
      outPath: outPath('new_topic_coach_result.png'),
    );
  });
}
