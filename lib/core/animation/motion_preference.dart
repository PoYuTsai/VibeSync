// lib/core/animation/motion_preference.dart
import 'package:flutter/widgets.dart';

/// 這個 subtree 現在該不該動。
///
/// 兩個 guard 一起看，跟 `LiquidMotionFrame` 同一套紀律：
/// - [MediaQueryData.disableAnimations]：使用者在 iOS 開了「減少動態效果」。
/// - [TickerMode]：subtree 被靜音（例如躺在非當前路由底下）。少了這個，
///   進場動畫會卡在第一格——數字永遠停在 0，比沒動畫還糟。
bool motionDisabled(BuildContext context) =>
    (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
    !TickerMode.valuesOf(context).enabled;
