# 011 — 四張報表圖收斂成單一 chartReveal token

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: MEDIUM
- **Category**: Easing & duration / Cohesion
- **Estimated scope**: 5 files

## Problem

同一個概念「圖表揭示」四個數字，最長 2.3 倍超預算（皆已有 disableAnimations 三元，該部分不動）：

- `lib/features/report/presentation/widgets/heat_trend_chart.dart:344` — `Duration(milliseconds: 700)`
- `lib/features/report/presentation/widgets/conversation_comparison_chart.dart:98` — `520`
- `lib/features/report/presentation/widgets/practice_temperature_chart.dart:358` — `480`
- `lib/features/report/presentation/widgets/stage_distribution_chart.dart:69` — `480`

曲線皆 `Curves.easeOutCubic`（保留）。

## Target

`lib/core/theme/app_motion.dart` 加：

```dart
/// 報表圖揭示——四張圖共用一個檔位（2026-08 收斂前是 480/520/700 三種）。
static const Duration chartReveal = Duration(milliseconds: 300);
```

四處的非 reduced-motion 分支換 `AppMotion.chartReveal`；`disableAnimations ? Duration.zero : ...` 結構原樣。

## Repo conventions to follow

- token 加在 AppMotion（分級註解風格照該檔既有）。
- 各 chart 檔 import `app_motion.dart`（相對路徑照各檔既有 core/theme import）。

## Steps

1. app_motion.dart 加 token。
2. 四處替換。

## Boundaries

- 不動曲線、不動 disableAnimations 結構、不動圖表資料邏輯。
- fl_chart `swapAnimationDuration` 語意不變，只換值。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test`; `grep -rn "480\|520\|700" lib/features/report/presentation/widgets/*.dart` 不再出現在 duration 位置。
- **Feel check**：開「我的報表」，四張圖同節奏 300ms 展開，趨勢線不再拖 0.7 秒。
- **Done when**: 上述成立。
