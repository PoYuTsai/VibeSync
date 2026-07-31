# 聊天測驗 第 1 期 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: 用 `superpowers:executing-plans` 逐任務執行本計畫。
> 需求真相源：Bruce 的《VibeSync-聊天測驗開發建議報告》（2026-07-31，md 與 pdf 內容相同）。
> 本計畫不得夾帶報告沒有的產品決策。發現報告有誤，先在本檔「§0 對報告的三處更正」記錄再改，不要默默改掉。

**Goal:** 在學習專區新增「聊天測驗」——一個獨立的判讀訓練場。第 1 期只做兩種題型（讀燈、選回覆）、兩個關卡群、四關、約 31 題，其中第 1 群第 1 關 10 題免費，其餘付費。這一期本身就可以出貨。

**Architecture:** 照電子書那一整套的形狀再做一套：JSON 資產 → fail-closed parser → Riverpod provider → 畫面 → 本機進度。能共用的型別直接共用（`EbookAccess`、`EbookSubscriptionAccess`、跳章工具）。**進度用自己的 Hive key，絕不併進電子書的進度檔。**

**Tech Stack:** 純 Flutter/Riverpod client + Hive 加密本機儲存 + JSON 資產。**沒有** Edge Function、**沒有** migration、**沒有**新套件、**沒有**網路請求、**不碰** quota 與計費。

---

## 開工前必讀

**基準**：`main` @ `b85aa555`（成為獎賞三冊內容改寫已上線）。

**風險等級**：R1。整個第 1 期落在 AGENTS.md 高風險區之外（不碰訂閱購買流程、不碰額度、不碰 Edge、不碰 migration）。唯一沾到高風險區的是**付費判斷的讀取端**，用既有的 `EbookSubscriptionAccess` 純函式，不新增權限來源。

**鐵律**（違反任一條就是 blocker）：

1. **絕不動 `EbookProgressSnapshot.currentSchemaVersion`。** 它的語意是「版本號對不上就整包當空」（`ebook_progress.dart:230`）。把測驗進度塞進去再升版號 = 清光所有現有使用者的閱讀進度。測驗進度用 `chat_quiz_progress_v1:<ownerUserId>` 這個獨立 key。
2. **`essential` 權限不得照抄 `isPremium`。** `isPremium == isStarter || isEssential`，照抄會讓 Starter 讀到《成為獎賞》轉化出來的題目。這條在電子書已經有紅字警告與守門測試，測驗要有自己的一份。
3. **一關的權限 ＝ 這一關所有題目來源書當中最高的那一層**（`free < premium < essential`）。由自動化測試守，不是靠人記得。
4. **免費入門關（1-1）的每一題，來源都不得是第 5–7 冊。** 那是唯一的免費出口，單獨守一條測試。
5. **訂閱狀態還在確認（`isResolving`）時，鎖頭不得顯示成付費文案。** 照抄 `ebook_access_gate.dart` 的三態處理。
6. **parser fail closed**：不認識的題型、缺必填欄位、單選題沒有恰好一個正解 → 直接丟 `QuizContentException`，不得靜默跳過。
7. **沒有任何一題的正解是「某個特定字串」。** 正解永遠是一個選擇。這條寫成測試。
8. 動效**不准用 `Timer` 當時間軸**，一律由 `AnimationController` 推導，否則 widget test 不收斂。
9. **絕不 `git add pubspec.lock`**；工作區有並行 session 時 commit 一律顯式列檔。

**每個 Task 結束都要 commit。** 一個 commit 一件事，繁體中文訊息。

---

## §0 對報告的三處更正（已查證，執行時照更正版做）

報告對現有程式碼的主張我逐條查過，**絕大多數屬實**（測驗引擎完整、七本書 quiz 題數為 0、拆解庫 A–N 十四案、前六案標好 `isDeathPoint`、24 篇文章、學習頁順序有測試守、進度 schemaVersion 會整包清空）。以下三處要更正：

**更正 1 — §7.2 缺口表有三條標錯。** 報告說這幾個概念「電子書覆蓋 ❌ 沒有」，實際上第 7 冊《進階聊天 · 讀懂反應再出手》都寫了：

