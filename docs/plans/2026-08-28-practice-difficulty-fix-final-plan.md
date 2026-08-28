# 實戰練習室難度修復：最終實作規劃（整合 Codex review）

> **狀態：PLAN ONLY 2026-08-28**（branch `claude/challenge-mode-difficulty-investigation-xpxsqk`；本檔為實作依據，尚未修改任何 runtime、無 commit、無 push、無部署）
>
> **基準：** `main@1338e896`
> **前版：** `docs/plans/2026-08-28-practice-difficulty-failure-fix-report.md`（調查報告；其「批次 1–4」方案已由本檔取代，缺陷分析 D1–D5 仍然有效）
> **整合來源：** Codex 唯讀 review（2026-08-28，同基準）。review 提出的每一項新事實與反對意見，本檔都已逐一對回程式碼驗證後才採納或駁回，結果見「〇、裁決」。

**一句話總結：** 原調查抓到的五個缺陷全部成立，但原修法有三處要撤回改寫（roundNonZero、分類器注入難度、Hint 直塞 NPC 規格）；Codex 補的三個新發現（bakeoff 失真、debrief 順位、seed 觀測缺口）全數證實。最終方案是七個獨立 PR，難度差異集中在「計分政策與 prompt 順位」，分類器保持客觀、跨場保溫完整保留。

---

## 〇、裁決：兩份報告的分歧點，逐項對程式碼驗證後的結論

| 分歧點 | 原報告 | Codex review | 裁決 |
|---|---|---|---|
| 分類器要不要看難度 | 3a：注入難度判準 | 否，保持客觀 | **採 Codex。** 挑戰已有低起始分、×0.7/×1.3 倍率、更兇的 NPC、更高邀約門檻；同一句話再被判得更差是雙重懲罰，分數會更難解釋（正是「亂跳」體感）。分類器答「這句客觀上接住了沒」，難度政策答「同一結果加扣多少」。兩層分開才可測試、可解釋。 |
| `roundNonZero` 要不要改 | 建議改成只保護負向 | 不改，改了也沒用 | **採 Codex，原建議撤回。** 已驗證：`Math.round(0.7) = 1`，+1 不是走「0 補成 ±1」那個分支來的，改 `roundNonZero` 根本擋不住。精準開關是證據閘門（下方 PR 2），不是動整數化。原報告的**診斷**（四捨五入吃掉倍率）正確，**修法**錯誤。 |
| 普通回合 0 分的範圍 | 建議全 beginner 對齊 Game | 第一版只改 challenge | **採 Codex。** 最小範圍正中 Eric 的回報（挑戰變簡單），輕鬆／一般保留正回饋不動，真機體感確認後再議是否擴大。 |
| 難度 prompt 搬到最尾端 | 無條件搬最後 | 分模式順位，Game FSM 優先 | **採 Codex。** 已驗證 `gameMode` 區塊在組裝順序中間（`prompt.ts:665`）；無條件把難度壓到最後會蓋掉 Game 的 FSM 測試、懲罰演出與速約窗口。要的是明確的順位規則，不是字串搬家。 |
| Hint 的難度規格來源 | 3c：直塞 `difficultyPrompt` | 新增教練視角 `hintStandard` | **採 Codex，原建議撤回。** NPC 規格裡的「你」是女孩本人，Hint 裡的「你」是使用者——直塞會角色反轉。 |
| 挑戰回合下限 | 5 / 9 / 12 或整組不套 | 5 / 9 / **無純回合數邀約下限** | **採 Codex。** 12 回合自動開模糊邀約仍然是「聊得夠久就繞過品質」，只是晚四球。 |
| 跨場保溫（D5） | 三選項交 Eric 拍板 | 完整保溫，不重置不衰減 | **採 Codex 為預設。** 重置或衰減會製造「上一場 50、下一場 20」——比現在更明顯的亂跳，且破壞「同一位女孩記得上一場」的產品語意。改為補測試與觀測，不動行為。Eric 仍可覆寫。 |

### Codex 的三個新發現，驗證結果

