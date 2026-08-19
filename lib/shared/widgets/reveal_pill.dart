import 'package:flutter/material.dart';

import '../../core/services/app_haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_typography.dart';

/// 「藏起來的內容」統一揭示元件（2026-08-19 Eric 拍板抽共用）：
/// 收合＝懸浮深墨膠囊，逐項對標 AnalysisScrollHint「跟到最新」——
/// brandInk 底、白粗字、ctaStart 雙下箭頭與 Stadium 橘框、中性黑陰影；
/// 整顆沿動作軸垂直 nudge（「動、頓、長頓」拍子，2026-08-11 拍板常駐
/// 循環）。展開＝原地換安靜淡紫容器＋「收起」文字列（沿用開場救星
/// 「收起備選」語彙）。深淺底都成立：深底靠橘框＋陰影浮起（同對象
/// 作戰板深色磚），淺底靠 ink 對比。
///
/// reduced motion 停在原位；repeat 帶 count 上限避免 pumpAndSettle
/// timeout（同 SwipeHintNudge）。
/// 使用點：教練卡「看完整教練分析」、開場救星「下一步怎麼接？」。
class RevealPill extends StatefulWidget {
  const RevealPill({
    super.key,
    required this.label,
    this.collapseLabel = '收起',
    required this.children,
  });

  /// 收合膠囊上的文字。
  final String label;

  /// 展開後底部收合列的文字。
  final String collapseLabel;

  /// 展開後的內容。
  final List<Widget> children;

  @override
  State<RevealPill> createState() => _RevealPillState();
}

class _RevealPillState extends State<RevealPill>
    with SingleTickerProviderStateMixin {
  /// 膠囊垂直位移量：夠真機有感、又不至於吵。
  static const double _dip = 5;

  late final AnimationController _controller;
  late final Animation<double> _offsetY;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _offsetY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: _dip)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _dip, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 12,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 6),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: _dip)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _dip, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 12,
      ),
      // 長頓＝輪間休息，避免不停點頭變成噪音。
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 46),
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
    final enabled =
        TickerMode.valuesOf(context).enabled && !reduceMotion && !_expanded;
    if (!enabled) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(count: 34);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _syncAnimationState();
  }

  @override
  Widget build(BuildContext context) {
    final pill = FilledButton.icon(
      onPressed: AppHaptics.onPress(_toggle),
      icon: const Icon(
        Icons.keyboard_double_arrow_down_rounded,
        size: 21,
        color: AppColors.ctaStart,
      ),
      label: Text(
        widget.label,
        style: AppTypography.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size(124, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        backgroundColor: AppColors.brandInk.withValues(alpha: 0.96),
        foregroundColor: Colors.white,
        elevation: 9,
        shadowColor: Colors.black.withValues(alpha: 0.38),
        shape: StadiumBorder(
          side: BorderSide(
            color: AppColors.ctaStart.withValues(alpha: 0.62),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AnimatedSize(
        duration: AppMotion.state,
        curve: AppMotion.easeOut,
        alignment: Alignment.topCenter,
        child: _expanded
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...widget.children,
                    Center(
                      child: TextButton.icon(
                        onPressed: AppHaptics.onPress(_toggle),
                        icon: const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          widget.collapseLabel,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Center(
                child: AnimatedBuilder(
                  animation: _offsetY,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, _offsetY.value),
                    child: child,
                  ),
                  child: pill,
                ),
              ),
      ),
    );
  }
}