| 報告標記 | 實際位置 |
|---|---|
| 興趣指標三類 ❌ 沒有 | **3.5** 教「行為 > 情緒 > 字面」三層交叉判讀 ＋ 綠/黃/紅三色訊號條目庫 |
| 負面訊號三類 ❌ 沒有 | 降溫型 **3.2**、測試型 **3.3**、終止型 **3.5**（「當她明確說出『不要』……這不是你在判讀的訊號，這是答案」）|
| 換檔的行為判準 ❌ 沒有 | **3.6**「推進不看你們聊了幾天，只看她的反應等級」|

**後果（都往小的方向走）**：
- 第 7.6 節第 9、19、16 條從「❌ 新寫」改為「衍生」。
- §7.3 那筆「再加 2,500–3,500 字」要往下修——第 1 期落在範圍內的第 19 條（拒絕訊號三類）有現成素材，不是白紙。
- §7.2 說這些題「沒有章節可連、深連要留空」**不成立**，1-2 關的題目連得到 3.2/3.3/3.5。

**更正 2 — §2.1 低估了練習室。** 報告寫「開放式練習、沒有標準答案」。實際上練習室已有 `PracticeTemperature`（score/delta/band/reason/stageLabel，逐句評分）與 debrief 拆解卡（做得不錯／可以調整／進度／缺口／卡點／下句／邀約）。

**這不影響要不要做測驗**（Bruce 已指出：那些是教與回饋，測驗是實際練習），但它決定一件事：**測驗的正解語彙必須沿用 debrief 已經在用的詞**，否則使用者會在兩個地方學到兩套說法。寫內容時對照 `practice_debrief_card.dart` 的五行標籤。

**更正 3 — §8 分期表的工時只含工程。** §7 說「程式約 1.5–2 週，內容才是瓶頸」，但 §8 寫第 1 期 4–5 天。兩者不衝突，是**分期表的天數只算工程**。排期時內容要另計，第 1 期約 31 題、依 §7.3 的單價約 3,000–4,000 字。

**§11 的十個待決項，全部採用報告的建議值**（Bruce 2026-07-31 拍板「照做」）：

| # | 決定 |
|---|---|
| 1 | 學習頁位置：練習室 → **聊天測驗** → 電子書 → 文章 |
| 2 | 第一版規模：先 4 關 / 31 題 |
| 3 | 「自己改一句」：延到第三期，單獨授權 |
| 4 | 連續天數：只顯示不推播（第 2 期才做） |
| 5 | 付費關再分層：取材第 5–7 冊的關卡限 Essential |
| 6 | 階段用語：測驗群名跟隨報告頁的短標籤 |
| 7 | 第 1 期關卡地圖：只顯示已有內容的 2 群 |
| 8 | 「接下去」：只放 6 關（第 2 期的事） |
| 9 | 免費關題型：至少含一題「接下去」 |
| 10 | 電子書還沒寫的概念：測驗先教，書之後補 |

> **決定 9 與第 1 期的衝突，以及處理方式。** §11 決定 9 要求免費關含一題「接下去」，但 §8 第 1 期只做「讀燈」與「選回覆」兩種題型。兩者不可能同時成立。
>
> **本計畫的做法：第 1 期的免費關 1-1 不含「接下去」，改為在第 2 期把 1-1 的第 10 題換成「接下去」。** 理由是決定 2（先 4 關驗手感）優先於決定 9，而且「接下去」需要多回合素材，硬塞進第 1 期會拖慢出貨。**這是本計畫唯一一處沒有完全照報告執行的地方，Task 5 完成時要回報給 Bruce 確認。**

---

## 內容 JSON 契約

`assets/learning/quizzes/group_1_signal.json`、`group_2_lifeline.json`

