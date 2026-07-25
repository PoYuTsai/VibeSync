# 給 CC：學習專區四本互動式電子書 — 詳細開工說明

> 這份文件可以整份交給 Claude Code（CC）。
> 完整施工規格：`docs/plans/2026-07-25-interactive-ebooks-implementation-plan.md`
> 本文件是執行摘要，不能取代完整規格；若兩者有落差，以完整規格的「已鎖定產品方向」「不變量」「Definition of Done」為準。

---

## 任務

請在 VibeSync 的學習專區實作四本互動式電子書：

1. Book 1《先找到真正卡點》— Free。
2. Book 2《看懂一段對話》— Starter／Essential。
3. Book 3《對話急救室：該救，還是該停》— Starter／Essential。
4. Book 4《從聊天走到見面》— Starter／Essential。

完成：

- bundled JSON content catalog。
- typed block models／parser。
- 書架。
- 書籍目錄。
- 章節閱讀器。
- 對話泡泡。
- 翻卡。
- 單選／複選 Quiz。
- checklist。
- account-scoped Hive 進度。
- stable route／resume。
- subscription access guard。
- tests。
- 繁中、逐 concern commits。
- Codex＋GLM read-only review packet 與 reconciliation。

這份任務不包含 push、deploy、production mutation 或 TestFlight；沒有 Eric 另行明確授權就停在本機已驗證、已 commit 狀態。

---

## 0. 開工前

### 0.1 先讀

1. 完整讀：
   - `AGENTS.md`
   - `docs/plans/2026-07-25-interactive-ebooks-implementation-plan.md`
   - 本文件
2. 完整讀兩份來源：
   - Windows：
     - `C:\Users\eric1\OneDrive\Desktop\Vibesync重要文件\交友軟體實戰手冊.md`
     - `C:\Users\eric1\OneDrive\Desktop\Vibesync重要文件\交友軟體實戰五階段課程.md`
   - WSL：
     - `/mnt/c/Users/eric1/OneDrive/Desktop/Vibesync重要文件/交友軟體實戰手冊.md`
     - `/mnt/c/Users/eric1/OneDrive/Desktop/Vibesync重要文件/交友軟體實戰五階段課程.md`
3. 只讀相關現況：
   - `lib/features/learning/`
   - `lib/app/routes.dart`
   - `lib/features/subscription/data/providers/subscription_providers.dart`
   - `lib/core/services/storage_service.dart`
   - `lib/features/subscription/presentation/screens/settings_screen.dart`
   - `lib/features/analysis/domain/coach/learning_link_resolver.dart`
4. 這是 R2 並觸及 paywall／帳號隔離：
   - 先跑 `adaptive-workflow-router`。
   - 若可建立 task graph，使用 `graph-control-plane`。
   - 若 repo 已有無關 active graph，不得 `--force` 覆蓋；記錄現況並回報。

### 0.2 Worktree

```powershell
git status --short --branch
git log --oneline -15
```

- 記錄 `BASE_SHA`。
- 既有變更一律視為 Eric／其他工作的內容。
- 不 reset、不 checkout 丟棄、不順手格式化、不混入 commit。
- 若需要 branch 且 Eric 沒指定，使用本機 branch：

```text
claude/interactive-learning-ebooks
```

- Branch 建立不代表允許 push。

### 0.3 Baseline

先跑：

```powershell
flutter test test/unit/features/learning `
  test/unit/app/main_shell_test.dart `
  test/unit/features/analysis/domain/coach/learning_link_resolver_test.dart
```

2026-07-25 的參考 baseline 是 22／22 PASS；你的實際開工結果才是本輪證據。

---

## 1. 不要重新設計的產品決策

- 兩份新版教材是 canonical source。
- 使用五標記：V／F／E／I／R。
- 三燈：綠推進、黃維持／換軌、紅退回／停止。
- 四本書約二十章。
- Book 1 Free。
- Books 2–4 Starter／Essential。
- 不做前一本完成才解鎖下一本。
- 電子書不消耗每日三篇文章額度。
- 內容用 bundled JSON，不再把數萬字塞進 Dart const。
- JSON 解析後必須是 typed sealed blocks。
- Quiz 支援 single／multiple。
- 預設答錯可 retry；不要把首答永久鎖定寫死。
- 進度存在加密 `StorageService.settingsBox`。
- Storage key 必須 account scoped。
- Resume 存 chapter id，不存 index。
- Quiz 存 choice string ids 與 revision。
- 不保存真實聊天或自由文字反思。
- 現有 24 篇 article ids 與 Coach learning links 不動。
- Practice Hero 保留。
- 電子書區在文章區之前。
- 文章每日額度提示只放在文章區。
- 不新增封面圖片。
- 不改 RevenueCat、tier、quota、Supabase 或 Edge Function。

內容硬規則：

- 舊四變數分析不能覆蓋新版五標記。
- 「十二個案例」改成十四個。
- 「照片五個位置」改成六個功能位。
- 不把忽冷忽熱、Negging、間歇性強化、假篩選、壓縮退出空間、升級棘輪包裝成正向技巧。
- 敘述以「對方」為主。
- 涉及邀約必須清楚保留拒絕權。
- Book 4 補公開場所、自主交通、告知朋友、個資、詐騙與同意提醒。

