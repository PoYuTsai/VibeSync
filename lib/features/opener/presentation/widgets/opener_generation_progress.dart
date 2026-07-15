// lib/features/opener/presentation/widgets/opener_generation_progress.dart
//
// Staged local progress copy for opener generation (F3-2 低配版).
//
// Unlike the analyze prelude's looping [StreamingAnalysisLoader], this widget
// advances through its phrases once and holds on the last one — opener has no
// streaming events to hand off to, so looping back to "reading" copy after
// "polishing" copy would read as a stall. The periodic timer is cancelled at
// the last stage (and on dispose), so pumpAndSettle converges.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

const List<String> kOpenerScreenshotProgressPhrases = <String>[
  '正在讀取截圖上的線索…',
  '從對方的資訊找切入點…',
  '構思開場方向…',
  '打磨每一句開場白…',
  '還在整理開場方向，請保持連線…',
];

const List<String> kOpenerManualProgressPhrases = <String>[
  '正在整理你提供的線索…',
  '從對方的資訊找切入點…',
  '構思開場方向…',
  '打磨每一句開場白…',
  '還在整理開場方向，請保持連線…',
];

const Duration kOpenerProgressStageInterval = Duration(seconds: 3);

class OpenerGenerationProgress extends StatefulWidget {
  final List<String> phrases;
  final Duration interval;

  const OpenerGenerationProgress({
    super.key,
    required this.phrases,
    this.interval = kOpenerProgressStageInterval,
  });

  /// Screenshot runs go through OCR first, so their copy leads with reading
  /// the screenshot; manual runs start from the user-typed clues.
  static List<String> phrasesFor({required bool hasImages}) {
    return hasImages
        ? kOpenerScreenshotProgressPhrases
        : kOpenerManualProgressPhrases;
  }

  @override
  State<OpenerGenerationProgress> createState() =>
      _OpenerGenerationProgressState();
}

class _OpenerGenerationProgressState extends State<OpenerGenerationProgress> {
  // 生成生命週期快照：mount 後 parent 換 phrases（用戶切 tab/改輸入）不得
  // 讓進度文案漂到另一條路徑——後端處理的仍是生成開始時的輸入。
  late final List<String> _phrases = widget.phrases;
  int _stage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_phrases.length > 1) {
      _timer = Timer.periodic(widget.interval, (_) {
        if (!mounted) return;
        setState(() {
          _stage++;
          if (_stage >= _phrases.length - 1) {
            _stage = _phrases.length - 1;
            _timer?.cancel();
            _timer = null;
          }
        });
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
    if (_phrases.isEmpty) return const SizedBox.shrink();
    final stage = _stage.clamp(0, _phrases.length - 1);
    return Column(
      children: [
        const SizedBox(height: 8),
        const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.ctaStart),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _phrases[stage],
            key: ValueKey<int>(stage),
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