```jsonc
{
  "schemaVersion": 1,
  "id": "quiz-group-1",
  "number": 1,
  "key": "signal",                    // 對映報告頁短標籤
  "title": "讀燈",
  "subtitle": "她現在是什麼狀態",
  "stageLabel": "破冰",               // 決定 6：跟隨報告頁短標籤
  "levels": [
    {
      "id": "quiz-level-1-1",
      "number": "1-1",
      "title": "她現在是哪一種",
      "goal": "把「我該說什麼」換成「她現在是哪一種狀態」。",
      "access": "free",               // 由測試驗證＝所有題目來源的最高層
      "passRatio": 0.8,
      "questions": [ /* 10 題 */ ]
    }
  ]
}
```

題目：

```jsonc
{
  "id": "q-1-1-01",                   // 全域唯一，由測試守
  "type": "signalRead",               // signalRead | pickReply
  "revision": 1,                      // 語意改動要 +1，讓舊答案失效
  "scenario": "她：今天上班快累死",     // 可空
  "question": "這句是什麼燈？",
  "choices": [
    { "id": "q-1-1-01-a", "text": "🟢 綠燈——她在給你一個開口",
      "correct": true,  "feedback": "對。情緒就是開口，而這是整段對話裡最大的一個。" },
    { "id": "q-1-1-01-b", "text": "🟡 黃燈——有回但沒延伸",
      "correct": false, "feedback": "黃燈是「接得住但不加碼」。她主動丟出情緒，那就是加碼。" }
  ],
  "takeaway": "情緒是開口，事實是死路。她給情緒的時候，你永遠往情緒走。",
  "source": {                          // 深連；查不到就整個欄位省略，按鈕不顯示
    "bookId": "ebook-2-conversation",
    "chapterId": "ebook-2-chapter-1"
  }
}
```

**`source` 決定權限**：`access` 由所有題目 `source.bookId` 對應書的 `EbookAccess` 取最高值。沒有 `source` 的題目視為 `free`。

---

## Task 1：domain model ＋ fail-closed parser

**Files:**
- Create: `lib/features/learning/domain/models/chat_quiz.dart`
- Create: `lib/features/learning/data/repositories/chat_quiz_catalog_repository.dart`
- Test: `test/unit/features/learning/chat_quiz_catalog_test.dart`
- Modify: `pubspec.yaml`（`assets:` 加 `- assets/learning/quizzes/`）

**Step 1: 先寫失敗測試**

```dart
test('不認識的題型直接報錯，不靜默跳過', () {
  expect(() => parseQuizGroup(_json(type: 'dragOrder')),
      throwsA(isA<QuizContentException>()));
});
test('單選題沒有恰好一個正解就報錯', () {
  expect(() => parseQuizGroup(_json(correctCount: 2)),
      throwsA(isA<QuizContentException>()));
  expect(() => parseQuizGroup(_json(correctCount: 0)),
      throwsA(isA<QuizContentException>()));
});
test('每個選項都必須有 feedback', () { /* ... */ });
test('題目 id 在整份 catalog 全域唯一', () { /* ... */ });
```

Run: `flutter test test/unit/features/learning/chat_quiz_catalog_test.dart`
Expected: FAIL（尚未實作）

**Step 2: 實作**

照 `ebook_catalog_repository.dart` 的形狀寫：`_requireString` / `_requireList` / `_requireEnum` 那組 helper 直接照抄語意（錯誤訊息要帶 JSON 路徑，例如 `group_1.levels[0].questions[3].choices[1].feedback 不得為空`）。

`sealed class ChatQuizQuestion` + `EbookQuizMode` 那種 exhaustive switch，讓之後新增題型時編譯器會逼你補 UI。

Run: 同上　Expected: PASS

**Step 3: 接 provider**

`lib/features/learning/data/providers/chat_quiz_providers.dart`，照 `ebook_providers.dart`：`chatQuizCatalogRepositoryProvider` / `chatQuizCatalogProvider`（FutureProvider，解析失敗是 AsyncError 不是空 catalog）。

**Commit:** `聊天測驗：內容模型與 fail-closed 解析器`

---

## Task 2：內容不變式測試（守門先於內容）

**Files:**
- Test: `test/unit/features/learning/chat_quiz_content_invariants_test.dart`

這支測試要在**內容還沒寫之前**就存在，內容才不會長歪。照 `ebook_content_invariants_test.dart` 的形狀。

必守項目：