1. **bakeoff 已不能代表 production——證實，且比 review 說的更糟。** `tools/practice-difficulty-bakeoff/bakeoff.ts:282` 呼叫分類器時沒傳 `assistantReply`，而且分類發生在 `turns.push({role:"ai"})` **之前**（`:308`），分類器完全看不到女孩那一輪的回覆；沒有 `applyPartnerStateUpdate` 累積 mood；`buildChatMessages`（`:264`）只帶 practiceMode ＋兩個分數，production 實際注入的認識管道、時間、生活情境、記憶、貼文全都沒有——所以它剛好量不到 D3「後加 prompt 蓋掉難度」這個最關鍵的問題。
2. **debrief 難度判準也有順位問題——證實。** `prompt.ts:976-999`：`difficultyDebriefStandard` 排在 user prompt 最前面，後面才接 `temperatureBandDebriefInstruction`（warm 檔明寫「不得把整場說成毫無進展或機會很低」）、階段、與帶著 dateChance high/medium 指示的 `inviteMaturityPrompt`——後面的指示可能把挑戰的嚴格判準放寬回去。
3. **缺分數來源觀測——證實。** `practice_chat_succeeded`（`handler.ts:4355`）記了 difficulty，但沒記本輪起算分數是來自 ledger、relationship thread、client seed 還是難度預設值；「第一輪跳分」發生時無法快速定位是哪一層。

### 原報告被撤回或修正的三個建議（供追溯）

- 批次 2 的「順手改 `roundNonZero`」→ 撤回（無效修法）。
- 批次 3a 的「分類器 prompt 注入難度判準」→ 撤回（雙重懲罰）。
- 批次 3c 的「把 `difficultyPrompt` 原文給 Hint」→ 撤回（角色反轉），改為 `hintStandard`。

---

## 一、定案的產品規則（本計畫預設；屬產品感受，Eric 可覆寫）

| 題目 | 定案 | 理由 |
|---|---|---|
| 普通但不傷的回合 | **只有挑戰改為 0 分**；輕鬆／一般維持現狀 | 最小範圍解決回報，保留輕鬆模式的正回饋 |
| 分類器是否隨難度變嚴 | **否** | 同一句先得到一致的客觀分類，再由難度決定獎懲 |
| 挑戰推進下限 | 個人／曖昧延後到 **5／9**；**取消純回合數邀約下限** | 回合數永遠不該單獨繞過「聊得好不好」 |
| 同一位女孩續聊 | **完整保溫，不重置、不衰減** | 關係連續性優先；重置才是更大的亂跳 |
| Game 與難度衝突 | **Game FSM 優先於難度行為規格** | Game 有自己的階段、失敗狀態與速約規則 |

---

## 二、七個獨立 PR

每個 PR 一個目的、可獨立測試、合併與回退；commit 訊息繁中、一個 concern。全部走 branch + PR CI，不直接 push `main`（push `main` 會自動部署 practice-chat 且觸發 Build & Distribute）。

### PR 0｜先修 difficulty bakeoff，建立可信基準

- **性質：** 測試工具，不動使用者 runtime。**風險：低。**
- **為什麼要先做：** 後面每個行為改動（PR 2/3/4/5/6）都需要可信的前後對照；現在的工具連 D3 都量不到。

**修改檔案**

- `tools/practice-difficulty-bakeoff/bakeoff.ts`、`scripts.ts`、`README.md`
- 新增 `tools/practice-difficulty-bakeoff/bakeoff_test.ts`

**實作規格**

1. 分類器補傳 `assistantReply: reply`，並把分類移到取得回覆**之後**（對齊 `handler.ts:1504` 的真實呼叫形狀）。
2. 每輪用 `applyPartnerStateUpdate` 累積 partner state，下一輪回灌 `buildChatMessages`。
3. 加一組固定、無個資的 full-context fixture：認識管道（`getAcquaintanceOrigin`）、台北時間、生活情境、記憶摘要、朋友圈貼文區塊——與 production 注入形狀一致；minimal 與 full-context 兩種形狀都要能跑。
4. 之後 PR 2 的挑戰獎勵閘門必須抽成純函式讓 handler 與 bakeoff 共用；工具內禁止複製規則。
5. 新增 `low_signal_polite` 腳本：整場有禮貌但不接內容，專測「被動升溫」。
6. 報告每輪補：分類結果、閘門是否生效、分數前後、partner mood、prompt 字數。

