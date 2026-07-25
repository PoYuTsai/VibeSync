# 證偽報告：VibeSync 學習專區四本互動式電子書

---

## Claim 1 — 免費使用者在任何路徑都無法看到 Books 2–4 內容

**判定：沒找到反例（已排除可見路徑）**

我檢查了所有三條進入路徑：

| 路徑 | 閘門機制 | 結論 |
|---|---|---|
| 書架點擊 | `EbookShelfCard.onTap` → locked 時直接 `context.push('/paywall')`；未 locked 才進 detail | Books 2–4 不開 |
| 書籍目錄 `/learning/books/:bookId` | `EbookDetailScreen` → `EbookAccessGate(book: catalog.findBook(bookId))` | Books 2–4 被 gate 擋 |
| 章節 deep link `/learning/books/:bookId/chapters/:chapterId` | `EbookReaderScreen` → `EbookAccessGate` | Books 2–4 被 gate 擋 |

`EbookAccessGate.build()` 中 `allowed` 分支是唯一建立 child 的地方；`catalog._validateCatalog` 在載入時強制 `index == 0 → free, 其餘 → premium`，若 JSON 被竄改為 Book 2 free，會直接拋 `EbookContentException`。

唯一注意的是資產本身隨 bundle 發布，產品不變量已聲明這不是 server-side DRM，屬於已接受範圍。

---

## Claim 2 — 訂閱確認中／無法確認時，內容不閃現且不被誤導向 paywall

### ◆ 重要發現 (P2)：書架卡在 resolving／unavailable 時直接導向 paywall

**找到反例。**

`ebook_shelf_section.dart` 對每張書卡傳入：

```dart
locked: ebookLockedFor(book, access),
```

而 `ebookLockedFor` 定義為：

```dart
bool ebookLockedFor(Ebook book, EbookSubscriptionAccess subscription) =>
    ebookAccessFor(book, subscription) != EbookAccessDecision.allowed;
```

當 `subscription.isResolving == true` 時，`ebookAccessFor` 回傳 `resolving`，而 `resolving != allowed` 為 `true` → `locked = true`。

接著 `EbookShelfCard.onTap`：

```dart
onTap: () {
  if (locked) {
    context.push('/paywall');  // ← resolving 時也走這條
    return;
  }
  context.push(ebookDetailRoute(book.id));
},
```

同時 `_AccessPill` 在 `locked == true` 時顯示「訂閱解鎖」pill，包括 `isResolving` 與 `hasError` 狀態。

**具體重現步驟：**
1. 設 `SubscriptionState(isLoading: true)`（或 `error: 'network'`）。
2. 書架上的 Books 2–4 顯示「訂閱解鎖」pill。
3. 點擊 → 直接跳 `/paywall`。
4. 期望：不導 paywall（狀態未確認）。實際：導了 paywall。

**影響範圍：** 僅書架卡。`EbookDetailScreen` 與 `EbookReaderScreen` 正確使用 `EbookAccessGate`，在三種狀態分別顯示 loading／error message／redirect，沒有閃現。

**驗證方式：** 在 `ebook_access_gate_test.dart` 裡加入 shelf card 層級的測試，模擬 `EbookSubscriptionAccess.resolving()` 時點擊 Books 2–4 卡片，觀察是否 `context.push('/paywall')` 被呼叫。預期不應被呼叫。

---

## Claim 3 — 閱讀電子書不影響短篇文章每日三篇額度

**判定：沒找到反例（已排除）**

| 維度 | Article（既有） | Ebook（新增） |
|---|---|---|
| Box | `StorageService.usageBox` | `StorageService.settingsBox` |
| Key | `article_daily_read_count` 等 | `learning_progress_v1:<ownerUserId>` |
| Service | `ArticleReadService` | `EbookProgressRepository` |

- `ebook_providers.dart` 完全沒有 import `ArticleReadService`。
- `EbookProgressRepository` 只寫 `settingsBox`，key prefix `learning_progress_v1:`。
- `ArticleReadService` 只讀寫 `usageBox`，key prefix `article_`。
- `learning_screen.dart` 的額度提示文案加上「（電子書不計入）」，但功能邏輯沒改。

兩者的 key space 和 box 完全不重疊，不可能互相影響。

