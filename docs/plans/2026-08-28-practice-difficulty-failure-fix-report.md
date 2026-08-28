# 實戰練習室難度失效：調查與修復實作報告

> **狀態：SUPERSEDED 2026-08-28**——本檔的「修復方案（批次 1–4）」已由整合 Codex review 的最終規劃取代：
> `docs/plans/2026-08-28-practice-difficulty-fix-final-plan.md`。**實作請以最終規劃為準**（本檔的批次 2 roundNonZero 修法、3a 分類器注入、3c 直塞 difficultyPrompt 三項已被撤回）。缺陷分析 D1–D5 與程式碼證據仍然有效。
>
> 原狀態：REPORT ONLY 2026-08-28（branch `claude/challenge-mode-difficulty-investigation-xpxsqk`；尚未修改任何 runtime 檔案，無 commit、無 push、無部署）

**問題陳述：** Eric 回報「挑戰模式變簡單，現在很容易都會加分，回應也變熱情」，後續補充「好感度會亂跳」。

**結論：** 挑戰模式不是壞了一次，是**五個地方各自沒接好**，疊起來把「難度」這個設定架空。其中 2 個是純 bug、1 個是接線漏掉（都可以直接修）；另外 2 個是過去刻意做的決定，現在需要重新拍板。

**證據來源：** 現行程式碼複查、離線重跑計分算式（Node 逐字複刻 `temperature.ts` 純函式）、螢幕錄影 34 張畫格逐格比對、`git log -S` 追溯。

**相關文件：** `docs/plans/2026-07-05-practice-difficulty-redesign.md`（當初的難度分級設計，三支槓桿 A/B/C 即本報告 D2/D3 的來源）。

---

## 一、五個缺陷一覽

| # | 缺陷 | 性質 | 對玩家的影響 | 修復成本 |
|---|---|---|---|---|
| D1 | 切難度不重算開場溫度 | 純 bug | 挑戰可能真的從 35 分開始（該是 20） | 極小 · client 一處 |
| D2 | 普通回合必定 +1，挑戰倍率被四捨五入抹平 | 舊決定（Game 已推翻一半） | 敷衍地聊也穩定升溫，三檔加分一樣 | 小 · 對齊 Game 現有做法 |
| D3 | 難度規格在 prompt 裡被稀釋，且不再是最後一段 | 設計漂移 | 她照後面幾段走，變得會遞話題、救場 | 中 · 會重凍黃金雜湊 |
| D4 | 評分分類器與推進下限完全不看難度 | 接線漏掉 | 三檔用同一把尺評分；推進只看發了幾則 | 中 · 三處接線 |
| D5 | 跨場保溫讓挑戰的低起點只生效一次 | 刻意設計 | 同一位對象第二場起，挑戰不再從冷的開始 | 看拍板結果 |

「挑戰」這三個字現在只影響三件事：**開場溫度、一個正負分倍率、塞進 prompt 的一段行為規格**。這三件事分別被一個 client bug、一個四捨五入、和七段後來加上去的 prompt 抵銷掉了。評分的分類器、推進的回合下限、Hint 教練，則從頭到尾就沒接上難度。

---

## 二、缺陷詳述

### D1｜切難度時，溫度計不跟著換（純 bug）

**現象**

在還沒送出第一句的畫面上，點難度那一排完全不會改變溫度計的數字。只有動到模式那一排（標準 ↔ 新手），數字才會重算。

**錄影逐格證據**（`ScreenRecording_08282026_175935`，2 fps 抽格）

| 畫格 | 操作 | 溫度計 | 正確值 |
|---|---|---|---|
| 032 | 挑戰（已選） | 20 | 20 ✓ |
| 033 | 點「輕鬆」 | 20 | 35 ✗ |
| 034 | 點「一般」 | 20 | 28 ✗ |
| 009 | 挑戰 + 新手 | 20 | 20 ✓ |
| 010–011 | 切成標準、點一般 | （溫度計隱藏） | — |
| 012 | 切回新手 | 28 | 28 ✓ |

**真因**

兩個相鄰的函式，一個有做、一個沒做：

- `lib/features/practice_chat/data/providers/practice_chat_providers.dart:1734` `setPracticeLearningMode`（切模式）→ 有重算 `temperatureScore`
- 同檔 `:2535` `setDifficultyPreference`（切難度）→ 只更新 `difficulty` / `difficultyLabel`，完全沒碰溫度

