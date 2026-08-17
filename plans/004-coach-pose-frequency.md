# 004 — Sydney 姿勢重擲降頻＋換圖 crossfade

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: MEDIUM
- **Category**: Purpose & frequency
- **Estimated scope**: 2 files

## Problem

`lib/app/main_shell.dart:228-236` — 每次切回首頁 tab 都重擲 Sydney 姿勢：

```dart
void _updateCurrentTab(int nextIndex) {
  if (nextIndex == 0) {
    _changeCoachPose();
  }
  _currentIndex = nextIndex;
}

void _changeCoachPose() {
  _coachPose = _coachPose.differentPose(_coachRandom);
}
```

兩個問題：稀有彩蛋被 100+ 次/天的動作重擲（新鮮感歸零）；立繪在 tab 硬切下無動效地變身（內容跳變）。`_coachPose` 消費點：`main_shell.dart:131` 傳給 `PartnerListScreen(coachPose: ...)`。

## Target

1. **降頻**：改成「每次 app 冷啟動隨機一次＋之後每回到 tab 0 有 20% 機率換」——保留驚喜、不再每次都變。實作：`_changeCoachPose()` 開頭加 `if (_coachRandom.nextDouble() >= 0.2) return;`。
2. **換圖 crossfade**：找到 PartnerListScreen 內實際渲染 coachPose 圖的 widget（順 `coachPose` 參數往下追，應在 home coach 視覺區），外包：
   ```dart
   AnimatedSwitcher(
     duration: AppMotion.enter, // 200ms
     switchInCurve: AppMotion.easeOut,
     switchOutCurve: AppMotion.easeOut,
     child: Image.asset(pose.assetPath, key: ValueKey(pose)),
   )
   ```
   `key: ValueKey(pose)` 是 AnimatedSwitcher 判斷換圖的關鍵。

## Repo conventions to follow

- AnimatedSwitcher 寫法模仿 `lib/features/subscription/presentation/screens/paywall_screen.dart:449-455`（duration/curve 用 AppMotion token）。

## Steps

1. `main_shell.dart` `_changeCoachPose` 加機率閘（0.2）。
2. 追 `coachPose` 到渲染點，包 AnimatedSwitcher（key 綁 pose）。
3. 若渲染點已有其他動畫包裝（如 LiquidMotionFrame），AnimatedSwitcher 放在圖的最內層、只包 Image。

## Boundaries

- 不動姿勢清單與 asset。
- 001 也會動 main_shell.dart——先做 001 再做本計畫（rebase 順序）。
- 若 `coachPose` 傳遞鏈與描述不符（漂移），STOP 回報。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test`。
- **Feel check**：來回切 tab 十次，Sydney 大多數時候不變；變的時候是 200ms 淡變不是瞬跳。
- **Done when**: 上述成立。