**Gate（工具自測）**：同一 fixture 三難度用相同 user 腳本；分類器收到剛生成的回覆；下一輪 prompt 看得到上一輪 partner state；full-context fixture 覆蓋所有 production 注入區塊。

---

### PR 1｜切難度後同步重設開場狀態（修 D1）

- **性質：** 確定 bug（client）。**風險：低。** 可與 Edge 修正完全並行，不等拍板。

**修改檔案**

- `lib/features/practice_chat/data/providers/practice_chat_providers.dart`（`setDifficultyPreference`，`:2535`）
- `test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart`

**實作規格**

`setDifficultyPreference` 在難度解析完成後，若為 assisted mode（beginner／game）同步重設**整組** assisted 初始狀態（比照 `setPracticeLearningMode` `:1734` 的形狀）：

- `temperatureScore = initialPracticeTemperatureScore(resolved.difficulty)`
- `temperatureBand = null`（UI 回落分數鏡像）
- `familiarityScore = 0`、`relationshipStageLabel = 建立熟悉中`
- `lastTemperatureDelta = null`、`temperatureReason = null`

standard 模式維持全部 null。採整組重設而非只改一個分數：此方法只在第一則送出前可用（`messages.isNotEmpty` 即 no-op），不會誤刪關係進度，卻能防 draft 還原殘留不一致欄位。

**必補測試**

- beginner：normal→challenge 28→20；challenge→easy 20→35
- game：同樣隨難度更新
- standard：切難度後 `temperatureScore` 仍 null
- random 偏好：分數等於**本次實際解析出**的難度起始值
- draft：難度與 `temperatureScore` 一起寫入
- 第一則 API request 的 seed 等於畫面選中難度的起始值（堵 `providers.dart:1846` → `handler.ts:4118` 那條污染路徑）
- 已有 messages 時切難度仍 no-op

**回退條件：** 切 chip 造成換女孩、清 transcript、額度變動或 standard 出現分數 → 立即回退。

---

### PR 2｜挑戰普通回合不再被動加分（修 D2）

- **性質：** 計分規則。**風險：中（體感）。** 第一版只改 **challenge × beginner**（Game 已有自己的閘門 `game_fsm.ts:1219`；standard 無分數；easy／normal 不動）。

**修改檔案**

- `supabase/functions/practice-chat/temperature.ts`、`handler.ts`
- `learning_state_test.ts`、`index_test.ts`

**規則（先客觀分類、再難度政策）**

```
有 caught 或 passed                    → 允許正向加分（仍吃 ×0.7）
無正向證據、結果本來為正               → challenge beginner 夾到 0
結果本來為負                           → 照常扣分（×1.3）
受保護的 exact／small-edit Hint        → 豁免，保留既有 Hint floor
easy／normal／Game／standard           → 行為與改前 byte 級一致
```

**實作方式**

1. `temperature.ts` 新增具名純函式（如 `applyChallengeRewardGate`），簽名收 `judgement、currentHeat、currentFamiliarity、classification、protectedAppliedHint`；內部重用 `withNonPositiveLearningDeltas`，不重算 score/stage。豁免邏輯放在**閘門內**（鏡像 Game 的 `canEarnPositive = protectedAppliedHint || (...)`），不是靠套用順序。
2. 接在 `handler.ts` `protectedJudgementForSnapshot`（`:1428`）與 fallback 兩條路徑內，位於 `protectAppliedHintTemperature` 之後、crude-offense 最大扣分與 cooldown 之前後關係維持現狀（嚴重冒犯的確定性扣滿不受閘門影響）。
3. 閘門必須活在 `...ForSnapshot` closure 裡，CAS 重試時用新分數重算仍套同一規則。
4. 純函式同時 export 給 PR 0 的 bakeoff 共用。

**明確不做：** 不改 `CONNECTION_DELTAS.neutral`（會牽動全模式）；不動 `roundNonZero`；不把難度塞進分類器。

**必補測試**

- challenge + neutral/minor → heat 0、familiarity 0
- challenge + missed／defensive → 負分保留
- challenge + caught／passed → 正分保留且吃 ×0.7
- challenge + protected Hint + neutral → floor 保留
- easy／normal／Game 同 fixture 與改前完全相同
- CAS 首次失敗重算後仍套相同閘門
- `learning_state_test.ts:50`「no longer zeroes low-pressure neutral replies」改寫為「非 challenge 不夾、challenge 夾」