**不只是顯示錯**

送出第一則時，client 把畫面上那個數字當種子送給伺服器（同檔 `:1846`），伺服器在這段關係還沒有紀錄時直接採用它當開場溫度（`supabase/functions/practice-chat/handler.ts:4118`）。所以：

- 輕鬆 → 挑戰：挑戰真的從 **35** 開始（該 20）→ **挑戰變簡單**
- 挑戰 → 輕鬆：輕鬆真的從 **20** 開始（該 35）→ 輕鬆變難
- 挑戰 → 一般：一般從 20 開始（該 28）

`_saveDraftFromState` 還會把錯的值寫進草稿，關掉 App 再開仍然是錯的。

> 這也解釋了第一張截圖「挑戰 · 升溫 35」——35 剛好就是**輕鬆**的起始值。

**測試為什麼沒抓到**

`test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart:1095` 與 `:1107` 有覆蓋切難度，但只斷言 `difficulty` 欄位和草稿的難度，從來沒有斷言 `temperatureScore`。

UI 端（`practice_chat_screen.dart:1824`）其實寫了一道 `?? initialPracticeTemperatureScore(...)` 的保險，但新手模式下該欄位永遠不是 null，**這道保險是死的**。

---

### D2｜普通回合一定加分，挑戰的懲罰倍率被四捨五入吃掉（舊決定）

**算式**

一句「普通但不傷」的話（分類器判 `neutral`）本身就是熱度 **+1**、熟悉度 +2（`temperature.ts:88` `CONNECTION_DELTAS`），沒有「+0」這個結果。難度差異靠倍率（挑戰 ×0.7）套在後面，但 `clampHeatDelta` 用的 `roundNonZero()`（`temperature.ts:216`）規定「算出來是 0 就補成 ±1」，於是 `1 × 0.7 = 0.7` 又被四捨五入回 1。

**離線重跑驗證**（Node 逐字複刻 `temperature.ts` 純函式）

| 這輪的判定 | 輕鬆 | 一般 | 挑戰 | |
|---|---|---|---|---|
| 普通 / 小影響 | +1 | +1 | **+1** | 三檔完全相同 |
| 沒接住 / 小影響 | −1 | −1 | **−1** | 三檔完全相同 |
| 接住 / 中影響 | +5 | +4 | +3 | 倍率有效 |
| 17 輪全敷衍的收尾熱度 | 52 | 45 | **37** | 只靠出席就漲 +17 |

**性質：這是一個只翻了一半的決定**

`supabase/functions/practice-chat/learning_state_test.ts:50` 有一條測試叫 `applyLearningClassification no longer zeroes low-pressure neutral replies`——證明「普通回合 +1」是 2026-07-07（`a7165aea 重構練習室升溫判定為互動結果`）刻意從 0 改成 +1 的，不是意外。

但 2026-08-24 的 `2cd926ca 修正 Game 普通回合誤加分` 已經在 Game 模式推翻了它：沒有正向證據（`connection === "caught"` 或 `testHandling === "passed"`）就把正 delta 夾到 0。

問題在於那個守門寫在 `applyGameLearningDelta`（`game_fsm.ts:1219`）裡，而呼叫它的 `applyGameLearningIfNeeded` 開頭就是 `if (opts.request.practiceMode !== "game") return judgement;`——**新手模式沒被保護到**。截圖與錄影那場正是新手模式。

---

### D3｜難度規格被七段後來加的 prompt 蓋過去（設計漂移）

**當初的設計**

`supabase/functions/practice-chat/prompt.ts:517` 到現在還寫著難度規格「刻意放在『絕對規則』之後、prompt 尾端最高權重位置」。這句話在 2026-06-24（`1eead85f`）是真的——當時系統 prompt 就只有 `CHAT_SYSTEM_PROMPT + buildProfilePrompt(profile)` 兩段；2026-07-06 的 `3e914fe8 prompt 難度區塊移尾端` 還特地把難度移到尾端。

**後來加在它「後面」的區塊**