```
結構
  - 每題至少 3 個選項；單選題恰好一個正解
  - 每個選項都有 feedback；每題都有 takeaway
  - 所有題目 id 全域唯一
  - 每關 6–8 題，唯一例外：1-1 固定 10 題
  - 第一題與最後一題都不是該關最難的題型（維持階梯，刻意收在簡單題）

權限
  - 一關的 access ＝ 它所有題目來源書當中最高的那一層
  - 1-1 的每一題，來源都不是第 5–7 冊（唯一免費出口）
  - Starter 讀不到任何 essential 關卡

深連
  - 每個 source 都指向真的存在的書與章（用 ebookCatalog 對照）
  - 沒有 source 的題目不會渲染「讀原理」按鈕

界線（§4）
  - 沒有任何一題的正解是自由輸入字串（型別層就擋掉，這條測 enum 覆蓋）

安全（§7.5 五條，第 1 期適用 1/3/4）
  1. 涉及操縱、施壓的字詞，必須出現在「這樣做是錯的」的框架裡
  3. 有「救援」題的關卡，至少一題的正解是「這是真的拒絕，該停了」
  4. 換檔題的選項一定包含「收手」，且在該收手的情境裡選它就是滿分
```

> 第 2、5 條（邀約安全提醒、明確化關卡）在第 1 期沒有對應關卡，測試先寫成 `skip` 並註明「第 2 期開推進群時解除」，不要省略，否則第 2 期會忘。

Run: `flutter test test/unit/features/learning/chat_quiz_content_invariants_test.dart`
Expected: FAIL（沒有內容）→ Task 5 完成後轉 PASS

**Commit:** `聊天測驗：內容守門測試（含三條安全底線）`

---

## Task 3：進度儲存（獨立 Hive key）

**Files:**
- Create: `lib/features/learning/domain/models/chat_quiz_progress.dart`
- Create: `lib/features/learning/data/repositories/chat_quiz_progress_repository.dart`
- Test: `test/unit/features/learning/chat_quiz_progress_repository_test.dart`

**這一步是整個計畫風險最高的地方**（鐵律 1）。

儲存鍵：`chat_quiz_progress_v1:<ownerUserId>`。照抄 `ebook_progress_repository.dart` 已經做對的四件事：

1. key 綁 Supabase account id，**沒登入完全不寫入**（`ownerUserId` 空字串直接 `ArgumentError`），不建 `anonymous` 共用進度
2. 所有 mutator 在 repository 內序列化（`Future<void> _tail`），避免連點造成 read-modify-write 互蓋
3. 讀到壞資料回空的，**但不刪原始資料**、也不把內容寫進 log
4. 冪等：重複做同一個動作不改變結果

存的東西：

```dart
class ChatQuizProgress {
  final int schemaVersion;                       // 自己的版本號，不是電子書那顆
  final Map<String, ChatQuizLevelResult> levels; // levelId -> 最佳成績
  final Map<String, ChatQuizAnswer> answers;     // questionId -> {choiceId, revision, answeredAt}
}
```

`revision` 存下來，題目改版後舊答案自動失效（沿用電子書 quiz 已有的語意）。

**必寫測試：**

```dart
test('測驗進度與電子書進度完全獨立', () async {
  await ebookRepo.markChapterCompleted(...);
  await quizRepo.recordAnswer(...);
  final ebook = await ebookRepo.load(uid);
  expect(ebook.completedChapterIds, contains(chapterId));  // 沒被測驗寫壞
  expect(box.get('learning_progress_v1:$uid'), isNotNull);
  expect(box.get('chat_quiz_progress_v1:$uid'), isNotNull);
});
test('沒登入不寫入任何東西', () { /* ownerUserId 空 → throw，box 沒新增 key */ });
test('壞資料回空但不刪原始資料', () { /* ... */ });
test('連續 20 次寫入沒有遺失', () { /* ... */ });
test('換帳號不沿用上一個帳號的進度', () { /* ... */ });
```

Run: `flutter test test/unit/features/learning/chat_quiz_progress_repository_test.dart`

**Commit:** `聊天測驗：本機進度儲存（獨立 key，不碰電子書進度）`

---

## Task 4：權限判斷