**回退條件：** challenge 高品質句也無法加分；或 easy／normal／Game 行為漂移。

---

### PR 3｜重整 chat prompt 指令順位（修 D3）

- **性質：** Prompt 架構。**風險：高**（三模式共用）。**必跑 full-context bakeoff（PR 0 之後）＋ Game 回歸。**

**修改檔案**

- `supabase/functions/practice-chat/prompt.ts`（`buildProfilePrompt` `:519`、組裝 `:645-681`）
- `temperature.ts`（`temperatureBandInstruction` `:129`）
- `prompt_test.ts`（`:2104` 那條改驗整份 prompt 尾端）、`moments_memory_test.ts`（黃金雜湊重凍）
- 視需要 `acquaintance_origin_test.ts`

**實作規格**

1. 從 `buildProfilePrompt` 抽出難度行為區塊；generic 狀態指示（時間、情境、記憶、partner state、張力、溫度帶、邀約）先組完，**難度行為規格排在其後**。
2. 尾端加一小段明確的 conflict resolver：
   - 安全／身份／現實錨定／明確拒絕永遠最高；
   - Game：**Game FSM 高於難度規格**；
   - standard／beginner：**難度規格高於一般性的 band／pacing 建議**；
   - band 與 pacing 是「允許上限」，不是「必須主動遞話題或邀約」。
3. `temperatureBandInstruction` 的 cold 檔移除「用一個好接的小鉤子讓她願意多說」這類命令式文案，改為低壓狀態描述；要不要延伸、反問、回多長由難度決定。
4. 認識管道的「最前面幾句要帶到一個具體的點」（`prompt.ts:218`）改為：語氣與戒心符合管道；只有對話自然碰到時才帶具體點，不為交代設定另開話題。

**必補測試**

- full-context challenge prompt：難度區塊位於 band／invite／memory 之後
- challenge prompt 不再同時出現「絕不開新話題」與「必須丟鉤子」；也不再同時出現「不救場」與「開頭必須主動帶具體點」
- Game prompt 的順位規則明確指定 FSM 優先
- safety／identity／reality anchoring 順位不因搬動而降
- **黃金雜湊只在語意測試與 bakeoff 過關後重凍，不得為了讓測試變綠直接重算**

**回退條件：** Game FSM 指令失效、女孩洩漏內部詞、三模式回覆整體變短或變冷。

---

### PR 4｜推進下限吃難度（修 D4 之一）

- **性質：** 推進節奏。**風險：中。** 只影響 beginner（game 走 FSM、standard 走白話 pacing 行）。

**修改檔案**

- `supabase/functions/practice-chat/practice_pacing.ts`
- `prompt.ts`（`practiceStageFloorFor` 呼叫點）、`hint.ts`（**四個呼叫點** `:992`、`:998`、`:1624`、`:1637`——守門與 prompt 必須同一份政策）
- `practice_pacing_test.ts`

**政策**

| 難度 | 可聊個人 | 可輕推曖昧 | 模糊邀約 |
|---|---:|---:|---:|
| easy／normal | 3 | 6 | 8 |
| challenge | 5 | 9 | **無純回合數下限** |

**API：** `practiceStageFloorFor(userTurnCount, mood, difficulty)`／`practiceInviteFloorFor(...)`／`standardPacingLine(...)`，`difficulty` 預設 `normal`，未更新的呼叫點行為不變。

**必補測試**

- easy／normal 仍 3／6／8；challenge 第 4 回合無 personal floor、第 5 才有；第 8 無 flirt floor、第 9 才有；任何回合不因回合數單獨取得 invite floor
- guarded／annoyed 仍停用整組 floor（順序：floor 先、mood 降階後套，維持現有釘法）
- NPC prompt 與 Hint 守門（`buildHintDecision`）同一份政策——不能一邊已准邀約、一邊叫使用者別推進

**回退條件：** challenge 永遠推不動；或 guarded／annoyed 仍被 floor 強制升階。

---

### PR 5｜Hint 注入教練視角的難度尺度（修 D4 之二）

- **性質：** 教練一致性。**風險：中低。**

**修改檔案**

