# 015 — 首頁效能小刀三處（dock 指針、ShaderMask、名單卡液態框）

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: MEDIUM（效能）
- **Category**: Performance
- **Estimated scope**: 3 files

## Problem

A. `lib/features/report/presentation/widgets/partner_mindmap_card_list.dart:88` — 指針移動（最高 120 次/秒）每次 `setState` 重建整個 dock（Column→Stack→ListView.separated 全部 `_buildTile`），實際變的只有 `_influence` 範圍內 2-3 張 tile 的 scale：

```dart
void _updatePointer(Offset globalPosition) {
  ... setState(() { _pointerContentX = contentX; _focusedIndex = nearest; });
}
```

B. `lib/features/partner/presentation/widgets/home_coach_presence.dart:120` — 340px 立繪的**靜態**漸層 ShaderMask（`BlendMode.dstIn`）掛在首頁 CustomScrollView（三個掛載點：partner_list_screen.dart:80、624、711），該 screen `RepaintBoundary` = 0：每個捲動幀多付一層 offscreen saveLayer，遮罩卻從不變。

C. `lib/features/partner/presentation/widgets/partner_list_card.dart:96-105` — 每張對象卡頭像一個 `LiquidMotionFrame(strength: 0.92, duration: 6800ms)` 永動 painter（report 卡用的 strength 只有 0.065–0.12，0.92 是全 codebase 最強）；N 張可見卡 ＝ N 個 controller＋N 個每幀 3 次 drawRRect（含 glowRadius 10 blur）。

## Target

A. `_pointerContentX` 改 `ValueNotifier<double>`；tile 的 scale 段包 `ValueListenableBuilder`，`_updatePointer` 不再 setState（`_focusedIndex` 若只影響 scale 計算就併進 notifier；若影響其他 UI 再單獨 setState、但只在值真的變時）。

B. `home_coach_presence.dart` 的 ShaderMask＋Image 整棵包 `RepaintBoundary`。（更省的替代：把漸層淡出直接烘進 asset——但 asset 管線不在本計畫範圍，先 RepaintBoundary。）

C. 名單卡液態框降負：`strength: 0.92` → `0.4`、`duration: 6800` → `9000`（更慢更淡，視覺仍有生命感）。若 Eric 驗收覺得太淡再回調——在 commit message 標明可調參數位置。

## Repo conventions to follow

- ValueListenableBuilder 葉更新即 repo 目標型態；LiquidMotionFrame 參數語意見該檔 doc comment。

## Steps

1. A：state 改 notifier＋builder，刪 per-move setState。
2. B：RepaintBoundary。
3. C：參數調整。

## Boundaries

- 不動 dock 的 cosine falloff 數學與 `AnimatedScale`（那部分是對的）。
- 不動 LiquidMotionFrame 本體。
- 不改 asset。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test`。
- **Feel check**：報表頁 dock 滑指跟手依舊；首頁捲動 performance overlay raster 時間下降；對象卡頭像仍有淡淡液態光但不搶眼。
- **Done when**: 上述成立；C 的視覺由 Eric 真機拍板。