**Files:**
- Create: `lib/features/learning/domain/chat_quiz_access.dart`
- Test: `test/unit/features/learning/chat_quiz_access_test.dart`

純函式，重用 `EbookAccess` 與 `EbookSubscriptionAccess`，**不新增訂閱資料來源**。

```dart
/// 一關的權限＝它所有題目來源書當中最高的那一層。
EbookAccess accessForLevel(ChatQuizLevel level, EbookCatalog books);

/// 三態：可進 / 鎖住 / 還在確認。resolving 絕不能被當成鎖住。
ChatQuizGate gateFor(EbookAccess required, EbookSubscriptionAccess sub);
```

**必寫測試（照 `ebook_essential_unit_test.dart` 的形狀）：**

```
- free 關永不鎖
- premium 關：Starter 進得去、免費進不去
- essential 關：Starter 進不去（不得照抄 isPremium）
- isResolving 時回 resolving，不回 locked、不導 paywall
- hasError 時回 error，不包裝成 Free upsell
- 離線快取顯示 Starter 時，仍然讀不到 essential 關
```

**Commit:** `聊天測驗：關卡權限判斷（Starter 讀不到 Essential 取材）`

---

## Task 5：第 1 期內容（4 關 31 題）

**Files:**
- Create: `assets/learning/quizzes/group_1_signal.json`
- Create: `assets/learning/quizzes/group_2_lifeline.json`

| 關 | 題數 | 權限 | 題型 | 取材 |
|---|---|---|---|---|
| 1-1 她現在是哪一種 | **10** | **free** | 讀燈 ×6、選回覆 ×4 | 第 2 冊拆解庫 A/B/E ＋ 第 1 冊（**不得取材 5–7 冊**）|
| 1-2 消極期先止損 | 7 | premium | 讀燈 ×4、選回覆 ×3 | 第 3 冊救援 ＋ 第 7 冊 3.2／3.5（含**拒絕訊號三類**與**停損**）|
| 2-1 對話死在哪 | 7 | premium | 選回覆 ×5、讀燈 ×2 | 拆解庫 A/B/E（報告附錄 A 已寫好七題，直接用）|
| 2-2 情緒是開口 | 7 | premium | 選回覆 ×5、讀燈 ×2 | 拆解庫 C/D/F ＋ 第 2 冊 |

**內容產線沿用今天已驗證過的那一條**（`cross-model-review` 的 GLM worker → 守門腳本 → 合併），但這次守門條件換成 Task 2 那份不變式。**AI 起草、人工編輯，未經審閱不上線。**

**寫作規範（§7.6 第 22 條）**：所有情境設定在交友軟體語境——非同步、可能隔天才回、她同時有幾十個對話串。原始素材多半假設即時通訊的節奏，轉題目時一併改寫，否則會出現「她怎麼可能秒回」。

**1-1 要當櫥窗寫**：它是絕大多數免費使用者對這個功能的唯一體驗，也是他決定要不要付費的全部依據。密度要 ≥ 報告附錄 A 的示範。

**安全底線落點（不可延後）**：
- 1-2 必須有至少一題正解是「這是真的拒絕，該停了」（§7.5 第 3 條）
- 1-2 必須考「拒絕訊號三類」（§7.6 第 19 條）與「停損」（第 21 條）

Run: `flutter test test/unit/features/learning/chat_quiz_content_invariants_test.dart`
Expected: PASS（Task 2 那支全綠）

**Commit:** `聊天測驗：第 1 期內容 4 關 31 題`

> Task 5 完成時要回報 Bruce 兩件事：(1) 1-1 沒有放「接下去」（見 §0 的衝突處理）；(2) 1-1 那 10 題請他過目，那是櫥窗。

---

## Task 6：答題器

**Files:**
- Create: `lib/features/learning/presentation/screens/chat_quiz_player_screen.dart`
- Create: `lib/features/learning/presentation/widgets/chat_quiz_question_card.dart`
- Test: `test/widget/features/learning/chat_quiz_player_test.dart`