---

## 2. 施工順序

不要先一次寫完二十章。先做 infrastructure＋一章垂直切片，確認架構後才批量匯入內容。

### Step 1 — Models／JSON parser／catalog

新增：

```text
lib/features/learning/domain/models/ebook.dart
lib/features/learning/domain/models/ebook_block.dart
lib/features/learning/domain/models/ebook_progress.dart
lib/features/learning/data/repositories/ebook_catalog_repository.dart
lib/features/learning/data/providers/ebook_providers.dart
assets/learning/ebooks/
```

完成：

- `Ebook`。
- `EbookChapter`。
- sealed `EbookBlock`。
- paragraph／heading／bulletList／callout／comparison／dialogue／flipCard／quiz／checklist。
- single／multiple quiz。
- choice string id、feedback、correctness。
- quiz revision／retryPolicy。
- injectable `AssetBundle` parser。
- unknown type fail closed。
- catalog 恰四本。
- Book 1 access free，其餘 premium。

先用 Book 1 Chapter 1 最小 fixture；不要在 UI 尚未打通前先寫完整內容。

### Step 2 — Progress repository／controller

使用：

```text
StorageService.settingsBox
key = learning_progress_v1:<ownerUserId>
```

完成：

- `schemaVersion`。
- `contentVersionSeen`。
- `lastChapterId`。
- `completedChapterIds`。
- `quizStates`。
- `checklistStates`。
- async／await writes。
- rapid write ordering。
- corrupt JSON fallback。
- account A／B isolation。
- logout provider invalidation。

禁止：

- `ArticleReadService`。
- 未分帳號 key。
- index-based resume。
- email key。
- Hive adapter／typeId。
- 保存真實聊天。

### Step 3 — Interaction widgets

新增：

```text
ebook_block_renderer.dart
ebook_dialogue_block.dart
ebook_flip_card.dart
ebook_quiz_card.dart
ebook_checklist_block.dart
```

完成：

- exhaustive renderer。
- display-only dialogue bubbles。
- flip front/back。
- reduced-motion fallback。
- Semantics。
- single／multi quiz。
- per-choice feedback。
- retry／restore。
- checklist。
- text scale 2.0 無 overflow。

### Step 4 — Detail／reader／routes

新增：

```text
/learning/books/:bookId
/learning/books/:bookId/chapters/:chapterId
```

完成：

- `EbookDetailScreen`。
- `EbookReaderScreen`。
- PageView 一頁一章。
- 每章內垂直捲動。
- 位置進度與完成度分開標示。
- 完成本章後 await persistence，再翻頁。
- direct deep link。
- unknown book／chapter fallback。
- back stack fallback。

### Step 5 — Access guard

建立：

```text
ebookLockedFor(book, subscription)
EbookAccessGate
```

要求：

- Book 1 不鎖。
- Free 進 Books 2–4 → `/paywall`。
- Starter／Essential 可讀。
- subscription loading 只顯示 loading。
- subscription error 顯示 retry error，不洩漏內容、不假裝 quota。
- Premium child 在 gate 完成前完全不 build。
- Shelf、Detail、Reader、direct link 都守門。
- 電子書路徑不呼叫 `ArticleReadService`。

### Step 6 — Learning 首頁

保留 Practice Hero。

重整：

```text
AI 實戰練習室
互動電子書
短篇實戰文章＋每日剩餘篇數
24 篇文章 grid
```

書架卡顯示：

- icon／書號。
- title／subtitle。
- chapters／time。
- progress。
- 免費／訂閱解鎖。

不得改現有 article ids 或 Coach resolver。

### Step 7 — Vertical slice 驗證

只用 Book 1 Chapter 1 先驗證：

```text
書架
→ 目錄
→ 閱讀器
→ 翻卡
→ Quiz
→ 完成
→ 返回
→ 進度更新
→ 重啟續讀
```

同時驗：

- Free。
- Premium。
- deep link。
- unknown id。
- account switch。
- article quota 不變。

架構與 UX 沒通過前，不要大量寫內容。

### Step 8 — 匯入四本內容

依序、一本一 commit：

1. Book 1《先找到真正卡點》。
2. Book 2《看懂一段對話》。
3. Book 3《對話急救室：該救，還是該停》。
4. Book 4《從聊天走到見面》。

每本：

- 對照完整計畫的五章 map。
- 保留 source refs。
- 每章至少 flip＋quiz。
- 需要時 safety callout。
- 跑 catalog／invariant tests。
- 人工通讀。
- 不自行補造來源沒有的研究數字。

---

## 3. 測試要求

### Unit

- 四本、二十章。
- 全域 unique IDs。
- Free／premium policy。
- JSON assets 可載入。
- unknown block fail closed。
- 每章 flip＋quiz。
- Quiz single／multiple invariants。
- Account isolation。
- idempotent completion。
- lastChapterId。
- quiz revision invalidation。
- wrong-answer retry。
- corrupt data fallback。
- rapid writes。

