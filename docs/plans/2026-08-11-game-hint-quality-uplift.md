# Game hint/debrief 品質拉升計畫（2026-08-11,Fable 5 規劃、待接棒實作)

## 背景與症狀(Eric 真機實測,Nina 場景)

用戶開場「嗨」後全程用 5 次 hint,結果:

1. **5 個 hint 全是瑣事問答**(腳痠/泡腳/追劇),每句都以問句收尾 → 整場一問一答。
2. 沒有建立男女前提、沒有側面展示個性樣本(DHV)、沒有推拉、沒有「說話留一半」。
3. hint 落落長(貼近 60 字上限),不像高手的簡潔有態度。
4. 教練拆解卡(debrief)反過來批評「整場停留在問答形式」——**debrief 打臉自家 hint**。

用戶只有 5 次 hint、20 則 AI 回覆,每次 hint 扣 1 則額度。Game mode 的產品目標:
打開(簡單資訊交換)→ 建立男女前提 → 快速推進 → 文字側面展示個性樣本 →
測試/賦格(高位框架)→ 推拉 → 應對廢測 → 升溫 → 鋪墊模糊邀約 → 速約。
(參考:`Vibesync重要文件/社交高手的通關密語:七步聊天法核心概念解析.md`、`高階技術.pdf`)

## 根因診斷(已對到程式碼,非猜測)

全部在 `supabase/functions/practice-chat/`:

### R1:FSM 階段推進靠分數,分數爬升速度跟 hint 預算完全脫節(主因)
- `game_fsm.ts` `basePhaseFor()`:phase 由 `relationshipStage` 決定;
  `temperature.ts` `relationshipStageFor()`:familiarity < 40 → `building_familiarity` → **P1_OPEN**。
- 開場幾輪 familiarity 必然低,5 次 hint 用完時 FSM 還停在 P1,
  `targetVariableFor()` 給 `familiarity`,所以每個 hint 都在「建立熟悉」= 聊瑣事。
- 產品經濟是「20 則內收尾、5 次 hint 每發都要推進」,但 FSM 是「分數到了才升階」——結構性錯配。

### R2:P1 的 stage guidance 主動把 hint 釘死在瑣事
- `hint.ts` `hintStageGuidance("building_familiarity")` = 「先接住她的狀態、情緒或具體情境;不要直接曖昧」。
- `visibleGameHintContract()` 「先讀淺溝通:累→降成本」——她說累,hint 就一路降成本問答。
- system prompt「新手低溫或剛開場只輕推情緒,不直接邀約」對 game mode 同樣生效。

### R3:few-shot 範例本身多數以問句收尾,教會模型一問一答
- `hint.ts` `GAME_HINT_MOVE_EXAMPLES`:「妳的放空儀式是什麼?」「妳酒量如何?」——
  示範句形狀 = 接住+回問,模型照抄形狀。
- callback 契約(詞面扣回她的字眼)是對的,但沒有配套「回應之後要轉進」的指令,
  導致 hint 永遠在「回應她的瑣事」而不是「借她的瑣事轉進男女前提/自我揭露」。

### R4:字數上限被當目標寫好寫滿
- `HINT_REPLY_SOFT_CHAR_LIMIT = 60`,prompt 只說「≤60字」。模型天性寫到上限。
  高手句是 15-35 字、一句一個重點、常以陳述/態度收尾。

### R5:debrief 與 hint 用不同 rubric 評同一場,必然打臉
- debrief(`debrief_card.ts`)拿「進度/缺口/卡點/下句/邀約」評結果,
  hint prompt 並沒有被要求 optimize 這些軸——hint 照自己契約走,debrief 照自己 rubric 批。

## 改法設計(五個工作包,全部不碰守門/結算穩定層)

**穩定紅線(不可動)**:`visible_text_guard.ts`、`game_vocab.ts` jargon 轉譯、
單發 v2 settlement/503 誠實路徑、`prompt_sanitizer`、額度結算。
本計畫只動:FSM phase 計算、prompt 組裝、few-shots、debrief 證據注入——全是純函數+測試可覆蓋。

### WP1:Game FSM 改「回合壓力推進」(治 R1,最重要)
- `game_fsm.ts` 新增回合驅動下限:game mode 下,不論分數,
  - user 已發言 ≥2 輪 → phase 至少 P2_VALUE(開始展示/前提)
  - ≥5 輪 → 至少 P3_TEST(測試/賦格)
  - ≥8 輪 → 至少 P4_TENSION
  - (P5 仍由邀約成熟度/軟邀約訊號觸發,不硬推——邀約時機錯了會翻車)
- 分數高可以跳得更快(現行邏輯保留,取 max);partnerMood 惡化(guarded/annoyed)照舊優先降回修復,failures(GREASY 等)照舊蓋過。
- 實作為純函數改動+`game_fsm_test.ts` 補案例:「6 輪瑣事對話、低分」必須落在 ≥P3。
- 注意:debrief 與 hint 共用 `evaluateGameFsm`,此改動自動讓兩邊階段一致(也是 WP5 的地基)。