**外框要新寫，不要複用 `EbookQuizCard` 的容器。** 電子書那張卡是設計來「嵌在閱讀流程裡」的自足卡片；這裡要的是「一題一頁 + 頂部進度條 + 底部統一送出」的連續流程，是不同的容器。

**可以複用的是互動規矩**（照抄 `ebook_quiz_card.dart` 的行為）：
- 送出前不揭示任何對錯
- 送出後就地展開：每個選項各自的 feedback ＋ 整題 takeaway
- **對錯一定要有文字，不能只靠紅綠色差**（色盲使用者讀不出來）
- 題目 `revision` 改了，舊答案失效要重答

一律用 `brand_kit.dart` 那套元件，不碰舊的玻璃質感元件。

**必寫測試：**
```
- 未作答不能按送出、不能往下一題
- 送出前畫面上沒有任何正解線索
- 送出後每個選項都有自己的 feedback 文字
- 對錯有文字標示（不是只有顏色）
- revision 變更後，已答過的題目回到未作答狀態
- 系統字級放到最大不爆版（textScaler 3.0）
```

**Commit:** `聊天測驗：答題器（一題一頁，送出前不揭示）`

---

## Task 7：關卡地圖

**Files:**
- Create: `lib/features/learning/presentation/screens/chat_quiz_map_screen.dart`
- Test: `test/widget/features/learning/chat_quiz_map_test.dart`

- 群跟群之間全開；**群裡面線性**（1-1 過了才開 1-2）
- **第 1 期只顯示已有內容的第 1、2 群**，不畫「即將推出」的佔位（決定 7）
- **付費入口只在這裡出現一次**，就在 1-2 那一列。學習頁區塊、答題器、結果頁都不放
- `isResolving` 時鎖頭顯示中性 loading，**不得顯示「快來訂閱」**

**必寫測試：**
```
- 免費帳號：1-1 可進、1-2 鎖、第 2 群整群鎖
- 付費帳號：四關全開
- Starter：essential 取材的關卡完全看不到（第 1 期沒有，測試先建立，第 2 期會用到）
- isResolving：不顯示付費文案
- 第 3–5 群完全不出現在畫面上
```

**Commit:** `聊天測驗：關卡地圖（付費入口只出現一次）`

---

## Task 8：結果頁

**Files:**
- Create: `lib/features/learning/presentation/screens/chat_quiz_result_screen.dart`
- Test: `test/widget/features/learning/chat_quiz_result_test.dart`

- 過關門檻 **80%**；沒過標題是「**再跑一次**」不是「失敗」
- **重試無限次、不扣任何東西**
- 答錯的題列出來，有 source 的顯示「📖 讀原理 →」，沒有的不顯示按鈕
- 過關動效手寫，**由 `AnimationController` 推導，不准用 `Timer`**（鐵律 8）
- 尊重系統「減少動態效果」：關掉重動效，保留一次性音效

> **觸覺回饋第 1 期不做。** 目前全 App 只有抽卡儀式兩處用觸覺，在測驗加「答對／點選」等於新增一種全新的觸覺使用模式，範圍比看起來大。報告 §6.6 自己也標了「需要先確認」。留給第 2 期單獨評估。

**Commit:** `聊天測驗：結果頁（再跑一次，不是失敗）`

---

## Task 9：學習頁區塊 ＋ 路由

**Files:**
- Create: `lib/features/learning/presentation/widgets/chat_quiz_section.dart`
- Modify: `lib/features/learning/presentation/screens/learning_screen.dart:53-61`
- Modify: `lib/app/routes.dart`（在 `/learning/books/...` 附近加兩條）
- Modify: `test/widget/features/learning/learning_screen_ebook_hierarchy_test.dart:88`
- Test: `test/unit/app/chat_quiz_routes_test.dart`

新路由：
```
/learning/quiz                    → ChatQuizMapScreen
/learning/quiz/levels/:levelId    → ChatQuizPlayerScreen
```

順序改成（決定 1）：
```
練習室 Hero → 聊天測驗 → 互動電子書 → 短篇文章標題 → 文章列表
```

`learning_screen.dart` 目前的註解寫著「順序刻意是 練習室 Hero → 電子書 → 短篇文章：教材優先、文章在後」——**這段註解要一併改寫**，否則下一個人會以為順序被改壞了。

