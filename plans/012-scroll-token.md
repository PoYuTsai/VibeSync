# 012 — 程式捲動收斂成 AppMotion.scroll（12 處）

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: MEDIUM
- **Category**: Cohesion & tokens
- **Estimated scope**: 8 files

## Problem

「捲到剛產生的東西」一個意圖，12 個站點寫了 250/260/280/300/320/350/360 七種數字、兩種曲線（弱版內建 `Curves.easeOut` 與 `easeOutCubic`）：

- `lib/features/analysis/presentation/screens/analysis_screen.dart:589-590`（280, easeOut）、`:678-679`（260, easeOut）、`:3378-3379`（300, easeOut）
- `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart:215-216`（250, easeOut）
- `lib/features/new_topic/presentation/widgets/new_topic_view.dart:286-287`（300, easeOut）
- `lib/features/opener/presentation/screens/opening_rescue_screen.dart:456-457`（280, easeOut）、`:637-638`（300, easeOut）
- `lib/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart:359-360`（260, easeOut）
- `lib/features/learning/presentation/widgets/ebook_entry_list.dart:79`（320, easeOutCubic）
- `lib/features/practice_chat/presentation/screens/practice_collection_screen.dart:188-189`（350, easeOutCubic）
- `lib/features/keyboard/presentation/screens/keyboard_setup_screen.dart:123`（360, easeOutCubic）、`:151`（320, easeOutCubic）

## Target

`app_motion.dart` 加：

```dart
/// 程式捲動（scrollTo/animateTo「捲去剛產生的東西」）統一檔位。
static const Duration scroll = Duration(milliseconds: 280);
```

12 處全部改 `duration: AppMotion.scroll, curve: AppMotion.easeOut`（強力 easeOut token，取代弱版內建曲線）。

## Repo conventions to follow

- 各檔多已 import core/theme；補 `app_motion.dart` import。
- 行號以 grep 重新定位（`animateTo\|ensureVisible` 附近的 `Duration(milliseconds:`），數字以上表為準；若某站點性質不是「捲去目標」（例如 keyboard_setup 的 PageView 翻頁），維持翻頁語意但仍換 token 曲線、時長不超過 300ms——由 executor 現場判斷並在 commit message 註明例外。

## Steps

1. token 加入。
2. 逐站替換（一個 commit）。

## Boundaries

- 不動捲動目標計算、offset 邏輯。
- 不動非程式捲動的 Duration。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test`；上列行號附近 grep 不再有裸數字 duration。
- **Feel check**：分析頁新增訊息自動捲到底、opener 生成後捲到結果——動作齊一、尾段收束乾脆（強 easeOut 的差異）。
- **Done when**: 上述成立。