- `supabase/functions/practice-chat/practice_persona.ts`（`DifficultyConfig`／`PracticeProfile` 新增 `hintStandard`）
- `hint.ts`（`profileToEvidence` `:1207` 加 `difficultyCoachingStandard` 欄位）
- `practice_persona_test.ts`、`hint_test.ts`

**文案語意（教練視角，「你」＝使用者；不得重用 NPC 原文）**

- easy：自然、低壓、有回應即可；小尷尬可以修一次。
- normal：至少接住她一個具體點或分享一點自己；避免純查戶口。
- challenge：建議句必須接住她最新的具體內容、情緒或梗；一般禮貌句不算升溫；訊號不足時不建議邀約，也不要用萬用反問救場。

**必補測試**

- 三難度各帶出對應尺度；challenge Hint 不因回合數建議邀約；兩個可貼句仍可用（不得故意產生差句模擬難度）；不得把 NPC 第一人稱規格、難度名稱或幕後設定抄進可見回覆；Game Hint 仍以 Game tactic／FSM 優先。

**回退條件：** Hint 角色反轉、替女孩說話、可貼句品質下降。

---

### PR 6｜debrief 難度順位 ＋ 分數來源觀測（修新發現 2、3）

- **性質：** 結果一致性與除錯能力。**風險：中。**

**修改檔案**

- `supabase/functions/practice-chat/prompt.ts`（`buildDebriefMessages` `:976-999`）、`handler.ts`
- `prompt_test.ts`、`index_test.ts`；視需要新增純函式測試檔

**Debrief 修正**

把「最終 dateChance 判準」移到所有狀態證據（band／stage／invite）**之後**，並明寫：

- 溫度與 invite maturity 是證據，不是自動給 high 的命令；
- 最終 dateChance 必須同時符合本場難度標準；challenge 缺高品質訊號即使聊得順也不得 high；
- Game 的技巧拆解仍由 Game contract 決定，但 dateChance 不得繞過難度與安全邊界。

**分數來源 helper**

把 `handler.ts:4114-4118` 的多層 ternary 抽成純函式：

```
resolveLearningSeed(...) → { temperatureScore, familiarityScore,
  source: ledger | relationship_thread | client | difficulty_default }
```

產品回應不暴露 source；只進無逐字稿的結構化 log（`practice_chat_succeeded` 補欄位）：practiceMode、difficulty、roundIndex、seed source、score before/after、delta、classification enums、challenge 閘門是否生效、是否 continuation、prompt policy version。**不記** user 文字、女孩回覆或完整 prompt。

**必補測試**

- seed 優先序：ledger ＞ 同 thread 分數 ＞ client seed ＞ 難度預設；thread profile 不符或資料無效時不得誤用
- continuation 從上一場 N 分開始，第一輪只動本輪 delta，無隱藏重置
- debrief full prompt 中，最終難度 dateChance 規則位於 band／invite guidance 之後

**回退條件：** 同一場 seed source 不穩定；debrief 與實際分數明顯矛盾。

---

## 三、驗證計畫

### 靜態與單元測試（每個 PR）

實作前先讀 `.agent/environment.json`，用專案釘選環境。

```bash
# Edge PR
deno fmt --check supabase/functions/practice-chat tools/practice-difficulty-bakeoff
deno lint supabase/functions/practice-chat tools/practice-difficulty-bakeoff
deno test supabase/functions/practice-chat/

# Client PR
flutter analyze
flutter test test/unit/features/practice_chat/
flutter test test/widget/features/practice_chat/
```

Prompt PR（PR 3／6）另須逐條確認黃金雜湊差異都在預期內，不是順手重凍。

### Bakeoff 驗收門檻（PR 0 修好後才算數；正式 gate ≥3 runs，合併候選 5 runs）

1. challenge 平均女孩回覆長度 ≤ easy 的 60%
2. `bad_interrogator`：challenge 的 dateChance 全 low
3. `low_signal_polite`：challenge 平均 heat 淨變化 ≤ 0（不能靠禮貌出席升溫）
4. `high_quality`：challenge 必須拿得到正向 delta（不能一路卡 0）
5. challenge 敷衍／短回占比顯著高於 easy
6. **minimal 與 full-context fixture 都要拉得開**（證明後加 prompt 不再蓋掉難度）
7. Game 指標對修正前基準無非預期退化

