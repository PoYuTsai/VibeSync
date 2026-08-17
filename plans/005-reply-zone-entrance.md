# 005 — 分析結果回覆區進場動畫（產品 payoff 時刻）

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: HIGH
- **Category**: Missed opportunity（稀有高情緒時刻）
- **Estimated scope**: 1 file（analysis_screen.dart）

## Problem

`lib/features/analysis/presentation/screens/analysis_screen.dart:7567` — 分析跑完，「回覆建議」標題＋橫滑卡組在同一幀直接插入 scroll column，零進場：

```dart
// current（節錄）
if (_hasReplyZoneContent) ...[
  KeyedSubtree(
    key: _replyZoneSectionKey,
    child: Row(children: [ Text('回覆建議', ...), ... ]),
  ),
  const SizedBox(height: 12),
  SingleChildScrollView(
    key: const ValueKey('analysis-reply-zone'),
    scrollDirection: Axis.horizontal,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showRecommendedReplyCard) _buildRecommendedReplyCard(),
        for (final type in _replyStyleOrder) ... _buildHorizontalReplyCard(...),
      ],
    ),
  ),
  ...
]
```

這是使用者等待整個串流分析的目的地，也是全 app 唯一有資格用 `AppMotion.celebrate`（320ms）＋`celebrateCurve`（easeOutBack）的高情緒時刻——目前兩個 token 在這條路徑閒置。

## Target

回覆區第一次出現時（`_hasReplyZoneContent` false→true 的那次 build）播放一次性進場：

- 整個回覆區塊（標題＋卡組）：opacity 0→1 ＋ `Offset(0, 0.04)`→zero（fractional，用 `FractionalTranslation` 或 `SlideTransition`），duration `AppMotion.celebrate`（320ms），curve `AppMotion.easeOut`。
- 卡組內每張卡 **stagger 50ms**（第 n 張延遲 n×50ms，最多 6 張＝最後一張 250ms 開始），每張各自 opacity 0→1＋scale 0.96→1.0，duration `AppMotion.celebrate`，curve `AppMotion.celebrateCurve`（easeOutBack——這裡是唯一允許彈感的檔位）。stagger 純裝飾：不得阻擋互動（卡從第一幀就可點）。
- 只播一次：記 `bool _replyZonePlayed`，重播條件是新一輪分析（`_hasReplyZoneContent` 歸 false 後再變 true）。
- reduced-motion（`MediaQuery.maybeOf(context)?.disableAnimations ?? false`）：直接顯示，不播。

實作建議：一個 `AnimationController _replyZoneEntrance`（total = 320 + 5×50 = 570ms），區塊與各卡用 `Interval` 切段：
```dart
// 區塊：Interval(0, 320/570)
// 第 n 張卡：Interval(n*50/570, (n*50+320)/570, curve: AppMotion.celebrateCurve)
```
在 `_hasReplyZoneContent` 轉 true 的 setState 後 `_replyZoneEntrance.forward(from: 0)`。

## Repo conventions to follow

- token 全取 `AppMotion`；reduced-motion 寫法照 `analysis_action_widgets.dart:113`。
- 分析完成已有一次性自動捲動錨在 `_replyZoneSectionKey`（見原碼註解）——進場動畫不得干擾該捲動（先捲動後播、或並行皆可，feel check 驗證不打架）。

## Steps

1. State 加 controller＋`_replyZonePlayed`；`dispose` 處理。
2. 找到 `_hasReplyZoneContent` 由 false→true 的賦值點（串流完成 handler），觸發 `forward(from: 0)`。
3. 回覆區塊包 `AnimatedBuilder`（`FadeTransition`＋`SlideTransition`；卡組 Row 的每張卡包 per-card interval 的 fade+scale）。
4. `_buildRecommendedReplyCard`／`_buildHorizontalReplyCard` 的回傳外層包 stagger wrapper（可寫一個私有 `_StaggeredCard(index, animation, child)` helper，只在本檔）。

## Boundaries

- 不動卡片內容、不動 outcome bar、不動自動捲動邏輯。
- 不動 `_hasReplyZoneContent` 的判斷本身。
- analysis_screen.dart 很大（9000+ 行）——只碰回覆區這一段與 state 宣告。
- 歷史紀錄回看（analysis_record_detail_screen）不在範圍：那裡是回看不是 payoff。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test test/widget/features/analysis/`（hydration 測試有找 '共鳴' 等字，確認沒被進場動畫的 offstage 打壞——必要時 pumpAndSettle）。
- **Feel check**：
  - 跑一次真分析：結果區淡入上移，卡片從左到右 50ms 級距依序落定，帶極輕微回彈；總長 ≤600ms。
  - 動畫中立刻點第一張卡可以點。
  - 回看歷史紀錄、切換 tab 回來：不重播。
  - reduce motion：直接出現。
- **Done when**: 上述成立。