| 區塊 | 加入日期 | commit |
|---|---|---|
| 生活情境 `sceneContext` | 2026-07-07 | `8c655490` |
| 心情狀態 `safePartnerState` | 2026-07-07 | `4a574353` |
| 邀約成熟度 `inviteMaturity` | 2026-07-07 | `6940ef18` |
| 認識管道 `acquaintanceOrigin` | 2026-08-04 | `d444cebe` |
| 張力階梯 `tensionLadder` | 2026-08-06 | `e62ec83f` |
| 朋友圈貼文記憶 `herRecentMoments` | 2026-08-24 | `323b59af` |
| 台北時間錨點 `nowContext` | 2026-08-28 | `551a6e97` |

現行組裝順序（`prompt.ts:645–681`）：

```
CHAT_SYSTEM_PROMPT
  → buildProfilePrompt（★ 難度規格在這裡面的最後）
  → acquaintanceOrigin → nowContext → sceneContext → memorySummary
  → herRecentMoments → partnerState → [gameMode]
  → tensionLadder → temperatureBand + relationshipStage → inviteMaturity
```

**尾端那幾段跟挑戰直接互斥**

- 溫度帶指示（35 分＝ cold band）：「回覆要輕鬆接話、少施壓，**用一個好接的小鉤子讓她願意多說**」
- 挑戰規格卻要求：「**絕不主動開新話題、不替對方補話題、不救場**」
- 認識管道那段還規定：「還在最前面幾句時，你的回覆要讓對方感覺得出你們是從這個管道認識的（帶到一個具體的點就好）」——跟挑戰的「第一輪 10 個字以內、不反問」互斥

模型碰到互相矛盾的指令時會傾向照**後面**那個做。

**字數佔比**

挑戰規格 508 字；整份系統 prompt 的固定文字已超過 6,400 字（尚未計入她的貼文、記憶摘要、生活情境等動態內容）→ **不到 8%，而且不在壓軸位置**。

**測試為什麼沒抓到**

`prompt_test.ts:2104`「chat system prompt：難度區塊出現在絕對規則之後（高權重尾端）」只驗 `難度區塊 index > 「絕對規則：」index`——那是**人設區塊內部**的相對位置，不是整份 prompt 的尾端。所以後面加再多段，這條測試都是綠的。

---

### D4｜評分和推進，兩個都沒接上難度（接線漏掉）

**分類器完全不看難度**

`buildTurnClassifierMessages`（`temperature.ts:607`）收了 `profile: PracticeProfile` 參數，但函式內 `opts.profile` 出現 **0 次**——完全沒用到（`profile` 一字只在型別宣告出現一次）。所以判斷「這句接得好不好」的標準，輕鬆和挑戰是同一把尺。

**回合下限完全不看難度**

`practice_pacing.ts`（2026-08-12 `589758a6 標準／新手對標 Game——回合下限解掉推進卡死`）規定：

- 第 3 顆球 → 自動開放「可以聊個人」
- 第 6 顆球 → 自動開放「可以輕推曖昧」
- 第 8 顆球 → 開放模糊邀約

**純看使用者發了幾則，不看聊得好不好，也不看難度。** 挑戰規格白紙黑字寫「必須同時集滿 4 個以上高品質訊號」，被這條下限直接繞過。

**Hint 只拿到標籤**

`hint.ts:1217` 只把 `difficulty: ${profile.difficultyLabel}`（也就是「挑戰」兩個字）給 Hint，沒有給 `difficultyPrompt` 的四欄行為規格。所以 AI 給的建議不會跟著本場難度調整。

---

### D5｜跨場保溫讓挑戰的低起點只生效一次（刻意設計，需拍板）

**機制**

- Client：`continueWithSamePartner`（`practice_chat_providers.dart:1682`，註解「續同一位保溫」）保留 `visiblePracticeThreadId`、沿用 `temperatureScore` 三元組，但 `aiReplyCount` 歸零。
- Server：`handler.ts:4114`（註解「續聊保溫」）在 ledger 尚未建檔時，優先讀 `practice_relationship_threads` 的舊分數，其次才是 client 種子、最後才是難度起始值。

**結果**

挑戰的起始 20 分，只在一段關係的**第一場**成立。之後她永遠從「溫的」開始，而且畫面上「還能聊 N 則」看起來像全新的一場——這正是第一張截圖「挑戰 · 升溫 35 · 本場已扣 1 則、還能聊 16 則」的樣子。

**性質**

