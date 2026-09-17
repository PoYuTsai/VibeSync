import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../subscription/data/providers/subscription_providers.dart';
import '../../data/night_market_story.dart';
import '../night_market_essential_gate.dart';
import '../screens/night_market_review_screen.dart';

class NightMarketEntryCard extends ConsumerStatefulWidget {
  const NightMarketEntryCard({super.key});

  @override
  ConsumerState<NightMarketEntryCard> createState() =>
      _NightMarketEntryCardState();
}

class _NightMarketEntryCardState extends ConsumerState<NightMarketEntryCard> {
  /// Guards the whole "open paywall -> sync/refresh -> enter review" round
  /// trip, released only in `finally` (same rule as the video screen's own
  /// gate) so a fast double-tap can't open two paywalls or enter review
  /// twice.
  bool _reviewGateInFlight = false;

  /// A likely-real purchase/restore was made but couldn't yet be confirmed
  /// (see [NightMarketUnlockOutcome.pendingConfirmation]). While true, the
  /// next tap retries confirmation instead of reopening the store paywall.
  bool _pendingConfirmation = false;

  /// The account [_pendingConfirmation] belongs to — a different signed-in
  /// account never attempted a purchase and must get the full flow, not a
  /// confirmation-only retry (review round 4, requirement 三).
  String? _pendingConfirmationAccountId;

  Future<bool> _pendingConfirmationStillForCurrentAccount() async {
    final currentAccount = await ref.read(nightMarketAccountIdProvider.future);
    return currentAccount == _pendingConfirmationAccountId;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _videoCard(context),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey('night-market-review-entry'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryLight,
            ),
            onPressed: _openReview,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('查看復盤'),
          ),
        ),
      ],
    );
  }

  /// The full recap (dialogue, chapter breakdowns, clip replay) is Essential
  /// content end to end, not just this entry button — gating here is the
  /// only call site left unguarded once beat-level gating covers the
  /// post-playback path (finishing S3 already requires Essential).
  Future<void> _openReview() async {
    if (_reviewGateInFlight) return;
    final gate = gateFor(
      EbookAccess.essential,
      ref.read(ebookSubscriptionAccessProvider),
    );
    switch (gate) {
      case ChatQuizGate.allowed:
        // Allowed either way means this specific attempt is over — clear
        // any stale pending flag so a LATER, genuinely fresh lock-out
        // doesn't incorrectly skip straight to a confirmation-only retry.
        _pendingConfirmation = false;
        _pendingConfirmationAccountId = null;
        _pushReview();
        break;
      case ChatQuizGate.resolving:
        showNightMarketGateNotice(context, '正在確認你的訂閱狀態，請稍後再點一次');
        break;
      case ChatQuizGate.unavailable:
        showNightMarketGateNotice(
          context,
          '暫時無法確認訂閱狀態',
          actionLabel: '重試',
          onAction: () => ref.read(subscriptionProvider.notifier).refresh(),
        );
        break;
      case ChatQuizGate.locked:
        _reviewGateInFlight = true;
        try {
          // A prior attempt ended pendingConfirmation: retry confirmation
          // only, never reopen the store paywall for a purchase that may
          // have already gone through — but only for the SAME account that
          // made the attempt; a different signed-in account never
          // attempted anything and must get the full flow.
          final usePendingConfirmation = _pendingConfirmation &&
              await _pendingConfirmationStillForCurrentAccount();
          if (!mounted) return;
          final outcome = usePendingConfirmation
              ? await resolveNightMarketPendingConfirmation(context, ref)
              : await resolveNightMarketEssentialUnlock(context, ref);
          if (!context.mounted) return;
          if (outcome == NightMarketUnlockOutcome.pendingConfirmation) {
            _pendingConfirmation = true;
            _pendingConfirmationAccountId =
                await ref.read(nightMarketAccountIdProvider.future);
          } else {
            _pendingConfirmation = false;
            _pendingConfirmationAccountId = null;
          }
          // Unlocked -> go straight into the recap, not the S1 playback.
          // Cancelled/still locked/pending -> stay on this card, no
          // restricted content shown.
          if (outcome == NightMarketUnlockOutcome.unlocked) _pushReview();
        } finally {
          _reviewGateInFlight = false;
        }
    }
  }

  void _pushReview() {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (reviewContext) => NightMarketReviewScreen(
        scenario: buildNightMarketScenario(),
        onExit: () => Navigator.of(reviewContext).pop(),
        onRestart: () {
          Navigator.of(reviewContext).pop();
          context.push('/practice-night-market');
        },
      ),
    ));
  }

  Widget _videoCard(BuildContext context) {
    return PressableScale(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('night-market-entry-card'),
          onTap: () => context.push('/practice-night-market'),
          child: SizedBox(
            height: 132,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/night_market/cover.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: AppColors.brandSurface2,
                    child: Icon(Icons.local_activity_outlined,
                        color: AppColors.ctaStart, size: 44),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Icon(Icons.local_activity_outlined,
                          color: AppColors.ctaStart, size: 32),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('簡易搭訕流程詳解',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800)),
                            SizedBox(height: 4),
                            Text('夜市實戰版：從注意到她到加聯繫方式',
                                style: TextStyle(
                                    color: Colors.white70, height: 1.35)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: AppColors.ctaStart),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
