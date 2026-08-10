import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// 「← 左右滑動」提示的長駐動態提醒（2026-08-11 Eric 拍板：播一次太不
/// 明顯，改常駐左右晃動，節奏套 OCR 滑動教學）。每輪：右去右回、頓，
/// 左去左回、長頓（兼當輪間休息），循環不止。
///
/// reduced motion 或 TickerMode 關閉時停在原位（同 AnalysisScrollHint
/// 的既有模式）。repeat 帶 count 上限（34 輪 ≈ 88 秒，體感即長駐）：
/// 無限 repeat 會讓所有 pumpAndSettle 到本頁的測試 timeout 炸掉。
/// 提示膠囊：與 OCR 滑動教學 badge 同一視覺語言（白底膠囊＋品牌橘
/// icon/字），深色頁上對比最強；原本的灰字在品牌漸層底上幾乎隱形
/// （2026-08-11 Eric 回報）。
class SwipeHintChip extends StatelessWidget {
  const SwipeHintChip({super.key, this.label = '左右滑動'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.ctaStart.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_horiz_rounded,
              size: 17,
              color: AppColors.ctaStart,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              // 15px 檔：原灰字 caption 12px 太小是 Eric 真機回報主因之一。
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.ctaStart,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SwipeHintNudge extends StatefulWidget {
  const SwipeHintNudge({super.key, required this.child});

  final Widget child;

  @override
  State<SwipeHintNudge> createState() => _SwipeHintNudgeState();
}

class _SwipeHintNudgeState extends State<SwipeHintNudge>
    with SingleTickerProviderStateMixin {
  /// 提示字是 caption 級，位移比 OCR 教學泡泡（28px）收斂到 12px。
  static const double _shift = 12;

  late final AnimationController _controller;
  late final Animation<double> _offsetX;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _offsetX = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: _shift)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 16,
      ),
      TweenSequenceItem(tween: ConstantTween(_shift), weight: 6),
      TweenSequenceItem(
        tween: Tween(begin: _shift, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 16,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 6),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -_shift)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 16,
      ),
      TweenSequenceItem(tween: ConstantTween(-_shift), weight: 6),
      TweenSequenceItem(
        tween: Tween(begin: -_shift, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 16,
      ),
      // 長頓＝輪間休息，避免不停擺動變成噪音。
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 30),
    ]).animate(_controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimationState();
  }

  void _syncAnimationState() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = TickerMode.valuesOf(context).enabled && !reduceMotion;
    if (!enabled) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.repeat(count: 34);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offsetX,
      builder: (context, child) => Transform.translate(
        offset: Offset(_offsetX.value, 0),
        child: child,
      ),
      child: widget.child,
    );
  }
}
