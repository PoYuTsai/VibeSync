# 010 — 分析主鈕進場壓進 300ms 預算

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: MEDIUM
- **Category**: Easing & duration
- **Estimated scope**: 1 file

## Problem

`lib/features/analysis/presentation/widgets/analysis_action_widgets.dart:103-107` — 分析主鈕（每次分析都看到的 primary CTA）controller 總長 720ms；進場段 `Interval(0, 0.52)` ＝ **~375ms** 的 opacity+scale，超出 300ms UI 預算；掃描環吃滿 720ms：

```dart
// current
_controller = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 720),
);
...
final entrance = const Interval(0, 0.52, curve: Curves.easeOutCubic).transform(value);
final scan = const Interval(0.08, 1, curve: Curves.easeOutCubic).transform(value);
```

## Target

按鈕本體 240ms 內落定，掃描環（裝飾）可以稍長但整體收斂：

```dart
_controller = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 480),
);
...
final entrance = const Interval(0, 0.5, curve: Curves.easeOutCubic).transform(value);   // = 240ms
final scan = const Interval(0.08, 1, curve: Curves.easeOutCubic).transform(value);       // = ~440ms
```

opacity/scale 公式（`0.18 + 0.82*entrance`、`0.88 + 0.12*entrance`）不動。

## Repo conventions to follow

- 該檔已有標準 reduced-motion 閘門（:110-124），不需動。
- curve 維持 `Curves.easeOutCubic`（該檔既有選擇，本計畫只修時長）。

## Steps

1. 720 → 480；`0.52` → `0.5`。

## Boundaries

- 不動掃描環視覺、按鈕結構、`AnalysisScrollHint`（850ms bob 是另一元件，保留）。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test`。
- **Feel check**：進分析頁，主鈕 ~240ms 內清晰落定，不再有「等它出現」的感覺；掃描環擴散仍完整。
- **Done when**: 上述成立。
