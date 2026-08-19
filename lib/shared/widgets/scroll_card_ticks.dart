import 'package:flutter/material.dart';

import '../../core/services/app_haptics.dart';

/// Mac Dock 觸感的垂直翻譯（2026-08-19 Eric：復刻報告「對象作戰板」的
/// 滑動節拍）。作戰板是手指掃過每塊磚、「最近的磚換人」那刻打一下輕
/// 觸覺；垂直清單版＝捲動時每張卡通過「焦點線」（視窗頂往下
/// [focusFraction]）的那一刻打一下 [AppHaptics.tap]——Mac 滾輪的咔咔感，
/// 卡片越多節拍越密。
///
/// 刻意只做觸覺不做縮放：整寬卡片縮放會推擠上下文造成版面抖動。
/// 用法：包住頁面的捲動視圖，然後把每張候選卡包進 [CardTickTarget]。
class ScrollCardTicks extends StatefulWidget {
  const ScrollCardTicks({
    super.key,
    required this.child,
    this.axis = Axis.vertical,
    this.focusFraction = 0.25,
  });

  final Widget child;

  /// 監聽的捲動軸向；橫向卡列（開場白五風格卡）用 [Axis.horizontal]，
  /// 焦點線改為寬度比例——就是 Dock 本來的樣子。
  final Axis axis;

  /// 焦點線位置＝本 widget 主軸尺寸 × 此比例（從頂端／左端算）。
  final double focusFraction;

  @override
  State<ScrollCardTicks> createState() => _ScrollCardTicksState();
}

class _ScrollCardTicksState extends State<ScrollCardTicks> {
  final Map<int, BuildContext> _targets = {};
  int? _focused;

  void _register(int index, BuildContext targetContext) {
    _targets[index] = targetContext;
  }

  void _unregister(int index, BuildContext targetContext) {
    if (identical(_targets[index], targetContext)) _targets.remove(index);
  }

  bool _checkScheduled = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    if (notification.metrics.axis != widget.axis) return false;
    // 通知先於 layout：這一刻卡片還在舊位置。排到 post-frame 再量，
    // 每幀最多一次（同時就是節流）。
    if (_checkScheduled) return false;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (mounted) _evaluateFocus();
    });
    return false; // 不攔截，讓通知繼續往上冒。
  }

  void _evaluateFocus() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final horizontal = widget.axis == Axis.horizontal;
    final mainExtent = horizontal ? box.size.width : box.size.height;
    final focusOffset = box.localToGlobal(
      horizontal
          ? Offset(mainExtent * widget.focusFraction, 0)
          : Offset(0, mainExtent * widget.focusFraction),
    );
    final focus = horizontal ? focusOffset.dx : focusOffset.dy;

    int? current;
    for (final entry in _targets.entries) {
      final rb = entry.value.findRenderObject() as RenderBox?;
      if (rb == null || !rb.attached) continue;
      final origin = rb.localToGlobal(Offset.zero);
      final start = horizontal ? origin.dx : origin.dy;
      final extent = horizontal ? rb.size.width : rb.size.height;
      if (start <= focus && start + extent > focus) {
        current = entry.key;
        break;
      }
    }
    if (current != null && current != _focused) {
      // 第一次落點（進頁後第一次捲動）不打——避免一動就震；
      // 卡片之間的空隙不清 _focused，否則同一張卡進出邊緣會連震。
      if (_focused != null) AppHaptics.tap();
      _focused = current;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: _TickScope(state: this, child: widget.child),
    );
  }
}

class _TickScope extends InheritedWidget {
  const _TickScope({required this.state, required super.child});

  final _ScrollCardTicksState state;

  static _ScrollCardTicksState? of(BuildContext context) => context
      .getInheritedWidgetOfExactType<_TickScope>()
      ?.state;

  @override
  bool updateShouldNotify(_TickScope oldWidget) => false;
}

/// 掛在每張候選卡外層；[index] 在同一個 [ScrollCardTicks] 範圍內唯一。
/// 不在 [ScrollCardTicks] 底下時是無害的透明殼。
class CardTickTarget extends StatefulWidget {
  const CardTickTarget({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<CardTickTarget> createState() => _CardTickTargetState();
}

class _CardTickTargetState extends State<CardTickTarget> {
  _ScrollCardTicksState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope?._unregister(widget.index, context);
    _scope = _TickScope.of(context);
    _scope?._register(widget.index, context);
  }

  @override
  void didUpdateWidget(covariant CardTickTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _scope?._unregister(oldWidget.index, context);
      _scope?._register(widget.index, context);
    }
  }

  @override
  void dispose() {
    _scope?._unregister(widget.index, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
