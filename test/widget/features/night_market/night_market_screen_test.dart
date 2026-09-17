import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';
import 'package:vibesync/features/night_market/presentation/screens/night_market_screen.dart';

import '../../../helpers/fake_sydney_video_platform.dart';
import '../../../helpers/night_market_paywall_harness.dart';

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<NightMarketPaywallHarness> _pumpStarted(
  WidgetTester tester, {
  EbookSubscriptionAccess access = const EbookSubscriptionAccess.essential(),
  bool forceSyncTierShouldFail = false,
  bool revenueCatRecoveryConfirmsEssential = false,
}) async {
  final harness = await pumpNightMarketPaywallHarness(
    tester,
    builder: (_, __) => const NightMarketScreen(),
    access: access,
    forceSyncTierShouldFail: forceSyncTierShouldFail,
    revenueCatRecoveryConfirmsEssential: revenueCatRecoveryConfirmsEssential,
  );
  await tester.tap(find.text('開始'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
  return harness;
}

/// Emits the platform completion event for the newest controller and pumps
/// until the screen reacts.
Future<void> _complete(WidgetTester tester, FakeSydneyVideoPlatform p) async {
  final id = p.creations.length - 1;
  p.streams[id]!.add(VideoEvent(eventType: VideoEventType.completed));
  for (var turn = 0; turn < 10; turn++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

const _mainChoice = '走到她看得到的側前方';
const _coachedChoice = '等她逛到我旁邊再說';

void main() {
  late FakeSydneyVideoPlatform platform;
  late VideoPlayerPlatform previous;

  setUp(() {
    previous = VideoPlayerPlatform.instance;
    platform = FakeSydneyVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  tearDown(() {
    platform.close();
    VideoPlayerPlatform.instance = previous;
  });

  testWidgets('start panel names the run; 開始 loads the first bundled video',
      (tester) async {
    await _pumpStarted(tester);
    expect(platform.creations, hasLength(1));
    expect(platform.creations.single.dataSource.asset,
        'assets/videos/night_market/s1_notice.mp4');
    expect(platform.playing[0], isTrue);
    // No captions, hint or choices while the video plays.
    expect(find.text('等我一下，我看一下這個。'), findsNothing);
    expect(find.textContaining('確信感'), findsNothing);
  });

  testWidgets('tap pauses/resumes; background pauses and stays paused',
      (tester) async {
    await _pumpStarted(tester);
    await tester.tap(find.byType(VideoPlayer));
    await tester.pump();
    expect(platform.playing[0], isFalse);
    await tester.tap(find.byType(VideoPlayer));
    await tester.pump();
    expect(platform.playing[0], isTrue);
    await _lifecycle(tester, AppLifecycleState.inactive);
    expect(platform.playing[0], isFalse);
    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(platform.playing[0], isFalse);
  });

  testWidgets(
      'Essential: stop point wrong choice shows coach card then continues; ending shows review',
      (tester) async {
    await _pumpStarted(tester);
    await _complete(tester, platform);
    expect(find.textContaining('確信感'), findsOneWidget);
    // Essential never sees the lock hint.
    expect(find.textContaining('Essential 方案內容'), findsNothing);
    await tester.tap(find.text(_coachedChoice));
    await tester.pump();
    expect(find.textContaining('等時機'), findsOneWidget);
    expect(platform.creations, hasLength(1));
    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(platform.creations, hasLength(2));
    expect(platform.creations[1].dataSource.asset,
        'assets/videos/night_market/s2_opening_to_craft.mp4');
    expect(platform.disposed, contains(0));

    await _complete(tester, platform);
    await tester.tap(find.textContaining('我之前也去過一次'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(platform.creations, hasLength(3));

    await _complete(tester, platform);
    expect(find.text('復盤'), findsOneWidget);
    // Approach anxiety is visible in the main debrief, outside More tips.
    expect(find.textContaining('接近焦慮'), findsOneWidget);
    expect(find.text('下次只記這個：強眼神溝通。', skipOffstage: false), findsOneWidget);
    expect(find.text('帶著確信，走過去'), findsOneWidget);
    // The full index uses the same disclosure; hidden terms stay collapsed.
    expect(find.text('所有知識點（27）', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('第一分鐘破防', skipOffstage: false), findsNothing);
    await tester.scrollUntilVisible(find.text('再練一次'), 300);
    await tester.tap(find.text('再練一次'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(platform.creations, hasLength(4));
    expect(platform.creations[3].dataSource.asset,
        'assets/videos/night_market/s1_notice.mp4');
  });

  testWidgets('captions toggle shows the timed line only when on',
      (tester) async {
    await _pumpStarted(tester);
    await tester.tap(find.byTooltip('顯示字幕'));
    await tester.pump();
    // Fake position stays at zero; the first S1 line starts at 3.50s.
    expect(find.textContaining('等我一下'), findsNothing);
  });

  testWidgets('failed video offers retry instead of a blank screen',
      (tester) async {
    platform.failInitialization = true;
    await _pumpStarted(tester);
    expect(find.text('影片暫時無法播放'), findsOneWidget);
    expect(find.text('重試'), findsOneWidget);
  });

  group('first stop point paywall (Free/Starter)', () {
    testWidgets('main-line choice opens the paywall instead of loading S2',
        (tester) async {
      await _pumpStarted(tester, access: const EbookSubscriptionAccess.free());
      await _complete(tester, platform);
      expect(find.textContaining('Essential 方案內容'), findsOneWidget);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
      expect(platform.creations, hasLength(1));
      expect(find.textContaining('等時機'), findsNothing);
    });

    testWidgets('coached choice opens the paywall directly, never the coach card',
        (tester) async {
      await _pumpStarted(tester, access: const EbookSubscriptionAccess.free());
      await _complete(tester, platform);
      await tester.tap(find.text(_coachedChoice));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
      expect(find.textContaining('等時機'), findsNothing);
      expect(platform.creations, hasLength(1));
    });

    testWidgets('cancel returns to the same choice card; tapping again reopens it',
        (tester) async {
      await _pumpStarted(tester, access: const EbookSubscriptionAccess.free());
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('paywall-cancel')));
      await tester.pumpAndSettle();
      expect(find.textContaining('確信感'), findsOneWidget);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
    });

    testWidgets('double tap opens only one paywall', (tester) async {
      await _pumpStarted(tester, access: const EbookSubscriptionAccess.free());
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
    });

    testWidgets('Starter also opens the paywall', (tester) async {
      await _pumpStarted(tester,
          access: const EbookSubscriptionAccess.premium());
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
    });

    testWidgets('resolving shows a neutral notice, never a paywall',
        (tester) async {
      await _pumpStarted(tester,
          access: const EbookSubscriptionAccess.resolving());
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pump();
      expect(find.text(paywallStubText), findsNothing);
      expect(find.text('正在確認你的訂閱狀態，請稍後再點一次'), findsOneWidget);
    });

    testWidgets('unavailable shows a retry notice, never a paywall',
        (tester) async {
      await _pumpStarted(tester,
          access: const EbookSubscriptionAccess.unavailable());
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pump();
      expect(find.text(paywallStubText), findsNothing);
      expect(find.text('暫時無法確認訂閱狀態'), findsOneWidget);
      expect(find.text('重試'), findsOneWidget);
    });
  });

  group('unlock consistency', () {
    testWidgets(
        'buying Essential restarts from S1 immediately and plays through with no second paywall',
        (tester) async {
      await _pumpStarted(tester, access: const EbookSubscriptionAccess.free());
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('paywall-buy-essential')));
      await tester.pumpAndSettle();
      // Restarted from S1 (not the start cover, not S2 directly).
      expect(platform.creations, hasLength(2));
      expect(platform.creations[1].dataSource.asset,
          'assets/videos/night_market/s1_notice.mp4');
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text(paywallStubText), findsNothing);
      expect(platform.creations, hasLength(3));
      expect(platform.creations[2].dataSource.asset,
          'assets/videos/night_market/s2_opening_to_craft.mp4');
    });

    testWidgets('buying Starter only stays locked and does not restart',
        (tester) async {
      await _pumpStarted(tester, access: const EbookSubscriptionAccess.free());
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('paywall-buy-starter')));
      await tester.pumpAndSettle();
      expect(platform.creations, hasLength(1));
      expect(find.textContaining('確信感'), findsOneWidget);
    });

    testWidgets(
        'sync failure but RevenueCat confirms the purchase: unlocks and '
        'persists, not just this one attempt', (tester) async {
      final harness = await _pumpStarted(
        tester,
        access: const EbookSubscriptionAccess.free(),
        forceSyncTierShouldFail: true,
        revenueCatRecoveryConfirmsEssential: true,
      );
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('paywall-buy-essential-sync-lag')),
      );
      await tester.pumpAndSettle();
      expect(harness.notifier.forceSyncTierCalls, 1);
      expect(harness.notifier.adoptRevenueCatTierIfHigherCalls, 1);
      expect(platform.creations, hasLength(2));
      expect(platform.creations[1].dataSource.asset,
          'assets/videos/night_market/s1_notice.mp4');
      // Recovery persisted into the real subscription state, so the very
      // next independent gate check must NOT be blocked again.
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsNothing);
      expect(platform.creations, hasLength(3));
      expect(platform.creations[2].dataSource.asset,
          'assets/videos/night_market/s2_opening_to_craft.mp4');
    });

    testWidgets(
        'sync failure and RevenueCat also cannot confirm it: stays locked, '
        'no standing bypass from the popped string alone', (tester) async {
      final harness = await _pumpStarted(
        tester,
        access: const EbookSubscriptionAccess.free(),
        forceSyncTierShouldFail: true,
      );
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('paywall-buy-essential-sync-lag')),
      );
      await tester.pumpAndSettle();
      expect(harness.notifier.forceSyncTierCalls, 1);
      expect(harness.notifier.adoptRevenueCatTierIfHigherCalls, 1);
      // No evidence anywhere confirmed Essential: must not restart or grant
      // access out of nothing.
      expect(platform.creations, hasLength(1));
      expect(find.textContaining('確信感'), findsOneWidget);
    });

    testWidgets(
        'confirmation retry after pendingConfirmation never reopens the '
        'store paywall, even once the subscription resolves '
        '(review round 3, requirement 四.4)', (tester) async {
      final harness = await _pumpStarted(
        tester,
        access: const EbookSubscriptionAccess.free(),
        forceSyncTierShouldFail: true,
      );
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('paywall-buy-essential-sync-lag')),
      );
      await tester.pumpAndSettle();
      // First attempt: sync failed and RevenueCat couldn't confirm either ->
      // pendingConfirmation (not denied), stays on this card.
      expect(platform.creations, hasLength(1));
      expect(find.text(paywallStubText), findsNothing);

      // Something independent resolves it between attempts (e.g. a
      // periodic/webhook-driven sync elsewhere) — the retry tap must find
      // this via refresh/adopt, not by reopening the store paywall.
      harness.notifier.onAdoptRevenueCatTierIfHigher =
          () => harness.setAccess(const EbookSubscriptionAccess.essential());
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsNothing);
      expect(harness.notifier.forceSyncTierCalls, 1,
          reason: 'retrying confirmation must not re-run the purchase sync');
      expect(platform.creations, hasLength(2));
      expect(platform.creations[1].dataSource.asset,
          'assets/videos/night_market/s1_notice.mp4');
    });

    testWidgets(
        'gate already independently allowed before the second tap still '
        'finishes the purchase round (restart) and clears pending, not just '
        'a normal advance (review round 4, requirement 三.1)', (tester) async {
      final harness = await _pumpStarted(
        tester,
        access: const EbookSubscriptionAccess.free(),
        forceSyncTierShouldFail: true,
      );
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('paywall-buy-essential-sync-lag')),
      );
      await tester.pumpAndSettle();
      expect(platform.creations, hasLength(1)); // pendingConfirmation

      // The subscription resolves BEFORE the user even taps again — not as
      // a side effect of the retry's own adopt callback (that's the
      // round-3 test above). The very next tap is an ordinary gate hit,
      // which must still finish the purchase round (restart), not just
      // silently continue to S2 as if nothing happened.
      harness.setAccess(const EbookSubscriptionAccess.essential());
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsNothing);
      expect(platform.creations, hasLength(2));
      expect(platform.creations[1].dataSource.asset,
          'assets/videos/night_market/s1_notice.mp4');

      // pending must have been cleared: a LATER, genuinely fresh lock-out
      // goes through the full flow again, not a confirmation-only retry.
      harness.setAccess(const EbookSubscriptionAccess.free());
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
    });

    testWidgets(
        'account switch after a pendingConfirmation clears it: the new '
        'account gets the full flow, not a confirmation-only retry '
        '(review round 4, requirement 三.2)', (tester) async {
      final harness = await _pumpStarted(
        tester,
        access: const EbookSubscriptionAccess.free(),
        forceSyncTierShouldFail: true,
      );
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('paywall-buy-essential-sync-lag')),
      );
      await tester.pumpAndSettle();
      expect(platform.creations, hasLength(1)); // pendingConfirmation

      harness.switchAccount('a-different-user');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      // A brand new account never attempted a purchase: must see the store
      // paywall again, not a silent confirmation-only retry.
      expect(find.text(paywallStubText), findsOneWidget);
    });

    testWidgets(
        'account switch while the paywall is open does not apply the stale result',
        (tester) async {
      final harness =
          await _pumpStarted(tester, access: const EbookSubscriptionAccess.free());
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      harness.switchAccount('a-different-user');
      // Let the real StreamProvider actually deliver the new account id
      // before continuing, same as a genuine auth-state event would.
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('paywall-buy-essential')));
      await tester.pumpAndSettle();
      // Account changed mid-flight: the unlock must not be applied.
      expect(platform.creations, hasLength(1));
      expect(find.textContaining('確信感'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tearing down the screen while the paywall round trip is pending does not throw',
        (tester) async {
      await _pumpStarted(tester, access: const EbookSubscriptionAccess.free());
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('re-checks the gate at the actual moment of entering content', () {
    testWidgets(
        'coach card shown while Essential; losing access before tapping 知道了 '
        'reopens the paywall instead of loading S2', (tester) async {
      final harness = await _pumpStarted(tester);
      await _complete(tester, platform);
      await tester.tap(find.text(_coachedChoice));
      await tester.pump();
      expect(find.textContaining('等時機'), findsOneWidget);
      // Access lost while the card was on screen (expiry/revocation).
      harness.setAccess(const EbookSubscriptionAccess.free());
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
      expect(platform.creations, hasLength(1));
    });

    testWidgets(
        'losing access right before S3 finishes does not build the full recap',
        (tester) async {
      final harness = await _pumpStarted(tester);
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await _complete(tester, platform);
      await tester.tap(find.textContaining('我之前也去過一次'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(platform.creations, hasLength(3));
      // Access lost while S3 is playing, right before it finishes.
      harness.setAccess(const EbookSubscriptionAccess.free());
      await _complete(tester, platform);
      await tester.pumpAndSettle();
      expect(find.text('復盤'), findsNothing);
      expect(find.text(paywallStubText), findsOneWidget);
    });
  });

  group(
      'S3 ending: resolving/unavailable/cancel stay recoverable (review '
      'round 3, requirement 三/四.5)', () {
    Future<void> reachS3End(WidgetTester tester) async {
      await _complete(tester, platform);
      await tester.tap(find.text(_mainChoice));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await _complete(tester, platform);
      await tester.tap(find.textContaining('我之前也去過一次'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(platform.creations, hasLength(3));
    }

    // The resolving/unavailable notices are shown via a real SnackBar, which
    // sits at the bottom of the screen — the same place as the persistent
    // retry card underneath it — and stays on screen (absorbing taps) for
    // its full display duration; `pumpAndSettle` does not wait that out
    // (it stops as soon as no frame is scheduled, i.e. right after the
    // entrance animation). Clearing it directly is deterministic, unlike
    // guessing how long to elapse fake time.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets(
        'resolving right as S3 finishes shows a neutral pending card, not a '
        'paywall, and retry succeeds once the subscription resolves',
        (tester) async {
      final harness = await _pumpStarted(tester);
      await reachS3End(tester);
      harness.setAccess(const EbookSubscriptionAccess.resolving());
      await _complete(tester, platform);
      await settle(tester);
      expect(find.text('復盤'), findsNothing);
      expect(find.text(paywallStubText), findsNothing);
      expect(find.widgetWithText(FilledButton, '重試'), findsOneWidget);
      // Neutral wording, not "this is Essential content" — the user may
      // well already be Essential; the subscription state just hasn't
      // confirmed yet (review round 4, requirement 四).
      expect(find.textContaining('正在確認訂閱狀態'), findsOneWidget);
      expect(find.textContaining('Essential 方案內容'), findsNothing);

      // Still resolving on this attempt too: stays on the same card, no
      // paywall, no crash.
      await tester.tap(find.widgetWithText(FilledButton, '重試'));
      await settle(tester);
      expect(find.text('復盤'), findsNothing);
      expect(find.text(paywallStubText), findsNothing);

      // Now resolves: retry succeeds without ever opening the store paywall.
      harness.setAccess(const EbookSubscriptionAccess.essential());
      await tester.tap(find.widgetWithText(FilledButton, '重試'));
      await settle(tester);
      expect(find.text('復盤'), findsOneWidget);
      expect(find.text(paywallStubText), findsNothing);
    });

    testWidgets('unavailable right as S3 finishes offers retry, not a dead end',
        (tester) async {
      final harness = await _pumpStarted(tester);
      await reachS3End(tester);
      harness.setAccess(const EbookSubscriptionAccess.unavailable());
      await _complete(tester, platform);
      await settle(tester);
      expect(find.text('復盤'), findsNothing);
      expect(find.widgetWithText(FilledButton, '重試'), findsOneWidget);
      expect(find.textContaining('暫時無法確認訂閱狀態'), findsOneWidget);
      expect(find.textContaining('Essential 方案內容'), findsNothing);

      harness.setAccess(const EbookSubscriptionAccess.essential());
      await tester.tap(find.widgetWithText(FilledButton, '重試'));
      await settle(tester);
      expect(find.text('復盤'), findsOneWidget);
    });

    testWidgets(
        'cancelling the auto-opened paywall at S3 end leaves a retry card '
        'that reopens it, not a dead end', (tester) async {
      final harness = await _pumpStarted(tester);
      await reachS3End(tester);
      // Access lost right before S3 finishes: the ending gate opens the
      // store paywall itself, same as the existing "losing access right
      // before S3 finishes" case — but this time the purchase is cancelled
      // instead of just leaving the paywall up mid-test.
      harness.setAccess(const EbookSubscriptionAccess.free());
      await _complete(tester, platform);
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('paywall-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('復盤'), findsNothing);
      expect(find.widgetWithText(FilledButton, '重試'), findsOneWidget);
      // Genuinely locked (not resolving/unavailable): the Essential-specific
      // wording is correct here, unlike the two cases above.
      expect(find.textContaining('Essential 方案內容'), findsOneWidget);

      // Retry while still genuinely locked reopens the paywall, not a
      // silent no-op.
      await tester.tap(find.widgetWithText(FilledButton, '重試'));
      await tester.pumpAndSettle();
      expect(find.text(paywallStubText), findsOneWidget);
      // Buying now: same as every other mid-story unlock, this restarts
      // from S1 rather than jumping straight into the recap (established by
      // the "unlock consistency" group above) — this call site is no
      // different just because the trigger was S3 finishing.
      await tester.tap(find.byKey(const ValueKey('paywall-buy-essential')));
      await tester.pumpAndSettle();
      expect(platform.creations, hasLength(4));
      expect(platform.creations[3].dataSource.asset,
          'assets/videos/night_market/s1_notice.mp4');
    });
  });

  group('full round-trip reentrancy', () {
    testWidgets(
        'provider flipping allowed mid-sync does not let a second tap race '
        'the pending restart', (tester) async {
      final harness = await _pumpStarted(
        tester,
        access: const EbookSubscriptionAccess.free(),
      );
      await _complete(tester, platform);
      final gate = Completer<void>();
      harness.notifier.forceSyncTierGate = gate;
      await tester.tap(find.text(_mainChoice));
      await tester.pumpAndSettle();
      // Pops the paywall as essential; the stub also flips the access
      // provider to essential synchronously, before forceSyncTier (now
      // stuck on `gate`) ever returns — the exact race under test.
      await tester.tap(find.byKey(const ValueKey('paywall-buy-essential')));
      // The pop transition itself needs settling (same as the push did),
      // independent of `forceSyncTier` being genuinely stuck on `gate`:
      // pumpAndSettle only cares about the frame scheduler, not arbitrary
      // suspended futures, so it converges once the paywall page is fully
      // gone and NightMarketScreen is interactive again.
      await tester.pumpAndSettle();
      expect(harness.notifier.forceSyncTierCalls, 1);
      // Tap again while the round trip is still stuck: must be dropped
      // outright, not race the pending restart by reading the now-allowed
      // gate directly (which would prematurely load S2 or show a coach
      // card).
      await tester.tap(find.text(_mainChoice));
      await tester.pump();
      expect(platform.creations, hasLength(1));
      expect(find.text(paywallStubText), findsNothing);
      expect(find.textContaining('等時機'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      // The ORIGINAL round trip finishes and restarts exactly once.
      expect(platform.creations, hasLength(2));
      expect(platform.creations[1].dataSource.asset,
          'assets/videos/night_market/s1_notice.mp4');
    });
  });
}
