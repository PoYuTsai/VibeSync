# 001 — 底部 tab 切換加 fade-through 轉場（保留分頁狀態）

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: HIGH
- **Category**: Purpose & frequency / Missed opportunity
- **Estimated scope**: 1 file（lib/app/main_shell.dart）＋1 token

## Problem

`lib/app/main_shell.dart:126` — 底部三個 tab 用 `IndexedStack` 硬切，一幀跳變。這是全 app 執行最多次的轉場，三個 tab 視覺差異大（對象列表／報表圖表／學習書架），Material 規範對無空間關係的頂層目的地就是 fade-through。

```dart
// lib/app/main_shell.dart:126 — current
body: IndexedStack(
  index: _currentIndex,
  children: [
    PartnerListScreen(
      bottomPadding: 32,
      ...
```

```dart
// lib/app/main_shell.dart:219-225 — current
void _selectTab(int index) {
  final nextIndex = _normalizeTabIndex(index);
  if (_currentIndex != nextIndex) {
    setState(() => _updateCurrentTab(nextIndex));
  }
  context.go('/?tab=${MainShell.tabRouteFromIndex(nextIndex)}');
```

附帶問題（同一結構修）：`IndexedStack` 不會替隱藏 child 關 ticker，背景 tab 的環境動畫（MyReportScreen 的 LiquidMotionFrame 8400ms、PracticeTemperatureChart 9600ms、每張對象卡 6800ms）在看不見時照跑（電池）。品牌元件內部已寫好 `TickerMode.valuesOf(context)` 閘門（`lib/shared/widgets/brand/liquid_motion_frame.dart:98`），只差殼層沒掛 `TickerMode`。

## Target

**不要用 `PageTransitionSwitcher`**（會銷毀非當前 tab 的 state，違背 IndexedStack 保狀態的目的）。fade-through 是序列動畫（先淡出舊、再淡入＋微縮放新），單層 IndexedStack 可忠實實作：

1. Shell 掛一個 `AnimationController`（`vsync: this`，總長 300ms）。
2. 切 tab 時：
   - **Phase A（0→90ms）**：整個 IndexedStack opacity 1→0，`Curves.easeOut`。
   - **在 90ms 時間點**（controller status/value listener 或 `TweenSequence`）呼叫 `setState` 換 `_currentIndex`。
   - **Phase B（90→300ms）**：opacity 0→1 ＋ scale 0.92→1.0，`AppMotion.easeOut`（=Cubic(0.23,1,0.32,1)）。
3. `disableAnimations == true` 時直接 `setState` 硬切（現行為即 fallback）。
4. 動畫進行中再點另一 tab：controller 重新從目前值出發（不得閃白）；最簡做法是 Phase A 從「目前 opacity」補間到 0。
5. IndexedStack 每個 child 包 `TickerMode(enabled: _currentIndex == i, child: ...)`。

實作骨架（executor 依此展開）：

```dart
late final AnimationController _tabTransition = AnimationController(
  vsync: this, duration: const Duration(milliseconds: 300));
int? _pendingIndex;

// _selectTab 內：
final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
if (reduceMotion) {
  setState(() => _updateCurrentTab(nextIndex));
} else {
  _pendingIndex = nextIndex;
  _tabTransition.forward(from: 0);
}
// controller listener：value >= 0.3（=90ms）且 _pendingIndex != null 時
// setState 換 index 並清 _pendingIndex。

// build 內：
body: AnimatedBuilder(
  animation: _tabTransition,
  builder: (context, child) {
    final t = _tabTransition.value;
    final out = (t / 0.3).clamp(0.0, 1.0);        // Phase A 進度
    final inn = ((t - 0.3) / 0.7).clamp(0.0, 1.0); // Phase B 進度
    final fadingOut = _pendingIndex != null;
    final opacity = fadingOut
        ? 1 - Curves.easeOut.transform(out)
        : AppMotion.easeOut.transform(inn);
    final scale = fadingOut ? 1.0 : 0.92 + 0.08 * AppMotion.easeOut.transform(inn);
    return Opacity(opacity: _tabTransition.isAnimating || _pendingIndex != null ? opacity : 1.0,
      child: Transform.scale(scale: _tabTransition.isAnimating ? scale : 1.0, child: child));
  },
  child: IndexedStack(
    index: _currentIndex,
    children: [
      for (final (i, tab) in tabs.indexed)
        TickerMode(enabled: _currentIndex == i, child: tab),
    ],
  ),
),
```

（`tabs` 即現有三個 screen；executor 保持現有建構參數不動。）

## Repo conventions to follow

- Duration/curve 一律取 `lib/core/theme/app_motion.dart` 的 token；本計畫新增一個 token：
  ```dart
  /// tab fade-through 總長（90ms 出＋210ms 進，Material fade-through 規格）。
  static const Duration tabTransition = Duration(milliseconds: 300);
  ```
- reduced-motion 判斷寫法照 `lib/features/analysis/presentation/widgets/analysis_action_widgets.dart:113`：`MediaQuery.maybeOf(context)?.disableAnimations ?? false`。

## Steps

1. `lib/core/theme/app_motion.dart`：加 `tabTransition` token（上面數值）。
2. `lib/app/main_shell.dart`：`_MainShellState` 改 `with TickerProviderStateMixin`（若現在不是），加 controller＋`_pendingIndex`＋listener，`dispose` 記得處理。
3. `_selectTab` 分流 reduced-motion／動畫路徑（`context.go` 那行維持原位不動）。
4. body 換成上述 AnimatedBuilder 包 IndexedStack；三個 child 各包 `TickerMode`。
5. 快速連點防護：動畫中再點，`_pendingIndex` 直接更新成最新目標即可（Phase A 繼續走完，換到最新 index）。

## Boundaries

- 不動三個 tab screen 本身、不動 `_updateCurrentTab` 的教練姿勢邏輯（004 處理）。
- 不新增依賴（本計畫不需要 animations 套件）。
- 若 main_shell.dart 與 commit 7f150ead 相比結構有漂移，STOP 回報。

## Verification

- **Mechanical**: `flutter analyze` 無新 issue；`flutter test test/widget/` 全過（若有 main_shell 測試需先看它斷言什麼）。
- **Feel check**（真機或 simulator）：
  - 切 tab：舊頁快速淡出→新頁淡入帶極輕微放大，全程 ≤300ms，無白閃、無左右滑動感。
  - 快速連點三個 tab 不卡死、不閃爍，最後停在最後點的 tab。
  - 切走再切回，各 tab 捲動位置與狀態保留（IndexedStack 沒被換掉的證據）。
  - iOS 設定開「減少動態效果」後：tab 硬切（無動畫），功能正常。
  - 停在 tab 0 時，用 Flutter DevTools performance overlay 確認報表 tab 的圖表動畫沒在背景跑（TickerMode 生效；切到 tab 1 才動）。
- **Done when**: 上述全部成立。
