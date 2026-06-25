# Practice-Chat 照片＋Profile 首屏體驗 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把 60 張 AI 生成女孩照片接進 Flutter，讓「AI 實戰練習室」首屏以大 profile card 為第一視覺、聊天中保留 compact identity header，且照片/身份嚴格跟著 `profileId` 狀態機走。

**Architecture:** MVP 用 **bundled local JPEG assets**（不走 Supabase Storage）。一支 `dart run` 轉檔腳本（用既有 `image` 套件）把來源 PNG resize+JPEG 編碼成 `assets/images/practice_girls/practice_girl_NNN.jpg`。Client catalog 既有 `photoId` → 推導 asset path。UI 分兩態：opening（大卡）／chat（compact header），可選 bottom sheet。狀態機（換一位／切難度／續玩／restore／recent）已由 `profileId` 驅動，本輪以測試鎖死行為，僅在必要時改 controller。

**Tech Stack:** Flutter / Riverpod、Dart `image: ^4.1.7`（JPEG 編碼）、Hive、Deno（catalog 漂移守門）。

**決策（已定，無需再問）：**
- 格式 **JPEG**（WebP 在本機無編碼器；Dart `image` 套件 WebP 僅 decode）。Eric 日後要更小可在 Windows 用 `cwebp` 重壓，asset 檔名不變即可平滑替換。
- 來源路徑**只**經 CLI arg 傳入，**不**寫進任何 committed code。
- 照片尺寸 max-dimension 1080、JPEG quality 82；轉完回報實際總大小，過大再降。
- 顯示欄位**只**用 server+prompt 已知欄位，**不**新增 client-only 身高/星座/學歷以外的東西（身高/星座 catalog 已有且 server 知，可選顯示）。

**不要碰：** Edge quota gate、ledger/RPC/migration、64KB body cap、不 push、不宣稱 dogfood-safe（等 UI 完成＋Codex review＋Eric 點頭）。

---

## Task 0：照片轉檔 pipeline（PNG → resized JPEG assets）

**Files:**
- Create: `tools/gen-practice-photos/convert_practice_photos.dart`
- Create (artifact): `assets/images/practice_girls/practice_girl_001.jpg … practice_girl_060.jpg`

**Step 1:** 寫 `convert_practice_photos.dart`：CLI `--src <dir> --out <dir> [--max 1080] [--quality 82]`。用 `package:image`：對 `practice_girl_001.png…060.png` 逐張 `decodeImage` → `copyResize`（長邊 ≤ max，維持比例）→ `encodeJpg(quality)` → 寫 `--out/practice_girl_NNN.jpg`。結尾印出：處理張數、缺漏清單、每張與總大小、最大單張。缺一張即 `exitCode=1`。**不得**內嵌任何 `.codex` 路徑。

**Step 2:** 執行
`dart run tools/gen-practice-photos/convert_practice_photos.dart --src "<.codex upload_ready>" --out assets/images/practice_girls`
Expected：`converted 60/60`，總大小單位數 MB，無缺漏。

**Step 3:** 驗證 `ls assets/images/practice_girls/*.jpg | wc -l` == 60；總大小 `du -sh`。若 > ~12MB 降 max/quality 重跑。

**Step 4:** Commit（assets＋script 同一 concern）。

---

## Task 1：pubspec 註冊 ＋ photoId→asset 解析 ＋ asset 存在守門測試

**Files:**
- Modify: `pubspec.yaml`（assets 區）
- Modify: `lib/features/practice_chat/domain/entities/practice_girl_profile.dart`（加 `String get photoAssetPath`）
- Test: `test/unit/features/practice_chat/domain/entities/practice_girl_photo_asset_test.dart`

**Step 1（失敗測試）:** 新測試：
(a) 對 `practiceGirlProfiles` 每位，`profile.photoAssetPath == 'assets/images/practice_girls/${photoId}.jpg'`；
(b) `File(profile.photoAssetPath).existsSync()` 為真（flutter test 由 package root 執行）——確保 60 張 asset 全部都在。

**Step 2:** Run `flutter test .../practice_girl_photo_asset_test.dart` → FAIL（getter 未定義）。

**Step 3:** 在 `PracticeGirlProfile` 加 `String get photoAssetPath => 'assets/images/practice_girls/$photoId.jpg';`；`pubspec.yaml` assets 加 `- assets/images/practice_girls/`。

**Step 4:** Run 測試 → PASS。

**Step 5:** Commit。

---

## Task 2：可重用 `PracticeGirlPhoto` widget（Image.asset ＋ fallback）

**Files:**
- Create: `lib/features/practice_chat/presentation/widgets/practice_girl_photo.dart`
- Test: `test/widget/features/practice_chat/practice_girl_photo_test.dart`

**Step 1（失敗測試）:** widget test：
(a) 給合法 `profile`、`shape=circle/rounded`，render 出 `Image`（`find.byType(Image)`），key 穩定 `ValueKey('practice-girl-photo-${photoId}')`；
(b) `errorBuilder` 觸發時 render fallback（沿用現有 hash 底色＋首字母，抽自 `_PracticeAvatar`），不 crash。

**Step 2:** Run → FAIL（widget 不存在）。

