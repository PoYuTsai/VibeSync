# 016 — token 採用率總清掃（機械替換＋孤兒值收斂）

- **Status**: TODO
- **Commit**: 7f150ead
- **Severity**: LOW（清理槓桿高）
- **Category**: Cohesion & tokens
- **Estimated scope**: ~20 files，全部機械替換

## Problem

token 採用率約 15%（duration 12/109、curve 14/66 用 token）。四類清掃：

**A. 數值已等於 token 的 18 處硬編**（零視覺變化）：`grep -rn "milliseconds: 200)\|milliseconds: 240)\|milliseconds: 320)" lib/ --include="*.dart"` 全清單，例：`onboarding_screen.dart:266`（200）、`glassmorphic_segmented_button.dart:33`（200）、`practice_game_intro_sheet.dart:521`（200）、`ebook_flip_card.dart:24`（320）、`analysis_screen.dart:609/:648`（320）、`screenshot_recognition_dialog.dart:1418`（320）。→ 200=`AppMotion.enter`、240=`AppMotion.state`、320=`AppMotion.celebrate`（僅當語意相符——320 用在慶祝/大型進場才換 celebrate，否則換 `state` 並統一到 240）。

**B. 180ms 孤兒值六處＋多數沒給 curve（＝linear）**：`draft_polish_sheet.dart:188`、`brand_kit.dart:640`、`partner_list_screen.dart:461`、`coach_surface.dart:288`、`keyboard_setup_screen.dart:576`、`onboarding_questionnaire_page.dart:110`（另 :188 是 150）。這些全是選取/切換態。→ 一律 `duration: AppMotion.enter, curve: AppMotion.easeOut`（200ms；比 180 慢 20ms 無感，換來單一檔位）。注意 `brand_kit.dart:427-428` 同檔已示範正確寫法。

**C. 顯眼進場用弱版內建曲線五處**：`screenshot_recognition_dialog.dart:586`（220ms easeOut）、`practice_collection_screen.dart:689-692`（引導 overlay 200ms easeOut）、`onboarding_questionnaire_page.dart:111`（easeOut）、`onboarding_screen.dart:102-103`（PageView 翻頁 300ms easeInOut——翻頁保留 easeInOut 語意，但時長不動、只確認 ≤300）、`partner_mindmap_card_list.dart:177-178`（120ms easeOut→`AppMotion.pressDown` 若 002 已入，否則 `AppMotion.press`）。→ `Curves.easeOut` 換 `AppMotion.easeOut`（強曲線，時長不變）。

**D. 展開/收合對稱時序**：`ebook_shelf_section.dart:308` `AnimatedRotation(turns:…, duration: 200ms)` 沒 curve（linear 旋轉）→ 補 `curve: AppMotion.easeOut`。`ebook_entry_list.dart:230` AnimatedSize 維持現狀（implicit 動畫無法非對稱，不強做）。

**E. 死動畫**：`report_subject_selector.dart:93` `AnimatedContainer` 的 width/height 恆為 7（永不變）→ 換普通 `Container`。

## Target

以上全數落地後：`grep -rhoP "milliseconds: (150|180|200|240|320)\)" lib/ --include="*.dart"` 中屬於動畫 duration 的裸數字趨近 0（Timer/delay 的 Duration 不在範圍）。

## Repo conventions to follow

- 每處替換前確認該 Duration 是動畫（AnimatedX/AnimationController/animateTo）不是 Timer/Future.delayed——**只換動畫**。
- import `app_motion.dart` 按各檔相對路徑。

## Steps

1. A 類（機械）→ 一個 commit。
2. B＋D＋E → 一個 commit。
3. C → 一個 commit（曲線變了，feel check 級）。

## Boundaries

- Timer、Future.delayed、debounce 的 Duration 一律不碰。
- 已 settled 的檔（`liquid_motion_frame`、`one_shot_*`、`swipe_hint_nudge`、`gradient_background` ambient 值）不碰。
- 測試若斷言特定 duration，同步更新。

## Verification

- **Mechanical**: `flutter analyze`; `flutter test` 全綠。
- **Feel check**：抽查 chip 選取（多了 easeOut 不再 linear）、書架 chevron 旋轉變順、辨識 dialog 進場尾段更俐落。
- **Done when**: 三個 commit 全綠＋grep 檢查達標。
