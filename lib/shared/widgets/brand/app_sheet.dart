// lib/shared/widgets/brand/app_sheet.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';

/// 全 app bottom sheet 統一入口：iOS 抽屜曲線＋不對稱進出時長
/// （340ms 進、260ms 出）。新 sheet 一律用這個，不再裸呼
/// showModalBottomSheet；參數維持 pass-through，不做行為改動。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  Color? barrierColor,
  BoxConstraints? constraints,
  Clip? clipBehavior,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    backgroundColor: backgroundColor,
    shape: shape,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    barrierColor: barrierColor,
    constraints: constraints,
    clipBehavior: clipBehavior,
    sheetAnimationStyle: AnimationStyle(
      duration: AppMotion.sheetIn,
      reverseDuration: AppMotion.sheetOut,
      curve: AppMotion.drawer,
      reverseCurve: Curves.easeOutCubic,
    ),
  );
}
