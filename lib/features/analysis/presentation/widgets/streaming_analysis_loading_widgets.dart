// lib/features/analysis/presentation/widgets/streaming_analysis_loading_widgets.dart
//
// UI primitives for the full-streaming analyze flow.
//
// - [StreamingAnalysisLoader]    Spinner + rotating Chinese narrative copy. The
//   historical class name remains for compatibility; it now represents the
//   full-streaming prelude before content events arrive.
// - [FullAnalysisPlaceholder] Legacy skeleton retained for rollback tests.
// - [FullAnalysisRetryCard]   Card shown after full failure. Disables the
//   retry CTA when [retriesRemaining] reaches 0 and switches copy to
//   「無法再重試，請重新分析」.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

const List<String> kStreamingAnalysisLoadingPhrases = <String>[
  '正在讀取對話脈絡...',
  '整理目前互動節奏...',
  '判斷對方訊號強弱...',
  '整理下一步建議...',
  '準備完整分析內容...',
];

const Duration kStreamingAnalysisRotationInterval =
    Duration(milliseconds: 1000);

const String kFullPlaceholderClosing = '正在補上完整報告...';
const List<String> kFullPlaceholderSectionLabels = <String>[
  '五大回覆風格整理中...',
  '互動雷達整理中...',
  '深層策略整理中...',
];
const String kRetryExhaustedMessage = '無法再重試，請重新分析。';

/// Rotating loader for the full-streaming prelude.
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
          Text(
            phrase,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
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

/// Static placeholder shown while full analysis is in flight.
///
/// [estimatedFullSeconds] is the server's ETA. When null, falls back to a
/// hard-coded 15-20s range so the copy never reads "預估 null 秒".
class FullAnalysisPlaceholder extends StatelessWidget {
  final int? estimatedFullSeconds;
  final List<String> sectionLabels;
  final String closingLabel;

  const FullAnalysisPlaceholder({
    super.key,
    this.estimatedFullSeconds,
    this.sectionLabels = kFullPlaceholderSectionLabels,
    this.closingLabel = kFullPlaceholderClosing,
  });

  static String formatEtaRange(int? seconds) {
    if (seconds == null || seconds <= 0) return '15-20';
    final low = (seconds - 2).clamp(1, 999);
    final high = (seconds + 3).clamp(low + 1, 999);
    return '$low-$high';
  }

  @override
  Widget build(BuildContext context) {
    final headerCopy = '完整分析整理中，預估 ${formatEtaRange(estimatedFullSeconds)} 秒';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  headerCopy,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final label in sectionLabels) _SkeletonBlock(label: label),
          if (closingLabel.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              closingLabel,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final String label;

  const _SkeletonBlock({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

/// Retry CTA card for failed full analysis.
///
/// When [retriesRemaining] > 0, shows the user-facing error plus a primary
/// retry button labelled "重試完整分析（剩 N 次）". When 0, swaps the body
/// for [kRetryExhaustedMessage] and disables the button to force "重新分析".
class FullAnalysisRetryCard extends StatelessWidget {
  final String? errorMessage;
  final int retriesRemaining;
  final VoidCallback? onRetry;

  const FullAnalysisRetryCard({
    super.key,
    required this.retriesRemaining,
    this.errorMessage,
    this.onRetry,
  });

  bool get _canRetry => retriesRemaining > 0;

  @override
  Widget build(BuildContext context) {
    final headline =
        _canRetry ? (errorMessage ?? '完整分析暫時失敗。') : kRetryExhaustedMessage;
    final buttonLabel = _canRetry ? '重試完整分析（剩 $retriesRemaining 次）' : '無法再重試';
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
            color: AppColors.primaryDark.withValues(alpha: 0.28),
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
                  borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _canRetry ? onRetry : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.16),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.46),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
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
