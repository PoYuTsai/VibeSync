# 008 — 載入→內容 crossfade（文章頁閘門＋串流金句輪換）

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: MEDIUM
- **Category**: Purpose（防跳變）
- **Estimated scope**: 2 files

## Problem

A. `lib/features/learning/presentation/screens/article_detail_screen.dart:87-95` — 訂閱閘門判定中回傳整頁 spinner，判定完一幀切成整篇文章：

```dart
// current
if (subscription.isLoading ||
    (subscription.isFreeUser && !_readGateChecked)) {
  return const BrandPageBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(child: CircularProgressIndicator()),
    ),
  );
}
return BrandPageBackground(
  child: Scaffold(...文章本體...),
);
```

B. `lib/features/analysis/presentation/widgets/streaming_analysis_loading_widgets.dart:70-104` — 載入金句每輪 `setState(() => _tick++)` 後 `Text(phrase)` 硬換字，讀起來像 glitch：

```dart
_timer = Timer.periodic(widget.interval, (_) {
  if (!mounted) return;
  setState(() => _tick++);
});
...
Text(phrase, style: ..., textAlign: TextAlign.center),
```

## Target

兩處都用 `AnimatedSwitcher`，數值與寫法完全照 repo 現成範式 `lib/features/subscription/presentation/screens/paywall_screen.dart:449-455`：

```dart
AnimatedSwitcher(
  duration: AppMotion.enter,        // 200ms
  switchInCurve: AppMotion.easeOut,
  switchOutCurve: AppMotion.easeOut,
  child: ...,
)
```

A. 文章頁：兩個分支的共同外殼是 `BrandPageBackground(child: Scaffold(...))`——把「spinner 或 body」的切換點內移，讓 AnimatedSwitcher 只包 body 內容（`key: ValueKey('gate')` / `ValueKey('article')`），背景與 Scaffold 不參與 crossfade（避免整頁雙曝疊影）。

B. 金句：`Text(phrase)` 包 AnimatedSwitcher，`child: Text(phrase, key: ValueKey(phrase), ...)`。字串當 key，同句不重播。

## Repo conventions to follow

- 範式：paywall_screen.dart:449（AppMotion token＋AnimatedSwitcher）。
- AnimatedSwitcher 換字時高度可能不同——外層若因此跳高度，包 `AnimatedSize(duration: AppMotion.enter)` 或給 Text 固定 minHeight（feel check 決定）。

## Steps

1. article_detail_screen.dart：重構兩個 return 成單一 Scaffold＋body 的 AnimatedSwitcher。注意 spinner 分支目前是 `const`，重構後保持 gate 判定邏輯完全不變。
2. streaming_analysis_loading_widgets.dart：Text 包 AnimatedSwitcher。

## Boundaries

- 不動 `_scheduleReadGate` 與訂閱判定。
- 不動金句輪換的 Timer 間隔。
- 不動 AppBar/文章內容。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test`（搜尋引用這兩個 widget 的測試，pump 節奏若吃 Timer 需 `tester.pump(interval)`）。
- **Feel check**：
  - 免費帳號開文章：spinner 淡出、文章淡入，無整頁閃爍、無雙曝。
  - 分析載入時盯金句：字與字之間 200ms 交叉淡變，版面高度不跳。
- **Done when**: 上述成立。