這是刻意設計，不是 bug。「續同一位就該保溫」在關係模擬上是對的；問題只在於它讓難度的區分度隨場次遞減。要不要處理、怎麼處理，是產品決定。

---

## 三、修復方案：四個獨立批次

四個批次可以各自成為一個 PR（一個 PR 一個目的、可獨立測試與回退）。

### 批次 1｜開場溫度跟著難度走（修 D1）

| | |
|---|---|
| 風險 | **低** |
| 範圍 | 只動 client |
| 需拍板 | 否 |

**改什麼**

`lib/features/practice_chat/data/providers/practice_chat_providers.dart` 的 `setDifficultyPreference`，在 `copyWith` 補上：

- `temperatureScore`：依新難度重算（`initialPracticeTemperatureScore(resolved.difficulty)`），僅在 `isAssistedLearningMode` 時給值，否則 null
- `temperatureBand: null`：讓顏色回到用分數推的兜底（比照 `setPracticeLearningMode` 的做法）

**不動什麼**

熟悉度與階段標籤不用碰——三檔難度都是從 0、「建立熟悉中」起跳。

**補測試**（`practice_chat_controller_test.dart`）

- 切難度後 `temperatureScore` 等於該難度起始值（easy 35 / normal 28 / challenge 20 各一條）
- 標準模式切難度後 `temperatureScore` 仍為 null
- 草稿（`_saveDraftFromState`）也帶到新值

**會打到的既有測試**：無。

**風險**：極低。純粹是開聊前的 client 狀態，而且 `messages.isNotEmpty` 已經擋住開聊後改難度。

**PR 一句話**：切難度時同步重算新手開場溫度。

---

### 批次 2｜普通回合不再自動加分（修 D2）

| | |
|---|---|
| 風險 | **中**（體感改動） |
| 範圍 | Edge `practice-chat` |
| 需拍板 | **是**（見拍板題一） |

**改什麼**

1. `temperature.ts` 新增純函式（例如 `withPositiveEvidenceGate`）：這一輪沒有 `connection === "caught"` 也沒有 `testHandling === "passed"` 時，把熱度與熟悉度的**正** delta 夾到 0，負的照走。
2. `handler.ts:1428` `protectedJudgementForSnapshot` 裡、`protectAppliedHintTemperature` 之後套用；只在 `practiceMode === "beginner"` 生效，且 `protectedHintType !== undefined`（原句照貼 Hint）時跳過。

> 這與 Game 的 `applyGameLearningDelta`（`game_fsm.ts:1219` `canEarnPositive`）是同一套規則，等於把 `2cd926ca` 那個修法補到新手。

**建議一起處理**

`roundNonZero`（`temperature.ts:216`）改成只保護負向（正向算出 0 就是 0）。否則挑戰的 0.7 倍率在小分數上永遠會被抹平回 +1。

**會打到的既有測試**

`learning_state_test.ts:50`「no longer zeroes low-pressure neutral replies」需要改寫。純函式 `applyLearningClassification` 本身不動、守門是外掛的一層，所以 Game 與標準模式不受影響。

**風險**：中。要真機確認不會變成「一路都不動」。

---

### 批次 3｜難度真正接進評分與推進（修 D4）

| | |
|---|---|
| 風險 | **中** |
| 範圍 | Edge `practice-chat`，三處 |
| 需拍板 | 3b 需要（見拍板題三） |

**3a · 分類器帶入難度尺度**

`temperature.ts:607` `buildTurnClassifierMessages`，在 system prompt 加一句本場難度的判準。例如挑戰：「接住的門檻更高——只有真的接住她的情緒或梗才算 caught，禮貌回應算 neutral。」

會打到的既有測試：無（目前沒有任何測試鎖住這個函式的難度盲點）。

**3b · 回合下限吃難度**

`practice_pacing.ts` 的 `practiceStageFloorFor` / `practiceInviteFloorFor` 收 difficulty：挑戰把 3 / 6 / 8 往後推（例如 5 / 9 / 12），或整組不套。

會打到的既有測試：`practice_pacing_test.ts` 現有 8 條。

**3c · Hint 拿到行為規格**

`hint.ts:1217` 把 `difficultyPrompt` 的四欄行為規格給 Hint，不只給 label。

會打到的既有測試：`hint_test.ts` 的 prompt 位元組／字數斷言。

