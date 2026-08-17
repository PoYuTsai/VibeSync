# 014 — 抽卡儀式效能重構（setState-per-tick → AnimatedBuilder）

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: HIGH（效能）
- **Category**: Performance
- **Estimated scope**: 1 file（3486 行，重構範圍集中）

## Problem

`lib/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart:315-336` — 全螢幕抽卡儀式用 listener+setState 每幀重建整個 State.build：

```dart
// current
_intro.addListener(_onTick);
_reveal.addListener(_onTick);
_waiting.addListener(_onTick);
...
void _onTick() {
  if (mounted) setState(() {});
}
```

檔內 `AnimatedBuilder` 0 個、`RepaintBoundary` 0 個。~9 秒 reveal＋無限 `_waiting.repeat()` 期間，每幀重跑 `build`（441-556）＋`_buildStage`（578-1050）：重建 20+ 個 CustomPaint、`_CeremonyCardBack`、`_GrandInfoBar`，重排 `_FrontInfo` 文字。`:1398-1399` 的 `BackdropFilter(blur 12)`（_GrandInfoBar）底下正是所有會動的東西，全螢幕合成回讀。120Hz iPhone 上這是 app 最重的動畫。另 `:489,508` 用 `Opacity(opacity: controller.value)` 包整個 stage Column（每幀重建整段）。

各 painter 的 `shouldRepaint` 其實都寫對了——但 widget 每幀被**重新建構**，等於白寫。

## Target

- 移除 `_onTick`/三個 addListener。
- `build` 頂層改一次性建構；會動的節點各自用 `AnimatedBuilder(animation: 對應 controller, child: 靜態子樹)` 訂閱，`child:` passthrough 把不動的部分抽出 builder。模範就在同 repo：`lib/shared/widgets/brand/liquid_motion_frame.dart`（AnimatedBuilder＋child passthrough＋內部 RepaintBoundary＋scoped shouldRepaint）。
- 具體切點（依 commit 7f150ead 的結構）：
  1. 每個 `CustomPaint(painter: XxxPainter(progress: _reveal.value, ...))` → 包 `AnimatedBuilder(animation: _reveal, builder: (_, __) => CustomPaint(painter: XxxPainter(progress: _reveal.value, ...)))`；painter 建構便宜，重點是**只有 CustomPaint 節點**重建。
  2. `Opacity(opacity: contentOpacity...)`（:489、:508 一帶）→ `FadeTransition(opacity: <Animation>)`（把值來源改成 CurvedAnimation/Tween.animate，不再手算）。
  3. `_GrandInfoBar` 的 `BackdropFilter`（:1398）外包 `RepaintBoundary`，且 info bar 整棵作為 AnimatedBuilder 的 `child:` 靜態傳入。
  4. `_waiting.repeat()` 驅動的呼吸態：只包實際呼吸的節點。
- 文字/佈局節點（_FrontInfo 等）不得出現在任何 builder 閉包內（作為 child 傳入）。

## Repo conventions to follow

- 模範檔：`liquid_motion_frame.dart:90-140` 的訂閱結構。
- 該檔已有 reduced-motion 閘門（:255、:357），不動。

## Steps

1. 刪 listener/_onTick；确认沒有其他地方依賴「每幀 setState」的副作用（若 build 內有讀 `_xxx.value` 決定**結構**〔if/else 換子樹〕的地方，改用 `AnimationStatus` listener 精準 setState 一次）。
2. 依上面切點逐段包 AnimatedBuilder/FadeTransition。
3. BackdropFilter 加 RepaintBoundary。
4. DevTools timeline 前後對比。

## Boundaries

- **不改任何視覺**：時間軸、曲線、painter 內容一律不動——這是純重構。
- 不動抽卡邏輯、獎勵發放、狀態機。
- 檔案大：只碰 315-336 的 listener 區與 build/_buildStage 的包裝層。
- 結構若與 7f150ead 有漂移，STOP 回報。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test test/widget/features/practice_chat/`。
- **Feel check**：真機抽一次卡，逐幀看不出與改前差異（錄屏對比）；DevTools performance：reveal 期間 UI thread 每幀 build 時間顯著下降（目標 <4ms）；`_waiting` 呼吸期 CPU 佔用下降。
- **Done when**: 視覺零差異＋timeline 改善可截圖佐證。