`learning_screen_ebook_hierarchy_test.dart:88` 那條「電子書區塊在短篇文章區之前」要擴充成三段順序斷言。

**第 1 期的區塊內容只有入口卡**：標題 ＋ 一句定位 ＋「全部關卡 →」。今日 3 題、弱點推薦、各技能準確率、連續天數、錯題入口**全部是第 2 期**，第 1 期不畫。

**區塊要自己處理自己的錯誤**：測驗內容解析失敗時只有測驗那一塊顯示錯誤，不能把同一頁的 24 篇文章一起弄死。照抄 `EbookShelfSection` 的降級做法。

**必寫測試：**
```
- 學習頁三段順序：練習室 → 測驗 → 電子書 → 文章
- 測驗 catalog 解析失敗時，文章列表仍然渲染得出來
- 兩條新路由都到得了正確畫面
```

**Commit:** `聊天測驗：學習頁區塊與路由（順序改為測驗在電子書之前）`

---

## Task 10：視覺 proof ＋ 收尾驗證

**Files:**
- Create: `test/visual_proof/chat_quiz_proof_test.dart`

照 `test/visual_proof/` 既有做法（中文字型已處理好，不會豆腐字）。

> **鐵坑（電子書踩過）**：拍付費關卡一定要用 `EbookSubscriptionAccess.essential()` 或 `.premium()`。用錯權限會被 gate 導走，截圖拍到空畫面而測試照樣綠。**每張截圖都要加「畫面上真的有目標 widget」的斷言。**

拍：關卡地圖（免費視角／付費視角）、答題器（送出前／送出後）、結果頁（過關／再跑一次）。

**全套驗證：**
```
flutter test
flutter analyze
```
Expected: 全綠、No issues found

**實機檢查表（Eric 在 iPhone 上跑，報告 §10 的第 1 期適用項）：**
```
1  免費帳號：1-1 十題完整玩完並看到過關畫面
2  免費帳號：1-2 上鎖，第 2 群整群上鎖
3  訂閱狀態還在查的時候，鎖頭不是付費文案
4  故意答錯 → 結果頁列出來，「讀原理」跳得到正確章節
5  殺掉 App 重開 → 進度還在
6  切換帳號 → 沒有殘留上一個帳號的進度
7  ★ 開電子書確認閱讀進度沒有被清掉（鐵律 1 的實機驗證）
8  開飛航模式全程可玩
9  系統字級拉到最大，答題器不爆版
10 開 VoiceOver：對錯有唸出文字，不是只有顏色
11 開「減少動態效果」：過關動效降級，音效還在
```

**Commit:** `聊天測驗：視覺 proof 與第 1 期收尾`

---

## 第 2 期（本計畫不含，出貨後另開）

加「找死亡點」「這句多給了什麼」「換檔題」「接下去」；五群全開、10 關約 72 題；錯題複習 ＋ 三格間隔重複 ＋ 今日 3 題 ＋ 連續天數 ＋ 各技能準確率；接口 A（報告推薦弱點，**必須跟報告頁共用同一個階段判定純函式**）與接口 B（雙向跳轉）。1-1 第 10 題換成「接下去」。解除 Task 2 那兩條 skip 的安全測試。

## 第 3 期（需另外授權）

「自己改一句」（Edge Function、額度、計費帳本、流量限制）＋ 接口 C（問教練為什麼）。**所有貴的、高風險的東西都隔離在這一期。**

---

## 交付

第 1 期是 Change 任務，從 `main` 開工 → 逐 Task commit → 全套測試綠 ＋ analyze 0 → push `main` → 監看 exact-SHA `Build & Distribute`。**沒有 migration、沒有 Edge Function**，所以沒有 pre-push audit 的對象。TestFlight 送審是 Eric 的手動動作。

> **dogfood 注意（§9 第 8 點）**：TestFlight 測試者如果是免費帳號，體感會是「幾乎全鎖」。收回饋前要幫測試帳號開權限，否則拿到的會是一堆關於付費牆的意見，而不是關於題目品質的意見。
