// UI primitives for the streaming AnalyzeChat flow.
//
// - [StreamingAnalysisLoader] shows progress until structured events arrive.
// - [StreamingAnalysisRetryCard] handles recoverable stream failures.
// - [QuotaExceededUpgradeCard] keeps quota exhaustion out of retry semantics.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/services/app_haptics.dart';
import '../../../subscription/presentation/quota_copy.dart';
import '../helpers/analysis_quota_hints.dart';

const List<String> kStreamingAnalysisLoadingPhrases = <String>[
  '正在讀取對話脈絡…',
  '整理目前互動節奏…',
  '判斷對方訊號強弱…',
  '整理下一步建議…',
  '準備完整分析內容…',
];

const Duration kStreamingAnalysisRotationInterval =
    Duration(milliseconds: 1000);

const String kRetryExhaustedMessage = '無法再重試，請重新分析。';

/// Rotating loader for the streaming prelude.
///
/// Cycles through [phrases] every [interval] to reduce perceived dead time.
/// Caller may inject custom phrases for tests; production uses
/// [kStreamingAnalysisLoadingPhrases].
class StreamingAnalysisLoader extends StatefulWidget {
  final List<String> phrases;
  final Duration interval;
  final String? label;
  final String? detail;

  const StreamingAnalysisLoader({
    super.key,
    this.phrases = kStreamingAnalysisLoadingPhrases,
    this.interval = kStreamingAnalysisRotationInterval,
    this.label,
    this.detail,
  });

  @override
  State<StreamingAnalysisLoader> createState() =>
      _StreamingAnalysisLoaderState();
}

class _StreamingAnalysisLoaderState extends State<StreamingAnalysisLoader> {
  int _tick = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.phrases.length > 1) {
      _timer = Timer.periodic(widget.interval, (_) {
        if (!mounted) return;
        setState(() => _tick++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.label == null && widget.phrases.isEmpty) {
      return const SizedBox.shrink();
    }
    final phrase =
        widget.label ?? widget.phrases[_tick % widget.phrases.length];
    final detail = widget.detail?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          // 金句輪換走 200ms 交叉淡變，不硬換字；字串當 key，同句不重播。
          AnimatedSwitcher(
            duration: AppMotion.enter,
            switchInCurve: AppMotion.easeOut,
            switchOutCurve: AppMotion.easeOut,
            child: Text(
              phrase,
              key: ValueKey(phrase),
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// 額度不足升級卡（smoke P1 fix 2026-06-11）。
///
/// Quota 429 中止分析時取代 [StreamingAnalysisRetryCard]：解釋剩餘/需要則數並給
/// 「查看方案」CTA（caller 接 paywall）。絕不顯示「無法再重試」——額度不足
/// 不是技術失敗，重試只會再撞 429。
class QuotaExceededUpgradeCard extends StatelessWidget {
  final bool isMonthly;
  final int? remaining;
  final int? quotaNeeded;
  final VoidCallback? onViewPlans;

  /// 目前方案（SubscriptionTierHelper 的代碼），決定怎麼說下一步（Eric 2026-10-18）：
  /// Essential 已經是最高方案，只說什麼時候恢復；Starter 只會被叫去升級 Essential。
  /// 必填：漏帶會讓 Essential 又看到升級。
  final String? tier;

  /// 免費用戶多寫一行 Starter 的量（每天幾則、大約幾次完整分析；Eric 2026-10-18），
  /// 讓「升級」換算成看得懂的次數。已經是付費方案就不寫。
  final bool showStarterCapacity;

  const QuotaExceededUpgradeCard({
    super.key,
    required this.isMonthly,
    required this.tier,
    this.remaining,
    this.quotaNeeded,
    this.onViewPlans,
    this.showStarterCapacity = false,
  });

  /// 先講什麼時候恢復，能升級的方案再補升級（Onboarding 第 3 步：本月那句以前只叫人
  /// 升級，好像付錢是唯一的路）。
  String get _headline {
    final hasNumbers = remaining != null && quotaNeeded != null;
    if (isMonthly) {
      final lead =
          hasNumbers ? '本月額度剩 $remaining 則，這次分析需要 $quotaNeeded 則。' : '本月額度不足，';
      final next = quotaNextStepLine(
        tier: tier,
        isMonthly: true,
        upgrade: '也可以升級至 ${quotaUpgradeTargets(tier)}',
      );
      return '$lead$next。';
    }
    final lead =
        hasNumbers ? '今日額度剩 $remaining 則，這次分析需要 $quotaNeeded 則。' : '今日額度不足，';
    return '$lead${quotaNextStepLine(tier: tier, isMonthly: false)}。';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.backgroundGradientMid,
            Color(0xFF351A52),
            Color(0xFF4A245C),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primaryLight.withValues(alpha: 0.42),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.36),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.ctaStart.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.ctaStart.withValues(alpha: 0.34),
                  ),
                ),
                child: const Icon(
                  Icons.workspace_premium_outlined,
                  size: 18,
                  color: AppColors.ctaStart,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _headline,
                  style: AppTypography.bodyLarge.copyWith(
                    color: Colors.white,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (showStarterCapacity) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Text(
                starterCapacityLine(),
                key: const ValueKey('quota-exceeded-starter-capacity'),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: AppHaptics.onPress(onViewPlans),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ctaStart,
              foregroundColor: AppColors.onCta,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: Text(
              '查看方案',
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Retry CTA card for an interrupted analysis stream.
///
/// When [retriesRemaining] > 0, shows the user-facing error plus a primary
/// retry button labelled "重試完整分析（剩 N 次）" that resumes the same run.
/// When 0, the same run cannot continue: shows [errorMessage] (falling back to
/// [kRetryExhaustedMessage]) and a "重新分析" button wired to [onReanalyze],
/// which starts a new analysis through the normal start flow. The button is
/// disabled while [onReanalyze] is null (e.g. screenshot recognition running).
class StreamingAnalysisRetryCard extends StatelessWidget {
  final String? errorMessage;
  final int retriesRemaining;
  final VoidCallback? onRetry;
  final VoidCallback? onReanalyze;

  const StreamingAnalysisRetryCard({
    super.key,
    required this.retriesRemaining,
    this.errorMessage,
    this.onRetry,
    this.onReanalyze,
  });

  bool get _canRetry => retriesRemaining > 0;

  @override
  Widget build(BuildContext context) {
    final exhaustedMessage = errorMessage?.trim() ?? '';
    final headline = _canRetry
        ? (errorMessage ?? '完整分析暫時失敗。')
        : (exhaustedMessage.isEmpty
            ? kRetryExhaustedMessage
            : exhaustedMessage);
    final buttonLabel = _canRetry ? '重試完整分析（剩 $retriesRemaining 次）' : '重新分析';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.backgroundGradientMid,
            Color(0xFF351A52),
            Color(0xFF4A245C),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primaryLight.withValues(alpha: 0.42),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.36),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.bokehCoral.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.bokehCoral.withValues(alpha: 0.34),
                  ),
                ),
                child: const Icon(
                  Icons.refresh_outlined,
                  size: 18,
                  color: AppColors.bokehCoral,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  headline,
                  style: AppTypography.bodyLarge.copyWith(
                    color: Colors.white,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: AppHaptics.onPress(_canRetry ? onRetry : onReanalyze),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ctaStart,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.16),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.46),
              foregroundColor: AppColors.onCta,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: Text(
              buttonLabel,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