### WP2:每個 hint = 一個指定戰術動作(治 R2、R3 一半)
- server 依(新)phase 選一個「本輪指定戰術」,以一行注入 gameHint evidence,例:
  - P1:自狀態+感受開球、說話留一半(資訊交換但留懸念)
  - P2:男女前提句(把互動定調成男女交流,不是客服)、生活樣本側面展示、有態度的觀點
  - P3:玩笑式小測試/賦格(釋放標準讓她來靠)、輕推拉
  - P4:張力升溫、角色小劇場(L 級照現有 spicy ladder 管)
  - P5:安全感鋪墊+模糊邀約→速約(照現有速約階梯,最多推一階)
- 同時改 `hintStageGuidance`:game mode 分流,`building_familiarity` 不再輸出「不要直接曖昧」那句,改由 phase 戰術行接管(非 game 模式維持原樣,不影響新手模式)。
- 新增「打破一問一答」硬規則進 `visibleGameHintContract()`:
  「warmUp/steady 兩句中,至多一句以問號收尾;至少一句以陳述、態度或畫面收尾。
  連續兩輪都用問句收尾=查戶口,會被打回。」
  (落地為 prompt 規則即可;是否加 parser 級檢查由實作者評估,加的話走既有
  `rejectBossyPasteableHintReply` 同款軟修復模式,別新增 reject→503 路徑。)

### WP3:few-shot 全面重寫(治 R3)
- 重寫 `GAME_HINT_MOVE_EXAMPLES`:每個 phase 至少一例,句長 15-35 字,多數以陳述收尾。必備新招式:
  - 「自狀態+感受」:『剛收工,腦子只剩一格電,現在只想找人講廢話。』
  - 「說話留一半」:『我的紓壓方式有點怪,講出來怕妳學走。』
  - 「男女前提」:『跟妳聊天有點危險,我本來只打算回一句的。』
  - 「賦格/標準釋放」:『會邊泡腳邊追劇的女生,基本上已經過我第一關了。』
  - 「輕推拉」:『妳品味不錯嘛——雖然選劇眼光還有待觀察。』
  - 既有的「接住測試」「降壓修復」「收成邀約」保留改短。
- 範例必須全過 `visible_text_guard` 詞表(不得含 1.2 原詞),寫完跑 guard 測試確認。

### WP4:字數與語氣壓縮(治 R4)
- `visibleGameHintContract()` 加:「高手句短:warmUp/steady 目標 20-40 字,60 是硬頂不是目標;一句只做一件事,不用『~』與過度熱情語助詞堆疊」。
- coaching 同步壓:先講這輪戰術一句話,再講為什麼,不重複逐字稿。

### WP5:debrief 與 hint 對齊,消滅打臉(治 R5)
- debrief prompt 注入本場 hint 的戰術軌跡(WP2 的「指定戰術」記錄,可掛在既有
  `hint_fact_ledger` 或 game_state 持久化上),要求 debrief:
  - 評語必須對照「教練當時給的路線」——用戶照 hint 做的部分不得反過來批評為缺口;
    要批評就明說「教練這輪保守了,下次可以更早進測試」,把責任放在路線不是用戶。
  - 「下句」建議必須與當前 FSM phase 的戰術一致(共用 `game_vocab.ts` 詞彙,已是單一真相源)。
- 這包動 `debrief_card.ts` prompt 組裝+一條持久化欄位,不動結算。

## 驗收(接棒者必做)

1. 全部 deno 測試綠(`supabase/functions/practice-chat/` 既有測試+新增案例)。
2. Prompt 回歸對拍:對舊基線跑 `deno` 對拍(參照 2026-08-01 批 A 的 prompt 回歸鎖做法),
   確認非 game 模式的 hint prompt 位元組級不變——本計畫不得外溢到新手模式。
3. 離線劇本驗證:拿本次 Nina 逐字稿(嗨→腳痠→泡腳→追劇→劇名)重放,驗新 prompt 下
   第 2-3 個 hint 已出現男女前提/自揭/陳述收尾,而不是第五個問句。
4. Eric 真機同場景重跑 5-hint 流程,主觀驗:像不像高手、debrief 是否還打臉。
5. 守門紅線迴歸:visible_text_guard、503 誠實路徑、額度結算測試全綠,證明穩定層沒被碰。

## 風險與坑(給接棒者)

- **回合推進太激進會油**:WP1 只推到 P4 為止,P5 靠訊號;GREASY/FRAME_COLLAPSE failure 蓋過回合下限——failure 優先序已存在,別重寫。
- few-shot 換血後必跑 `visible_text_guard` 相關測試:範例含「篩選/推拉/框架」原詞會被 jargon 轉譯或 reject(見 `game_vocab.ts` 頭註)。
- `evaluateGameFsm` 是 hint/debrief 共用——改 phase 邏輯兩邊一起變,測試要兩邊都補。
- 全套測試要 `--concurrency=1`(2026-08-07 坑);fresh worktree 先跑 build_runner(client 側無關,本計畫純 Edge,不用)。
- `analyze-chat` 部署 `--no-verify-jwt` 與本計畫無關;practice-chat 走 push 自動 deploy,Edge deploy 522 常見要重跑。
- 男女前提/推拉措辭要留在「輕、玩笑、可撤退」檔位(七步法的表演性人格=社交安全網),spicy ladder L 級守門照舊,絕不繞過。

## 交棒指令建議

新 session 一句話:「照 docs/plans/2026-08-11-game-hint-quality-uplift.md 執行,WP1→WP5 順序做,紅線與驗收照計畫。」
建議執行棒:Codex(有額度)或 grok-codex;R2 級改動,收尾走既有雙審(執行者不自審)。
