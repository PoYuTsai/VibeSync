// lib/features/analysis/presentation/widgets/two_stage_loading_widgets.dart
//
// UI primitives for the full-streaming analyze flow.
//
// - [QuickRotatingLoader]    Spinner + rotating Chinese narrative copy. The
//   historical class name remains for compatibility; it now represents the
//   full-streaming prelude before content events arrive.
// - [FullAnalysisPlaceholder] Legacy skeleton retained for rollback tests.
// - [FullAnalysisRetryCard]   Card shown after full failure. Disables the
//   retry CTA when [retriesRemaining] reaches 0 and switches copy to
//   「無法再重試，請重新分析」.

import 'dart:async';

import 'package:flutter/material.dart';

const List<String> kQuickLoadingPhrases = <String>[
  '正在讀取對話脈絡...',
  '整理目前互動節奏...',
  '判斷對方訊號強弱...',
  '整理下一步建議...',
  '準備完整分析內容...',
];

const Duration kQuickRotationInterval = Duration(milliseconds: 1000);

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
/// [kQuickLoadingPhrases].
class QuickRotatingLoader extends StatefulWidget {
  final List<String> phrases;
  final Duration interval;
  final String? label;
  final String? detail;

  const QuickRotatingLoader({
    super.key,
    this.phrases = kQuickLoadingPhrases,
    this.interval = kQuickRotationInterval,
    this.label,
    this.detail,
  });

  @override
  State<QuickRotatingLoader> createState() => _QuickRotatingLoaderState();
}

class _QuickRotatingLoaderState extends State<QuickRotatingLoader> {
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
    final theme = Theme.of(context);
    final headline =
        _canRetry ? (errorMessage ?? '完整分析暫時失敗。') : kRetryExhaustedMessage;
    final buttonLabel = _canRetry ? '重試完整分析（剩 $retriesRemaining 次）' : '無法再重試';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              headline,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _canRetry ? onRetry : null,
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
