# 002 — 按壓回饋統一（主 CTA、底部 tab、FAB、篩選 chip）＋清死碼

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: HIGH
- **Category**: Physicality & origin / Interruptibility
- **Estimated scope**: 7 files

## Problem

按壓回饋覆蓋率約 3%（162 個 onTap 裡只有 5 處 `PressableScale`）。具體：

1. `lib/shared/widgets/brand/brand_kit.dart:426` — `BrandPrimaryButton`（38 個呼叫點的主 CTA）只有 240ms 灰↔橘狀態漸變，按下毫無縮放回饋。
2. `lib/app/main_shell.dart:189` — 底部 tab 是裸 `GestureDetector`，全 app 最常按的面沒有任何按壓回應。
3. `lib/app/main_shell.dart:254` `HomeFab`、`lib/features/analysis/presentation/widgets/analysis_action_widgets.dart:221` 分析圓鈕 — 深色 62px 圓上的 Material ripple 幾乎看不見。
4. `lib/features/learning/presentation/screens/learning_screen.dart:353` `_CategoryFilterChip`、`lib/features/practice_chat/presentation/screens/practice_collection_screen.dart:1038` `_RarityFilterChip` — 裸 `GestureDetector`＋靜態 `Container`，按壓與選取切換全部瞬跳。
5. `lib/shared/widgets/gradient_button.dart` — 唯一完整實作 0.97 規格的 widget 是**死碼**（production 零使用，只有 `test/visual_proof/` 引用），而 `lib/core/theme/app_motion.dart:23` 還註解「與 GradientButton 既有 0.97 對齊」——規格錨點指向使用者看不到的東西。
6. `lib/shared/widgets/pressable_scale.dart:39-41` — 按下與放開共用同一個 120ms（對稱時序）。按下是系統回應該更快；放開可以慢一點。

```dart
// lib/shared/widgets/pressable_scale.dart:38-43 — current
child: AnimatedScale(
  scale: _pressed ? AppMotion.pressedScale : 1.0,
  duration: AppMotion.press,
  curve: AppMotion.easeOut,
  child: widget.child,
),
```

## Target

- `PressableScale` 升級為不對稱時序：按下 **90ms**、放開 **150ms**，皆 `AppMotion.easeOut`，縮放維持 `AppMotion.pressedScale`（0.97）。做法：`duration: _pressed ? AppMotion.pressDown : AppMotion.pressUp`。
- `AppMotion` 新增：
  ```dart
  /// 按下（系統回應要快）／放開（可以慢一點收）——不對稱時序。
  static const Duration pressDown = Duration(milliseconds: 90);
  static const Duration pressUp = Duration(milliseconds: 150);
  ```
  既有 `press`（120ms）保留給仍在用它的地方，註解標明新按壓一律用 down/up。
- `BrandPrimaryButton`：整顆（AnimatedContainer 起）包進 `PressableScale`。`isLoading`/disabled 時 `enabled: false`。
- 底部 tab item：`GestureDetector` 外包 `PressableScale`。
- `HomeFab` 與分析圓鈕（`FilledButton` at analysis_action_widgets.dart:221）：外包 `PressableScale`。
- 兩個篩選 chip：`Container` → `AnimatedContainer(duration: AppMotion.enter, curve: AppMotion.easeOut)`（讓選取的底色／邊框有 200ms 過渡），外包 `PressableScale`。
- 刪除 `lib/shared/widgets/gradient_button.dart` 與 `test/visual_proof/` 對它的引用（proof_themes.dart:19、density_proof_test.dart 三處改用 `BrandPrimaryButton`），並把 `app_motion.dart:23` 註解改成「按壓縮放比例（PressableScale 全域規格）」。

## Repo conventions to follow

- 模仿 `lib/features/partner/presentation/widgets/home_feature_entries.dart:108` 與 `lib/features/coach_chat/presentation/widgets/coach_cta_card.dart:20` 的 `PressableScale` 包法。
- `PressableScale` 用 `Listener` 不進手勢競技場，包在外層不會搶子樹 onTap——直接包即可。

## Steps

1. `app_motion.dart`：加 `pressDown`/`pressUp`，改 0.97 註解。
2. `pressable_scale.dart`：duration 改三元。
3. `brand_kit.dart` `BrandPrimaryButton.build`：`return PressableScale(enabled: !disabled, child: AnimatedContainer(...))`。
4. `main_shell.dart` tab item：`GestureDetector` 外包 `PressableScale`；`HomeFab` 的 `FloatingActionButton` 外包 `PressableScale`。
5. `analysis_action_widgets.dart`：`FilledButton`（:221）外包 `PressableScale`（包按鈕本體，不包掃描環 Stack）。
6. 兩個 chip：`Container`→`AnimatedContainer`＋外包 `PressableScale`。
7. 刪 `gradient_button.dart`；修 `test/visual_proof/proof_themes.dart` 與 `density_proof_test.dart`。

## Boundaries

- 不動 InkWell 卡片（reply/partner/style card）——ripple 保留，卡片按壓另議。
- 不動 `BrandChoiceChip`（已有 Material pressed 態）。
- 不改任何按鈕的 onPressed 邏輯與語意結構（Semantics 保留在 PressableScale 外側原位）。
- 若 `gradient_button.dart` 出現了新的 production 引用（commit 漂移），STOP 回報。

## Verification

- **Mechanical**: `flutter analyze`；`flutter test`（visual_proof 測試需過）；`grep -rn "GradientButton" lib/` 應為 0。
- **Feel check**：
  - 按住主 CTA：立刻縮到 0.97（~90ms，幾乎瞬間）；放開回彈稍慢（150ms）不彈跳。
  - 底部 tab、FAB、chip 同樣手感；快速連按不抖動、不卡在縮小態。
  - loading 中的主 CTA 按了不縮（enabled: false）。
- **Done when**: 上述成立且 production 無 GradientButton。
