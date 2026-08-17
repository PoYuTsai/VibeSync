# 009 — 分析紀錄 sheet → 詳情頁改 SharedAxis 轉場

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: MEDIUM
- **Category**: Purpose（來源與去向的空間關係）
- **Estimated scope**: 1 file
- **依賴**: 006（animations 套件已加入）

## Problem

`lib/features/analysis/presentation/screens/partner_analysis_records_screen.dart:256-262` — 從 74% 高的 bottom sheet 裡直接 push 全螢幕頁，預設橫滑轉場，sheet 還停在底下；起點（sheet 內的 row）與終點（全頁）毫無動線關係：

```dart
// current
Future<void> _openRecord(AnalysisRecord record) async {
  final deleted = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => AnalysisRecordDetailScreen(
        record: record,
        platform: _platformFor(record),
        ...
```

## Target

保留「push 全頁、sheet 留底、pop 回 sheet 繼續逛」的行為（使用者會連看多筆），只把轉場換成 **SharedAxisTransition（scaled / Z 軸）**——「往內走一層」的語意：

```dart
import 'package:animations/animations.dart';

final deleted = await Navigator.of(context).push<bool>(
  PageRouteBuilder<bool>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) =>
        AnalysisRecordDetailScreen(
      record: record,
      platform: _platformFor(record),
      onDelete: ...,   // 原參數全部照抄
    ),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      transitionType: SharedAxisTransitionType.scaled,
      fillColor: Colors.transparent,
      child: child,
    ),
  ),
);
```

`fillColor: Colors.transparent` 讓底下的 sheet/scrim 在轉場中自然透出，不閃白。

## Repo conventions to follow

- 這是 repo 第一個 animations 套件的 route 級使用；依 006 已加好的依賴。

## Steps

1. `_openRecord` 依上述改寫（原 `onDelete` 等參數逐字保留）。

## Boundaries

- 不動 sheet 本身與列表。
- 不動 AnalysisRecordDetailScreen。
- 回傳型別 `<bool>` 與 `deleted` 處理不變。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test`。
- **Feel check**：sheet 裡點一筆——詳情頁放大浮現（無橫滑）；back 縮回 sheet；連續開三筆流暢；刪除一筆返回後 sheet 列表有反映。
- **Done when**: 上述成立。