---

## Claim 4 — 帳號 A 與帳號 B 的本機進度不可能互相讀到

### ◆ 輕微發現 (P3)：非登出路徑的 session 切換可能有極短暫的進度殘影

**正常登出流程：安全。** `settings_screen.dart` 在登出時呼叫：
```dart
ref.invalidate(ebookProgressControllerProvider);
```
invalidate 後 state 進入 `AsyncLoading`（無 previousValue），`ebookBookProgressProvider` 取 `snapshot.value` 得 `null` → 回 `EbookBookProgress.empty`。然後 `build()` 重新執行，owner 為空 → 回 empty snapshot。帳號 B 登入後以 B 的 id 為 key 載入。無交叉。

### 不確定發現：非登出 session 切換

若 Supabase session 因 token 過期、多裝置登出等原因直接切換（不經過 settings screen 的 logout handler），`ebookProgressOwnerProvider` stream 會 emit 新 owner id，`EbookProgressController.build()` 重新執行。在 Riverpod 的 AsyncNotifier rebuild 期間，`AsyncLoading` 可能保留前一個 snapshot 作為 `previousValue`。

`ebookBookProgressProvider` 中：
```dart
final snapshot = ref.watch(ebookProgressControllerProvider);
return snapshot.value?.bookProgress(bookId) ?? EbookBookProgress.empty;
```

若 `AsyncLoading.value` 回傳 previousValue（A 的進度），則 `ebookBookProgressProvider` 會短暫回傳 A 的完成度，直到新的 `build()` 完成。

**嚴重度：P3** — 視窗極短（Hive 讀取通常 <1ms）、需要非典型 session 切換路徑、且只顯示完成百分比（不洩漏內容）。

**驗證方式：** 在 Riverpod mock 環境中，先讓 controller 載入 A 的進度，再直接改變 `ebookProgressOwnerProvider` 的 stream emit 值為 B 的 id（不經過 invalidate），觀察 rebuild 過程中 `ebookBookProgressProvider` 是否短暫回傳非空且屬於 A 的進度。

**key 隔離本身是正確的：** `storageKeyFor(ownerUserId)` 產生 `learning_progress_v1:<id>`，A 和 B 的 key 不同，Hive 層面不可能讀到對方資料。問題僅在 Riverpod state 層面的極短暫殘影。

---

## Claim 5 — revision / contentVersion 改變後舊作答不會被誤判有效

**判定：沒找到反例（quiz revision 部分）；contentVersion 部分證據充足**

### Quiz revision

```dart
EbookQuizState? quizStateFor(String quizId, int quizRevision) {
  final state = quizStates[quizId];
  if (state == null) return null;
  if (state.quizRevision != quizRevision) return null;  // ← revision 不符即失效
  return state;
}
```

`EbookQuizCard._restoreFromSavedState()` 收到的 `savedState` 已經由呼叫端以 `quizStateFor(block.id, block.revision)` 過濾。revision 改了 → 回 null → quiz 從未作答狀態開始。✓

`EbookQuizState.fromJson` 也驗證 `revision is! int || revision < 1 → return null`。✓

### contentVersion

`contentVersionSeen` 僅用於 `markChapterCompleted` / `setLastChapter` 的冪等優化，不用於 invalidation。但「作答」指的是 quiz answers，由 quizRevision 保護。章節完成不算「作答」，且產品不變量未要求 contentVersion 變化時清除章節完成狀態。

### 不確定：`isSolvedBy` 實作未提供

`ebook_quiz_card.dart` 呼叫 `widget.quiz.isSolvedBy(_selected)`，但 `ebook_block.dart` 的完整實作未在 packet 中展示。無法獨立驗證單選／複選的正確性判定邏輯。若 `isSolvedBy` 對複選題使用「子集即正確」而非「完全匹配」，則使用者可能被誤判為 solved，但這不直接違反 claim 5（claim 5 是關於舊答案在新 revision 下的有效性，不是 solved 判定邏輯本身）。

---

## Claim 6 — 內容 JSON 有任何不合法之處就整份拒絕載入

**判定：沒找到反例（已排除）**

逐一檢查聲稱中列出的四種不合法情況：