### Widget

- 四本書架。
- badges／progress。
- quota 提示位置。
- detail start／continue。
- reader completion／resume。
- flip Semantics／reduced motion。
- quiz single／multi／restore。
- text scale 2.0。
- unknown ID。
- loading／error／Free／Starter／Essential access。
- direct deep link no premium flash。

### Regression

```powershell
flutter test test/unit/features/learning
flutter test test/widget/features/learning
flutter test test/unit/app/main_shell_test.dart
flutter test test/unit/features/analysis/domain/coach/learning_link_resolver_test.dart
flutter analyze
flutter test --concurrency=1
git diff --check
```

Targeted 與 full 結果分開回報。

---

## 4. 建議 commits

1. `新增互動電子書模型與內容目錄`
2. `新增帳號隔離的電子書進度儲存`
3. `新增電子書互動區塊與無障礙測試`
4. `新增電子書目錄閱讀器與穩定路由`
5. `學習頁加入電子書書架與訂閱閘門`
6. `內容新增先找到真正卡點`
7. `內容新增看懂一段對話`
8. `內容新增對話急救室`
9. `內容新增從聊天走到見面`
10. `測試補齊電子書回歸與驗收證據`

每顆 commit 前：

```powershell
git status --short
git diff --cached --name-only
git diff --check
```

- 一 concern 一 commit。
- 繁中 commit。
- 不混入其他功能或使用者變更。
- 未經 Eric 授權不要 push。

---

## 5. 實作中必須停止請 Eric 決定的情況

- 需要改 Book 1 Free／Books 2–4 Premium。
- 需要讓電子書吃文章 quota。
- 需要改 RevenueCat 或 subscription tier。
- 需要儲存真實聊天或自由文字。
- 需要 Supabase／remote CMS。
- 需要移除安全／同意／撤退規則。
- 來源內容與五標記無法調和。
- 需要更動既有 article ids／Coach learning links。
- 需要擴大到 AI、照片上傳、漏斗 tracker、analytics。
- 無法在不洩漏內容的情況下做 paywall guard。
- Worktree 有重疊的未提交變更，無法安全繞開。

一般 symbol、檔名或 widget 組合差異不需停；在不改產品不變量下用最佳判斷調整，並在回報說明。

---

## 6. Review gate

完成本機實作與驗證後：

1. 準備最小 self-contained review packet。
2. Claude primary 直接用 `cross-model-review` 呼叫：
   - Codex read-only opposite-frontier review。
   - GLM read-only falsification。
3. 不送：
   - secrets。
   - `.env`。
   - 真實聊天。
   - 使用者／客戶資料。
   - 無關程式。
4. Review focus：
   - paywall no-flash。
   - account isolation。
   - article quota isolation。
   - content／quiz version migration。
   - accessibility。
   - 反操弄調性。
   - existing learning regression。
5. Primary 回 source／code 驗證並 reconcile；不採多數票。
6. 最多兩輪。

沒有完成 review，不得宣稱 ready to dogfood。

---

## 7. 禁止事項

- 禁止 `git reset --hard`。
- 禁止丟棄或覆蓋既有變更。
- 禁止 `supabase db push`。
- 禁止 deploy。
- 禁止 push。
- 禁止 TestFlight。
- 禁止修改 production。
- 禁止新增 AI request。
- 禁止把付費 JSON 下載到 Free 後只用 opacity 隱藏。
- 禁止將 target tests green 宣稱為 full regression green。
- 禁止只回「完成」而沒有 exact evidence。

---

## 8. 完成時回報格式

```text
狀態：
- IMPLEMENTED / BLOCKED

Branch：
- ...

Range：
- BASE_SHA..HEAD_SHA

Commits：
- <sha> <繁中訊息>

實際 changed files：
- ...

產品規格：
- 四本／二十章：
- Book 1 Free：
- Books 2–4 Premium：
- 非線性閱讀：
- Article quota 隔離：

Persistence：
- Account scoped key：
- Schema version：
- Content／quiz revision：
- Account switch smoke：

測試：
- Baseline：PASS/FAIL
- Catalog/data：PASS/FAIL；命令
- Progress：PASS/FAIL；命令
- Widget：PASS/FAIL；命令
- Route/regression：PASS/FAIL；命令
- Flutter analyze：PASS/FAIL
- Full Flutter：PASS/FAIL/NOT RUN
- git diff --check：PASS/FAIL

手動驗收：
- Free Book 1：
- Locked Book 2 deep link：
- Premium all books：
- Quiz retry/restore：
- Restart resume：
- Account A/B isolation：
- Text scale/reduced motion：

Review：
- Codex：PASS/ISSUES/UNAVAILABLE
- GLM：PASS/ISSUES/UNAVAILABLE
- Reconciliation：<path>

未執行：
- push / deploy / TestFlight / production mutation

Open concerns：
- none / ...
```

不要貼整段原始測試 log；提供命令、結果摘要、exact SHAs、review evidence 路徑與未執行事項。