### 真機驗收腳本（同一位女孩、同一套固定句子，依序 easy／normal／challenge）

- **開場：** 切 chip 立即顯示 35／28／20，不需切學習模式才刷新
- **普通句（8–10 句純禮貌）：** easy／normal 體感如舊；challenge 不再每輪固定 +1；畫面 delta／reason 與 server 一致
- **高品質句（接住具體內容＋分享自己＋自然玩笑＋低壓邀約）：** challenge 能逐步升溫，不是純懲罰；女孩仍比 easy 短、挑，但無無理由敵意
- **續聊：** 第一場收在 N 分；續同一位從 N 開始；第一則後只動本輪 delta，不得跳回 20／28／35

---

## 四、上線順序與回退

**順序：** PR 0（存 current main 基準）→ PR 1（可並行先上）→ PR 2 → 真機體感 → PR 3（必跑 full-context bakeoff ＋ Game 回歸）→ PR 4 → PR 5 → PR 6。

**不得把 PR 2–6 合成一個大 PR**——體感變差時要能分辨是計分、NPC prompt、pacing、Hint 還是 debrief 造成。

| 批次 | 立即回退條件 |
|---|---|
| PR 1 | 切難度造成換女孩、清 transcript、額度變動、standard 出現分數 |
| PR 2 | challenge 高品質句也無法加分；easy／normal／Game 漂移 |
| PR 3 | Game FSM 失效、洩漏內部詞、三模式回覆都變短或都變冷 |
| PR 4 | challenge 永遠推不動；guarded／annoyed 仍被強制升階 |
| PR 5 | Hint 角色反轉、替女孩說話、可貼句變差 |
| PR 6 | seed source 不穩、debrief 與實際分數矛盾 |

---

## 五、明確不納入本次實作

- 不重置、不衰減同一位女孩的跨場溫度／熟悉度
- 不修改訂閱、quota、翻牌、gacha、20 則上限或 round 機制
- 不新增 DB migration（現有 ledger／relationship thread 足夠）
- 不讓分類器因難度改變客觀分類標準
- 不把 NPC 的 `difficultyPrompt` 原文丟進 Hint
- 不以更新黃金雜湊代替行為驗證

---

## 六、完成定義

同時滿足以下所有條件，才算「難度失效已修好」：

- 選擇的開場分數與第一則 server seed 一致
- challenge 不再靠普通回合被動升溫
- 同一句使用者訊息先得到一致客觀分類，再由難度決定獎懲
- challenge 的 NPC 回覆、推進速度、Hint、debrief 用同一套難度語意
- full-context bakeoff 仍能拉開 easy／challenge（不只 minimal 有效）
- 高品質玩家在 challenge 仍能升溫，不是純懲罰模式
- 同一位女孩續聊完整保留關係進度，無跨場隱藏掉分
- Game、standard、easy／normal 無非預期退化
- 單元、整合、prompt golden review、bakeoff、實機腳本全部通過

---

## 附錄：前版「批次」與本版「PR」對應

| 前版 | 本版 | 變化 |
|---|---|---|
| — | PR 0 | 新增（Codex 發現 bakeoff 失真，經驗證屬實且更嚴重） |
| 批次 1 | PR 1 | 擴為整組 assisted 初始狀態重設；補 random／game 測試 |
| 批次 2 | PR 2 | 範圍縮為 challenge-only；撤回 roundNonZero 修法；閘門抽純函式與 bakeoff 共用 |
| 批次 3a | （撤回） | 分類器維持客觀，不注入難度 |
| 批次 3b | PR 4 | 5/9 ＋ 取消純回合數邀約下限；明確要求 hint.ts 四個呼叫點同步 |
| 批次 3c | PR 5 | 改為教練視角 `hintStandard`，不直塞 NPC 規格 |
| 批次 4 | PR 3 | 改為分模式順位層 ＋ conflict resolver，非無條件搬尾端 |
| 拍板題二（D5） | 定案：完整保溫 | 由 PR 6 補測試與觀測，不動行為 |
| — | PR 6 | 新增（debrief 順位 ＋ seed 來源觀測，經驗證屬實） |

**審核限制：** 本檔為靜態複查與規劃，未執行 Deno／Flutter／真機／付費模型 bakeoff；上述測試須由各實作 PR 補齊後方為上線證據。