| 不合法情況 | 檢查位置 | 行為 |
|---|---|---|
| 未知 block type | `_parseBlock` default 分支 | `throw EbookContentException` ✓ |
| 缺必填欄位 | `_requireString` / `_requireInt` / `_requireList` 等 | 全部 throw ✓ |
| 單選題正解數錯 | `_parseQuiz` single mode `correctCount != 1` | throw ✓ |
| id 重複 | `_validateCatalog`（book/chapter/global block）+ `_parseChapter`（local block）+ `_parseQuiz`（choice）+ `_parseComparisonItems` + `_parseDialogueLines` + `_parseChecklistItems` | 全部 throw ✓ |

所有 throw 都在 `parseBookJson` 或 `load()` 中，`ebookCatalogProvider` 是 `FutureProvider`，throw → `AsyncError` → UI 顯示 `_ShelfError()` / `_DetailContentError`，不會靜默跳過。

額外驗證：
- 未知 enum 值（`tone`、`speaker`、`signal`、`mode`、`stance`、`access`、`theme`、`retryPolicy`）全部 fail closed。
- `schemaVersion != 1` → throw。
- 空陣列（`chapters`、`blocks`、`choices`、`items`、`lines`、`sourceRefs`、`sections`）→ throw。
- 複選題全選項為正解 → throw。
- 複選題無正解 → throw。
- choices 少於 2 個 → throw。

---

## Claim 7 — 三燈與 Quiz 正誤在灰階／色盲下仍可判讀

### 已驗證可見部分：正確

**三燈 `EbookSignalChip`：**

| 燈號 | 圖示 | 文字 | 顏色 |
|---|---|---|---|
| 綠燈 | `trending_up_rounded` | 「綠燈 · 可以推進」 | green |
| 黃燈 | `pause_circle_outline_rounded` | 「黃燈 · 維持或換軌」 | yellow |
| 紅燈 | `do_not_disturb_on_outlined` | 「紅燈 · 退回或停止」 | red |

三組圖示各不相同，文字 label 各不相同，灰階下可區分。✓

**Quiz `_ChoiceRow`（revealed）：**
- 正確：`check_circle_outline` + 文字「正確」
- 不正確：`highlight_off` + 文字「不是這個」
圖示＋文字都在。✓

**Quiz `_ResultPanel`：**
- 答對：`check_circle_outline` + 文字「答對了」
- 再想想：`refresh_outlined` + 文字「再想想」
✓

**死亡點：**
- `heart_broken_outlined` + 文字「死亡點」✓

**Comparison stance：**
- weak：`thumb_down_off_alt_outlined`
- strong：`thumb_up_off_alt_outlined`
- neutral：`drag_indicator`
圖示不同，但無 stance 文字 label（label 是內容標籤如「流行說法」）。灰階下仍可靠圖示區分。✓

**章節完成狀態：**
- `check_circle_outline` + 文字「已完成」
- `radio_button_unchecked` + 文字「未完成」✓

### 不確定部分

`ebook_flip_card.dart` 與 `ebook_checklist_block.dart` 的完整實作未在 packet 中展示。無法驗證 flip card 的正反面切換與 checklist 的勾選狀態是否在灰階下可判讀。

**驗證方式：** 檢查 `EbookFlipCard` 是否依賴顏色來區分正反面；檢查 `EbookChecklistBlockView` 的勾選狀態是否同時使用圖示與文字。

---

## Claim 8 — 教材沒有把反效果技巧重新包裝為正向技巧

**判定：沒找到反例（基於提供樣本）**

Book 3 第 3.5 章的六項反效果技巧，每一項的結構都是：

```
comparison block
├── stance: "weak"  →「流行說法」+ 為什麼是壞的（技術理由）
└── stance: "strong" →「替代方案」/「正確用法」+ 理由
```

逐項確認：

| 技巧 | 被包裝為正向？ | 證據 |
|---|---|---|
| 延遲操作 | 否 | stance=weak，note 說明「直接降低走到見面的機率」 |
| Negging | 否 | stance=weak，note 說明「識別的成本是立即封鎖。期望值是負的」 |
| 間歇性否定 | 否 | stance=weak，note 說明「追求期順利、穩定後崩潰。那不是執行失誤，是設計後果」 |
| 假篩選 | 否 | stance=weak，note 說明「一旦它是表演…就只是一個可被識破的技巧」 |
| 預先消除退出理由 | 否 | stance=weak，note 說明「不改變她的意願，只提高她表達意願的成本」 |
| 升級棘輪 | 否 | stance=weak，note 說明「持續施壓直到突破…產生事後的關係崩壞與名聲風險」 |

