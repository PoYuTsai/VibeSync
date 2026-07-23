import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// 單一階段門檻：經過秒數達到 [minSeconds] 起顯示 [label]。
/// 階段表須依 [minSeconds] 由小到大排列，第一段通常是 0。
class PracticeWaitStage {
  const PracticeWaitStage({required this.minSeconds, required this.label});

  final int minSeconds;
  final String label;
}

/// 通用「階段式等待文案」列：hourglass icon＋當前階段文案＋經過秒數。
/// 自包含 Timer.periodic(1s) 累秒，mount 即從 0 起算、dispose 必取消，
/// 與練習室 hint 等待字幕列同視覺與同行為（原型見 `_HintCoachPanel`）。
class PracticeWaitProgress extends StatefulWidget {
  const PracticeWaitProgress({super.key, required this.stages});

  final List<PracticeWaitStage> stages;

  @override
  State<PracticeWaitProgress> createState() => _PracticeWaitProgressState();
}

class _PracticeWaitProgressState extends State<PracticeWaitProgress> {
  int _elapsedSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _stageLabel {
    var label = widget.stages.first.label;
    for (final stage in widget.stages) {
      if (_elapsedSeconds >= stage.minSeconds) {
        label = stage.label;
      }
    }
    return label;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.hourglass_top,
          size: 14,
          color: AppColors.primaryLight,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$_stageLabel（$_elapsedSeconds 秒）',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: AppColors.onBackgroundSecondary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