**Step 3:** 實作 `PracticeGirlPhoto`：`Image.asset(profile.photoAssetPath, fit: BoxFit.cover, errorBuilder: → _PhotoFallback(profile))`，支援 `double size` / `BoxShape or borderRadius` / circle/rounded 兩型。`_PhotoFallback` 沿用 `practice_chat_screen.dart` 現有 `_PracticeAvatar` 的 HSL 底色＋首字母邏輯（抽共用，避免兩份）。

**Step 4:** Run → PASS。

**Step 5:** Commit。

---

## Task 3：Opening 大 profile card（取代/包住 `_EmptyState`）

**Files:**
- Modify: `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart`（`_EmptyState` 約 420–467；`_PracticeProfileBar` 約 187–248）
- Test: `test/widget/features/practice_chat/practice_chat_screen_style_test.dart`（加 cases）

**Step 1（失敗測試）:** empty/opening 態（`messages` 空）斷言看得到：大照片（`PracticeGirlPhoto`，4:5 近似 dating card）、`displayName`、`age`、`professionLabel`、`city`、2–4 個 tag（persona/difficulty/interest/lifestyle 擇要）、`selfIntro` 一行、保留「換一位」與難度 chips。**不得**出現 Verified／真人帳號字樣。

**Step 2:** Run → FAIL。

**Step 3:** 把 `_EmptyState` 改成 `_PracticeProfileHero`：上方大照片（`AspectRatio 4/5` + rounded + `PracticeGirlPhoto`），照片下方/overlay 顯示 name·age、professionLabel·city、tag chips、selfIntro，底部保留 換一位＋難度 chips（沿用 `_DifficultyChips`）。維持「AI 陪練」語意文案。

**Step 4:** Run → PASS。

**Step 5:** Commit。

---

## Task 4：Chat 態 compact identity header

**Files:**
- Modify: `practice_chat_screen.dart`（`_PracticeProfileBar` 187–248、`_PracticeAvatar` 253–279）
- Test: `practice_chat_screen_style_test.dart`

**Step 1（失敗測試）:** chat 態（`messages` 非空）斷言：compact header＝小圓照片（`PracticeGirlPhoto` circle）＋ `displayName · professionLabel`，第二行 `age · city · difficultyLabel`；輸入區／剩餘則數／結束練習 CTA 仍可見不被擠壓。

**Step 2:** Run → FAIL。

**Step 3:** `_PracticeProfileBar` 在有訊息時切 compact：`_PracticeAvatar` 換成 `PracticeGirlPhoto`(circle, 38)＋兩行文字；header 包 `InkWell` → 開 profile sheet（Task 6；Task 6 未做前先 no-op 或不包）。

**Step 4:** Run → PASS。

**Step 5:** Commit。

---

## Task 5：狀態機行為鎖死（controller tests，必要時才改 code）

**Files:**
- Test: `test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart`
- （僅在測試揭露 bug 時）Modify: `practice_chat_providers.dart`

**Step 1（測試）:** 新增/補強：
- 換一位（`startNewPartner`/`regeneratePersona`）→ `girl.photoId`/`profileId` 改變；
- 切難度（`setDifficultyPreference`）→ `photoId`/`profileId` **不變**；
- 續玩（`continueWithSamePartner`）→ `photoId`/`profileId` 不變、transcript 保留、新 sessionId、roundIndex+1；
- restore（`resumeSession`）→ 依 `profileId` 還原正確照片；`profileId==null` → fallback 不 crash。

**Step 2:** Run → 應大多 PASS（行為已由 `profileId` 驅動）；任何 FAIL 視為真 bug，最小修。

**Step 3:** 綠。Commit（測試 ＋ 任何修補各自 concern）。

---

## Task 6（scope 允許才做）：Profile bottom sheet

**Files:**
- Create: `lib/features/practice_chat/presentation/widgets/practice_profile_sheet.dart`
- Modify: `practice_chat_screen.dart`（compact header onTap）
- Test: `practice_chat_screen_style_test.dart`

**Step 1（失敗測試）:** 點 compact header → bottom sheet 顯示大照片、`displayName/age/city/professionLabel`、interest tags、`selfIntro`。**只**含 server catalog 已知欄位。

**Step 2–4:** 紅→實作 `showModalBottomSheet` 內容→綠。Commit。

---

## Task 7：驗證 ＋ 回報（不 push）

**Step 1:** `deno test --allow-read tools/gen-practice-catalog/catalog_sync_test.ts` → PASS（catalog 仍對齊 server）。
**Step 2:** `flutter test test/unit/features/practice_chat test/widget/features/practice_chat` → 全綠。
**Step 3:** `flutter analyze lib` → 0 issue（至少不新增）。
**Step 4:** 回報：commits 列表（一顆一 concern）、asset 數量與最終 repo path、UI 行為描述、測試結果、任何 profile/photo 對不上或 fallback 情形。**不 push**，等 Codex review＋Eric 點頭。

---

## 完成定義（DoD）
- 60 張 JPEG 在 `assets/images/practice_girls/`，每張 ≤ 合理大小、總計單位數 MB。
- catalog 每位 `photoAssetPath` 都有對應實體檔（測試守門）。
- opening 大卡＋chat compact header 皆顯示真照片；missing asset 有 fallback 不 crash。
- 狀態機四條（換一位/切難度/續玩/restore）由測試鎖死。
- deno + flutter test + analyze 全綠。未 push。