結尾安全 callout 明確指出：「任何讓對方更難說不的設計，長期都在傷害你自己的結果。明確的拒絕要立刻停止；模糊的回應不算同意。」

Quiz 1 的正解（A）也確認：「問題不是它無效，是它產生的不是你要的東西」。

**限制：** 我只看到了 Book 3 第 3.5 章與 Book 4 第 4.4 章的安全 callout 樣本。其他章節的完整 JSON（Books 1–4 其餘 19 章）未在 packet 中展示，無法逐一驗證。claim 的完整成立需要審閱全部二十章。

---

## Claim 9 — 既有 24 篇文章、numeric id、Coach 深連不受影響

**判定：沒找到反例（基於可見程式碼）**

檢查了以下層面：

1. **路由：** 新增兩條獨立路由 `/learning/books/:bookId` 和 `/learning/books/:bookId/chapters/:chapterId`。既有 article 路由 `/learning/articles/:id` 未修改。電子書用 string id（如 `ebook-1-bottleneck`），文章用 numeric id，兩者的 id space 和 path namespace 完全不重疊。

2. **文章資料：** `articles_data.dart` 和 `learning_providers.dart` 未出現在變更範圍中。

3. **文章額度：** `ArticleReadService` 未出現在變更範圍中。`learning_screen.dart` 的文章區塊邏輯未改，只改了 header 文案（「練習專區」→「短篇實戰文章」）和加了一句「（電子書不計入）」。

4. **文章 UI：** 文章列表和詳情頁的 import 和 widget 樹沒被修改。

5. **Coach 深連：** 證據不足。Coach 相關程式碼未在 packet 中展示，無法確認 Coach 的「看教學」深連是否指向 article routes 或其他 routes。但從 routes.dart diff 來看，沒有修改任何既有 route 定義，只新增了兩條。

**驗證方式：** 比對 `git diff` 確認 `articles_data.dart`、`article_detail_screen.dart`、`article_read_service.dart` 無變更。搜索 Coach 相關檔案中是否有硬編碼的 route path 被改動。

---

## 額外觀察（不直接對應 9 條 claim）

### ◆ 輕微 (P3)：EbookAccessGate locked 後使用者回到 loading 死角

`EbookAccessGate` 在 `locked` 狀態下用 `_redirected` flag 防止重複導航，並回傳：
```dart
return const _EbookGateLoading(label: '這本需要訂閱才能閱讀');
```
使用者在 paywall 不訂閱返回後，`_redirected` 已是 `true`，不再觸發 redirect。使用者看到一個永遠不會結束的 loading 畫面，只能靠 back 鍵離開。不是安全問題，但 UX 不理想。

---

## 總結

| Claim | 判定 | 最高嚴重度 |
|---|---|---|
| 1. 免費使用者無法看到 Books 2–4 | 沒找到反例 | — |
| 2. 確認中不閃現／不誤導 paywall | **找到反例**（書架卡） | **P2** |
| 3. 電子書不影響文章額度 | 沒找到反例 | — |
| 4. 帳號隔離 | 輕微發現（非登出切換） | P3 |
| 5. revision 改變舊答案失效 | 沒找到反例 | — |
| 6. 不合法 JSON 整份拒絕 | 沒找到反例 | — |
| 7. 灰階／色盲可判讀 | 大部分已驗證；flip card / checklist 未驗證 | 不確定 |
| 8. 不包裝反效果技巧為正向 | 沒找到反例（僅樣本） | — |
| 9. 既有文章／Coach 不受影響 | 沒找到反例（Coach 證據不足） | — |

**需要優先處理的唯一重要發現：** Claim 2 的書架卡在 `isResolving` / `hasError` 時不應直接跳 paywall。建議讓 `EbookShelfCard` 區分 `locked`（確認免費）與 `indeterminate`（resolving / error），或在 `EbookShelfSection` 層過濾掉 resolving/error 時的 onTap 行為。
