# 013 — showAppSheet()：20 個 bottom sheet 統一動效

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: MEDIUM
- **Category**: Cohesion & tokens
- **Estimated scope**: ~16 files（1 新 wrapper＋15 個呼叫檔）

## Problem

20 個 `showModalBottomSheet` 呼叫點零自訂動效（`grep transitionAnimationController\|sheetAnimationStyle` = 0），全吃 Flutter 預設 250ms decelerate——app 最常見的抽屜手勢是動效系統唯一沒管到的面。已知呼叫點：

`draft_polish_sheet.dart:46`、`reply_refine_sheet.dart:88`、`practice_game_intro_sheet.dart:26`、`analysis_platform_picker.dart:37`、`growth_preview_sheet.dart:11`、`conversation_reassign_picker.dart:27`、`partner_analysis_records_screen.dart:44`、`message_bubble.dart:132`、`practice_chat_screen.dart:397`、`:2332`、`practice_profile_sheet.dart:19`、`add_partner_screen.dart:367`、`:427`、`home_quota_strip.dart:43`＋其餘以 `grep -rn "showModalBottomSheet" lib/` 為準。

## Target

新檔 `lib/shared/widgets/brand/app_sheet.dart`：

```dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';

/// 全 app bottom sheet 統一入口：iOS 抽屜曲線＋不對稱進出時長。
/// 新 sheet 一律用這個，不再裸呼 showModalBottomSheet。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? barrierColor,
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
    barrierColor: barrierColor,
    sheetAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 340),
      reverseDuration: const Duration(milliseconds: 260),
      curve: AppMotion.drawer,
      reverseCurve: Curves.easeOutCubic,
    ),
  );
}
```

`app_motion.dart` 加：

```dart
/// iOS 抽屜曲線（Emil/Vaul 系）：進場尾段極長收束。
static const Curve drawer = Cubic(0.32, 0.72, 0, 1);
```

20 個呼叫點機械替換成 `showAppSheet`，各站現用的 named 參數照搬；wrapper 缺哪個參數就補進 wrapper（保持 pass-through，不做行為改動）。

## Repo conventions to follow

- 檔案放 `lib/shared/widgets/brand/`（brand_kit 同層）。
- `sheetAnimationStyle` 需 Flutter ≥3.22（repo Dart 3.13 世代，符合；若編譯器說無此參數，STOP 回報，fallback 方案是 `transitionAnimationController`）。

## Steps

1. token＋wrapper。
2. `grep -rn "showModalBottomSheet" lib/` 全清單逐站替換（一站一檢查參數）。
3. 完成後 `grep -rn "showModalBottomSheet" lib/ | grep -v app_sheet.dart` 應為 0。

## Boundaries

- 只換入口，不動任何 sheet 內容、高度、drag 行為。
- 拖曳關閉的原生速度判斷不受影響（sheetAnimationStyle 只管程式開關的補間）。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test`; 上面的 grep 檢查。
- **Feel check**：開草稿潤飾、微調、平台挑選三個 sheet——進場尾段有「軟著陸」感（drawer 曲線特徵）、關閉比開啟快；手勢下拉關閉手感不變。
- **Done when**: 上述成立。