**風險**：中。3b 會讓挑戰的推進變慢，跟批次 2 疊起來可能過頭。**建議批次 2 和 3b 分兩次上，中間夾一次真機體感確認。**

---

### 批次 4｜prompt 權重歸位（修 D3）

| | |
|---|---|
| 風險 | **高**（影響所有練習模式） |
| 範圍 | Edge `practice-chat` 共用 prompt |
| 需拍板 | 否，但建議最後做 |

**改什麼**

1. 調整 `buildChatMessages`（`prompt.ts:645–681`）的串接順序：把難度的行為規格從 `buildProfilePrompt` 裡抽出來，改成整份系統 prompt 的**最後一段**（在 `inviteMaturity` 之後）。
2. 處理矛盾：`temperatureBandInstruction`（`temperature.ts:129`）在挑戰難度時不該說「用一個好接的小鉤子讓她願意多說」——難度應該能覆寫或收斂溫度帶的文案。

**會打到的既有測試**

- `moments_memory_test.ts` 的 SHA-256 黃金雜湊（standard / beginner / game 三種模式全部）——**這正是它該做的事**，要一起重新凍
- `prompt_test.ts:2104` 要改成驗「整份 prompt 的尾端」，而不是人設區塊內部的相對位置

**風險**：高。三種練習模式共用的 prompt，改壞會影響每一場練習。建議先用 `tools/practice-difficulty-bakeoff` 離線對拍再上。

---

## 四、需要 Eric 拍板的三件事

### 一、普通回合要不要真的變 0 分？

Game 模式已經是「沒有正向證據就不加分」。新手要不要跟？跟了之後，敷衍地聊會完全不動分，玩家可能覺得「壞掉了」；不跟的話，難度的區分度就只剩下扣分那一側。

- **A · 完全對齊 Game**（建議）
- B · 只在挑戰難度套用，輕鬆／一般維持現狀
- C · 維持現狀，只修其他四個洞

### 二、續玩同一位時，挑戰的溫度要不要重新錨定？

目前完全沿用，所以挑戰只有第一場是冷的。這是關係模擬的正確行為，但也是難度失效的一環。

- A · 維持完全沿用（關係連續性優先）
- B · 每新一場往起始值衰減一定比例
- C · 挑戰難度每場重新錨定回 20，輕鬆／一般照舊

### 三、挑戰的回合下限要放寬多少？

現在三檔共用第 3 / 6 / 8 顆球。這條下限當初（`589758a6`）是為了解「推進卡死」，拿掉會讓那個老問題回來。

- **A · 挑戰往後推到 5 / 9 / 12**（建議）
- B · 挑戰整組不套下限
- C · 維持現狀

---

## 五、驗證計畫與上線順序

### 每個批次都要跑

- `deno test supabase/functions/practice-chat/`（現況 1,216+ 條）、`deno lint`、`deno fmt`
- `flutter analyze`、`flutter test`（批次 1 主要在這裡）

### 批次 2 / 3 / 4 額外要跑

- `tools/practice-difficulty-bakeoff`：三難度 × 三腳本離線對拍，比較收尾溫度與 `dateChance` 分佈
- 真機：同一位對象、同一組敷衍台詞，三檔各跑一場，看收尾溫度有沒有拉開

### 建議順序

1. **批次 1 — 立刻可以走。** 純 bug、零風險、獨立 PR，不需要等任何拍板。
2. **Eric 拍板三題。** 批次 2、3b 的方向取決於這三個答案。
3. **批次 2 → 真機體感。** 先確認不會變成「一路都不動」，再往下走。
4. **批次 3 → 真機體感。** 3a / 3c 風險低可一起，3b 單獨一個 PR 方便回退。
5. **批次 4 — 放最後。** 它會重凍黃金雜湊，前面的批次先落地才不會互相干擾對拍基準。

### 部署風險提醒

push `main` 會自動觸發 `Build & Distribute` 與 Edge 部署。批次 2/3/4 都動到 `practice-chat`，建議一律在 branch 上做、branch push、PR CI 當作 pre-merge 證據，不直接 push `main`。

---

## 附錄：本報告未做的事

- 沒有修改任何 runtime 程式碼或設定
- 沒有 commit、沒有 push、沒有部署
- 沒有跑 `deno test` / `flutter test`（本次是純靜態複查 + 離線算式重跑 + 錄影比對；容器內無 deno）
