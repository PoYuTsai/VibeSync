import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_typography.dart';

/// 垂直捲動提示 pill（2026-08-18 呈現精修拍板）：結果很長時掛在畫面右下，
/// 提示下方還有目標區塊（公式開場／公式新話題）。目標一進入視口就視為
/// 「看過」並收起，直到 [resetToken] 換新（新一輪結果）才重新提示。
/// 點擊會直接捲到目標區塊。目標不存在（無結果／空清單）時整顆不渲染。
class MoreBelowHint extends StatefulWidget {
  const MoreBelowHint({
    super.key,
    required this.controller,
    required this.targetKey,
    required this.label,
    this.resetToken,
  });

  final ScrollController controller;
  final GlobalKey targetKey;
  final String label;

  /// 換新一輪結果時傳不同物件即可重新提示。
  final Object? resetToken;

  @override
  State<MoreBelowHint> createState() => _MoreBelowHintState();
}

class _MoreBelowHintState extends State<MoreBelowHint> {
  bool _seen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_checkTargetVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTargetVisibility();
    });
  }

  @override
  void didUpdateWidget(MoreBelowHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_checkTargetVisibility);
      widget.controller.addListener(_checkTargetVisibility);
    }
    if (oldWidget.resetToken != widget.resetToken) {
      _seen = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkTargetVisibility();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_checkTargetVisibility);
    super.dispose();
  }

  void _checkTargetVisibility() {
    if (!mounted || _seen) return;
    final targetContext = widget.targetKey.currentContext;
    if (targetContext == null) {
      // 目標尚未掛載（例如結果剛 setState）；下一幀或下次捲動再判。
      return;
    }
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final targetTop = renderObject.localToGlobal(Offset.zero).dy;
    final viewportBottom = MediaQuery.sizeOf(context).height;
    if (targetTop < viewportBottom) {
      setState(() => _seen = true);
    } else {
      // 從隱藏變可見（例如 reset 後）需要重繪一次。
      setState(() {});
    }
  }

  void _scrollToTarget() {
    final targetContext = widget.targetKey.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.08,
      duration: AppMotion.scroll,
      curve: AppMotion.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_seen || widget.targetKey.currentContext == null) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('more-below-hint'),
        borderRadius: BorderRadius.circular(999),
        onTap: _scrollToTarget,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.coachSurfaceRaised.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.coachAccent.withValues(alpha: 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: AppTypography.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_downward_rounded,
                size: 15,
                color: AppColors.coachAccentBright,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
