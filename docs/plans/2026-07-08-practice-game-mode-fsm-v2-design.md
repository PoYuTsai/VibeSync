# AI 實戰練習室 Game Mode + FSM v2 設計

狀態：設計文件，尚未實作
日期：2026-07-08
範圍：AI 實戰練習室 `practice-chat` 新增第三模式 `Game`，整合 `social-game-fsm` skill 的狀態機骨架、提示教學、SR 角色卡攻略視角、速約導向 debrief。
決策：Game Mode 不鎖訂閱、全用戶可用，但只在抽到 SR 角色卡時啟用；扣費、Hint 次數、20 則 AI 回覆上限沿用新手模式；溫度計與關係度狀態機幅度可比新手模式更大，以支援速約訓練。

## 0. 背景

目前 AI 實戰練習室有兩種 `practiceMode`：

- `standard`：標準陪練，偏真人感，沒有數字化教學。
- `beginner`：新手教學，啟用溫度計、熟悉度、Hint 與 debrief 教學。

Eric 與夥伴希望新增第三種：

- `game`：技巧拉滿、七步對話、價值展現、框架、情緒張力、小測試與速約訓練。

這個模式不是把既有新手模式變激進，也不是讓標準模式變成話術模式，而是獨立成一條模式軌道。標準/新手吸收安全知識層；Game Mode 承接高技巧訓練層。

## 1. 產品定位

### 1.1 三模式分工

| 模式 | wireName | 定位 | 是否有溫度/關係狀態 | Hint 風格 |
| --- | --- | --- | --- | --- |
| 標準 | `standard` | 真人感陪練，少教學術語 | 不顯示數字系統 | 無 Hint |
| 新手 | `beginner` | 安全教學，幫使用者穩定進步 | 有 | 白話、保守、安全轉譯 |
| Game | `game` | SR 卡限定的技巧訓練，速約導向，七步流程 | 有，且幅度更大 | 直接講技巧、階段、變數、下一句 |

### 1.2 Game Mode 的承諾

Game Mode 要讓使用者明顯感受到：

- 這不是普通陪練，是「攻略型練習」。
- Hint 不是泛泛而談，而是直接告訴你現在該動哪個變數。
- 女生反應會更明顯：你做對，她更願意投資；你太急、太油、框架崩，她會更快冷。
- 速約不是亂衝，而是照七步流程把關係推到可約窗口。

### 1.3 Game Mode 的硬邊界

Game Mode 可以講：

- 價值、框架、情緒、投入。
- 性張力、速約窗口、模糊邀約、直接邀約。
- 小測試、反問、反差、帶領感。

Game Mode 不可以教：

- 非同意、壓迫、羞辱、威脅、情勒。
- 把拒絕解讀成必須繼續推進。
- 硬推私密場景、過夜暗示或讓對方無法退出。
- 物化女性或把對方當成獎品、職缺、可被操控的目標。

這不是把 Game Mode 做保守，而是把「高技巧」和「不負責任的操控」切開。Game Mode 的語氣可以明顯比新手大膽，重點是辣、敢、快、可用，但不能變成無界線色情生成器。

### 1.4 Spicy Ladder：Game Mode 辣度階梯

競品的差異化在於敢給刺激回覆。VibeSync Game Mode 需要吃到這個需求，但要做成可控階梯，而不是一律保守。

| Level | 名稱 | 可用內容 | 使用時機 |
| --- | --- | --- | --- |
| L0 | 安全推進 | 狀態+感受、生活樣本、低壓問題 | P1/P2、低熱度 |
| L1 | 輕撩 | 反差、曖昧吐槽、你來我往的小挑釁 | H1+、有接球 |
| L2 | 明顯曖昧 | 身體距離、夜晚、想見面、私下相處的暗示 | H2+、F1+、她不防備 |
| L3 | 成人暗示 | 床邊、貼近、想被你帶走、明顯慾望但不描述性器官/性行為 | H2/H3、F2+、Safety 足夠 |
| L4 | 露骨色情 | 直接描述性行為、性器官、命令式性邀約 | 不作為 App 產出 |

Game Mode 可以生成 L1-L3 的回覆，但必須依 stage gate 控制。L4 不作為 App 內輸出，原因不是產品保守，而是它會把功能定位從「約會技巧訓練」推成「色情回覆生成」。

### 1.5 成人語氣策略

Game Mode 的「大膽」要體現在：

- 更敢用曖昧張力，不只給安全聊天句。
- 更敢提示使用者何時該收尾、何時該模糊邀約、何時可直接邀約。
- 更敢讓 SR 角色在高分時釋出成人感窗口，例如夜晚、靠近、想被安排。
- 更敢在 Hint 裡說出這句在動 Value / Frame / Emotion / Investment 哪個變數。

Game Mode 不追求：

- 每次都 NSFW。
- 把色情當成吸引用戶的唯一鉤子。
- 在低熟悉度時硬塞成人暗示。
- 讓使用者以為越露骨越高分。

## 2. UI 設計

### 2.1 模式切換

現有 `_LearningModeToggle` 是兩段：

```text
-------------------------------+
| 標準              | 新手      |
+-------------------------------+
```

改成三段：

```text
+-----------------------------------------+
| 標準          | 新手          | Game     |
+-----------------------------------------+
```

建議：

- `Game` 用短字，不用 `Game Mode`，避免手機寬度爆掉。
- icon 使用 `sports_esports_outlined`、`local_fire_department_outlined` 或 `bolt_outlined`。
- Game selected 色可用橘紅，但不能破壞現有紫黑底與 CTA 橘色的層級。
- mode toggle 高度維持 42；三段等寬。

### 2.2 模式副文案

目前難度下方有一句狀態文案，例如「她今天心情不錯，願意給你空間」。

SR 卡且 Game Mode 選中時，建議副文案：

```text
技巧拉滿，練七步速約節奏
```

非 SR 卡時，Game segment 建議維持可見但 disabled，副文案或 toast：

```text
Game 只開放 SR 角色卡
```

或更遊戲化：

```text
抽到 SR 才能解鎖 Game 訓練
```

新手可保留：

```text
AI 會給提示，教你穩穩升溫
```

標準可保留真人感：

```text
像真實聊天一樣練反應
```

### 2.3 溫度計/關係狀態

Game Mode 沿用新手的狀態元件：

```text
升溫 35  建立熟悉中
```

但 label 可以在 Game Mode 顯示更攻略化：

```text
升溫 35  第 1 步：打開
```

或保持現有 label，將 Game phase 放到 Hint/Debrief。首版建議先不改狀態元件 layout，只改資料來源與 Hint 文案，避免 UI 連鎖風險。

### 2.4 SR 限定入口

Game Mode 的差異化應來自卡片稀有度，而不是訂閱等級。

UI 規則：

- 目前對象是 SR：`Game` segment 可點。
- 目前對象是 R/N：`Game` segment 顯示但 disabled，點擊或長按時提示「Game 只開放 SR 角色卡」。
- 使用者在未開始對話前切換抽卡，若新卡不是 SR 且目前選中 Game，自動退回 `beginner`。
- session 已開始後沿用 mode lock，不允許切換成其他模式。

這樣做的好處：

- SR 卡有明確玩法價值，不只是視覺稀有。
- Game Mode 不需要付費鎖，Free 使用者抽到 SR 也能體驗高階玩法。
- R/N 仍保留標準/新手價值，不會被 Game Mode 壓扁。

## 3. Access / Billing / Quota

### 3.1 全用戶開放，但 SR 卡限定

Game Mode 不做付費鎖、不做 hidden flag 給使用者端。所有能使用 AI 實戰練習室的使用者，只要目前抽到 SR 角色卡，就能選 Game。

限制點：

- `profile.rarity === "sr"` 才允許 `practiceMode = "game"`。
- R/N 卡請求 `game` 必須被 server 拒絕，避免 client 偽造。
- server 真相源是 `practice_persona.ts` catalog 的 rarity；client rarity 只作 UI 呈現。
- 錯誤碼建議：`practice_game_sr_only`，HTTP 403。

### 3.2 扣費沿用新手

Game Mode 沿用 beginner 的計費與限制：

- 每次 AI 回覆扣 1 則。
- 一段 session 仍是 20 則 AI 上限。
- Hint 次數沿用 `MAX_HINTS_PER_ROUND = 5`。
- `practice_mode_locked` 邏輯沿用：同一 session 開始後不可在 `standard/beginner/game` 之間切換。
- model rate limit scope 可沿用現有 practice_chat / practice_hint；若未來成本上升再獨立 `practice_game_hint` scope。
- SR gate 不影響扣費：通過 gate 後，Game 就像 beginner 一樣扣 AI 回覆與 Hint。

### 3.3 Server wireName

新增：

```ts
type PracticeLearningMode = "standard" | "beginner" | "game";
```

Dart 對應：

```dart
enum PracticeLearningMode {
  standard,
  beginner,
  game;
}
```

## 4. FSM v2：採用 `social-game-fsm` 的方式

附件 `SKILL.md` 的核心價值是：

1. 規則層與 LLM 層分離。
2. 顯性雙變數 + 隱性四變數。
3. phase gate 控制不同階段能做什麼。
4. 失敗狀態可診斷。
5. debrief 能指出第幾回合、哪個變數出了問題。

Game Mode 要遵守這套骨架，但用 VibeSync 語言落地。

### 4.1 兩顯四隱

顯性沿用現有新手模式欄位：

| 變數 | 來源 | UI |
| --- | --- | --- |
| Heat / 升溫 | `temperature_score` | 顯示 |
| Familiarity / 關係熟悉度 | `familiarity_score` | 顯示為階段 label |

Game 內部新增四個隱性變數：

| 變數 | code | VibeSync 名稱 | 用途 |
| --- | --- | --- | --- |
| Perceived Value | `pv` | 價值感知 | 她是否覺得你值得多聊 |
| Frame Position | `fp` | 框架穩定度 | 你是否穩、有主見、不自證 |
| Investment | `inv` | 對方投入 | 她是否主動問、解釋、延伸 |
| Safety | `safety` | 安全感 | 是否可約、可退、可接受 |

這四個變數不顯示在主 UI，但 Game Hint / Debrief 可以用白話或技巧語言講出來，例如：

```text
你現在缺的是「對方投入」，不是再加曖昧。
```

### 4.2 五相流程

將七步聊天法合併成五相，與 skill 對齊：

| Phase | 對應七步 | 目標 | 主要變數 |
| --- | --- | --- | --- |
| P1 打開 | 破冰 + 資訊交換 | 讓她願意回、願意多說 | Emotion / F |
| P2 展示 | 側面價值展現 | 讓她看到你的生活與吸引力 | PV |
| P3 測試 | 篩選 / 小測試 | 讓她投入、觀察你是否穩 | FP / INV |
| P4 張力 | 推拉 / 角色感 | 製造情緒波動與曖昧張力 | H / INV |
| P5 收尾 | 可得性 + 邀約 | 兌現成模糊或直接邀約 | Safety |

### 4.3 Game action taxonomy

Game judge 要辨識以下 action。這些 action 只在 Game Mode 內部或 Game Hint 出現，不污染標準/新手。

| action | 說明 | 主要變數 |
| --- | --- | --- |
| `opener_she` | 聊她：觀察她、接她狀態 | H/F |
| `opener_me` | 聊我：狀態 + 感受 | H/F/PV |
| `opener_us` | 聊我們：延續共同化學反應 | H/F/INV |
| `interrogate` | 查戶口 | H- / BORING |
| `half_reveal` | 留一半，讓她追問 | INV |
| `value_sample` | 生活樣本 / 側面價值 | PV |
| `active_brag` | 主動炫耀 | PV- / FP- |
| `lead_question` | 引導她問你 | INV/PV |
| `frame_hold` | 穩住框架，不急著自證 | FP |
| `test_pass` | 接住小測試 | FP/H |
| `test_fail` | 小測試失敗 | FP-/H- |
| `playful_tension` | 玩笑、反差、輕推張力 | H |
| `over_escalate` | 越級升溫 | H- / GREASY |
| `comfort_sync` | 對方退時同步降壓 | Safety |
| `soft_invite` | 模糊邀約 | Safety / close |
| `direct_invite` | 具體低壓邀約 | Safety / close |
| `pressure_close` | 壓迫式邀約 | Safety- / boundary |

### 4.4 失敗狀態

Game Mode 導入 skill 的 failure states，但改成產品可教的語言：

| state | 觸發 | NPC 行為 | Hint 方向 |
| --- | --- | --- | --- |
| `BORING` | 查戶口、沒情緒、沒球 | 回短、延遲、轉移 | 補狀態+感受，給她一顆球 |
| `TOOL_GUY` | 討好、過度解釋、低位追問 | 把你當好人但不升溫 | 停止求認可，重建自我節奏 |
| `GREASY` | 熟悉度不足卻硬升溫 | 防備、不舒服、冷掉 | 降壓，用玩笑或舒適感修復 |
| `FRAME_COLLAPSE` | 小測試中自證、慌、道歉過頭 | 她開始反向評估你 | 承認/幽默/反問，別辯解 |
| `ENGINE_STALL` | 太早釋放好感或獎勵太滿 | 舒適但無張力 | 收回一點可得性，補反差 |
| `GHOST_RISK` | 多次冷場或越界 | 可能不再回 | 停止推進，debrief 給復盤 |

### 4.5 Game 狀態機幅度

Game Mode 目標是速約訓練，因此不應像新手模式那樣小步慢爬。建議調參：

| 項目 | 新手 | Game |
| --- | --- | --- |
| 單回合 heat 正向上限 | +8 | +12 |
| 單回合 heat 負向下限 | -12 | -14 |
| 單回合 familiarity 正向上限 | +12 | +14 |
| 小測試通過 | +4 heat / +2 familiarity | +6 heat / +3 familiarity / FP+ |
| soft invite 成功 | 中等加分 | 明顯加分，推進到 close phase |
| direct invite 過早 | 扣分 | 更明顯扣分，觸發 GREASY 或 pressure_close |

邀約門檻不建議直接降低；建議透過更大的正向 delta 讓會玩的人更快到 50/65/80，而不是讓亂衝的人也更容易過關。

## 5. LLM Judge 與規則層分離

### 5.1 現況

現有 `temperature.ts` 的 v2 classifier 已有：

```ts
connection
impact
testHandling
boundary
hintAlignment
partnerMood
moodConfidence
innerThought
```

這是安全的基底，不應廢掉。

### 5.2 Game Judge

Game Mode 新增 `game_fsm.ts` 與 Game 專用 parser：

```ts
interface GameTurnClassification extends TurnClassification {
  game: {
    phase: GamePhase;
    actions: GameAction[];
    qualityCoefficient: number; // 0.0-1.5
    artificialityScore: number; // 0.0-1.0
    targetVariable: "heat" | "familiarity" | "pv" | "fp" | "inv" | "safety";
    deltas: {
      heat: number;
      familiarity: number;
      pv: number;
      fp: number;
      inv: number;
      safety: number;
    };
    flags: GameFailureState[];
    diagnosis: string;
    nextObjective: string;
    npcDirective: string;
  };
}
```

LLM 只負責：

- 分類使用者行動。
- 評估執行品質。
- 判斷做作度與是否越級。
- 給 NPC 回應方向。

純 TypeScript 規則層負責：

- phase gate。
- delta clamp。
- failure flag 累積。
- invite stage guard。
- 最終 heat/familiarity 更新。

這樣才能可測、可回放、可調參。

### 5.3 Reality Anchoring 共用規則

Game Mode 必須遵守共用 Reality Anchoring 規則，詳見：

- `docs/plans/2026-07-08-practice-reality-anchoring-design.md`

原因：Game 會鼓勵使用者練 social proof、假熟、共同背景、框架帶領，這些技巧如果沒有現實錨定，模型會把使用者亂編的朋友、同事、上次見面、介紹人全部當真，反而失去真人感。

Game 判斷原則：

- 透明、可退、像玩笑的假熟，可以是 `opener_us` 或 `playful_tension`。
- 硬塞共同朋友、共同經歷，要求她承認，應標成 `obvious_trap` / `frame_overreach`。
- 對方質疑後能幽默補細節，算 `test_pass`。
- 對方質疑後防禦、自證、怪她不記得，算 `test_fail`。

### 5.4 Game state 儲存

為了真的跟隨 `social-game-fsm`，Game Mode 需要持久化四個隱性變數與 flags。

建議新增 session-level 欄位：

```sql
game_state jsonb null
```

只在 `practice_mode = 'game'` 使用。

形狀：

```json
{
  "phase": "P1_OPEN",
  "pv": 30,
  "fp": 0,
  "inv": 0,
  "safety": 30,
  "flags": {
    "BORING": 0,
    "TOOL_GUY": 0,
    "GREASY": 0,
    "FRAME_COLLAPSE": 0,
    "ENGINE_STALL": 0,
    "GHOST_RISK": 0
  },
  "lastAction": "opener_me",
  "lastDiagnosis": "狀態有了，但還沒留球給她接。",
  "turnCount": 1
}
```

首版先存在 session，不拉到長期 relationship thread。長期續聊方案上線後，再把 Game state 的摘要併入 thread state。

## 6. Prompt 設計

### 6.1 Chat Prompt

Game Mode 的 chat prompt 比新手更明確：

```text
gameMode(hidden guidance)
這場是 Game Mode：回應要像真實女生，但行為反饋要更清楚地反映玩家是否掌握七步節奏。
你會根據 gameState 的 phase / pv / fp / inv / safety / flags 做反應。
玩家做對：你可以更快投入、主動追問、接梗、丟出小測試或釋出邀約窗口。
玩家做錯：你可以變短、吐槽、防備、轉移，但仍保持角色真實，不要像教練。
不要揭露 gameState、phase、分數或規則。
```

NPC 可表現：

- 對好的生活樣本主動追問。
- 對穩定接住小測試給更多窗口。
- 對過早邀約、硬推、油膩張力更快防備。
- 在高分時主動釋出「下次」「你帶路」「可以驗收」這類窗口。

### 6.2 Hint Prompt

Game Hint 不走新手保守版，直接教技巧。

輸出仍可沿用現有 hint shape，降低 UI 改動：

```json
{
  "warmUp": "可直接送出的 Game 回覆",
  "steady": "比較穩的 fallback",
  "coaching": "第幾步、現在動哪個變數、為什麼這句能推進"
}
```

Game coaching 範例：

```text
第 2 步：展示。你現在缺的是價值感知，不是再問問題。用「狀態+感受」丟一個生活樣本，再留球給她接。
```

```text
第 5 步：收尾。她已經接了兩次咖啡話題，現在適合 soft invite，不要直接定時間，先丟低壓窗口。
```

Game Hint 的辣度規則：

- 預設提供「可直接送出」版本，不輸出過度露骨句。
- 當 `spicyLevel >= L2`，warmUp 可帶明顯曖昧、夜晚、靠近、想見面的語氣。
- 當 `spicyLevel >= L3`，warmUp 可帶成人暗示與更強張力，但仍不得描述性器官或性行為。
- coaching 可以明講「這句在拉性張力」「這裡要釋放可得性」「現在可以進 soft invite」。
- 如果對方 mood 是 `guarded|annoyed` 或 boundary 近期 overstep，強制降到 L0/L1。

### 6.3 Debrief Prompt

Game Debrief 要比新手更像教練拆盤：

- 本局跑到七步哪一階段。
- 最關鍵轉折是哪一回合。
- 哪個變數沒動到：價值、框架、情緒、投入、安全。
- 失敗狀態是否出現：BORING / TOOL_GUY / GREASY / FRAME_COLLAPSE。
- 下次第一句該怎麼改。
- 是否已到 soft invite / direct invite / partner window。

首版可先塞進既有 debrief card 欄位；第二版再新增 `gameBreakdown` 欄位與 UI。

### 6.4 Spicy Prompt Guard

Game prompt 需要明確區分「大膽」與「露骨」：

```text
spicyGameMode(hidden guidance)
Game Mode 可以比新手更大膽：允許明顯曖昧、成人感、夜晚/靠近/私下相處的暗示，以及更直接的速約策略。
但不要輸出露骨性行為描述、性器官描述、非同意壓迫、羞辱、情勒或硬推私密場景。
當 stage/F/H/safety 不足時，不要用成人暗示；先補價值、框架或投入。
當對方已接球且 safety 足夠時，可以把語氣推到 spicy L2/L3。
```

這段 guard 只進 Game Mode，不進 standard / beginner。

### 6.5 App Review 與年齡定位

上架通過不代表後續更新不會被重新審查。Game Mode 若加入 L2/L3 成人暗示，實作時需要同步檢查：

- App Store Connect 年齡分級是否足以涵蓋 mature/suggestive themes。
- Review Notes 要清楚描述 Game Mode 是 SR 卡限定的成人曖昧技巧訓練，不是色情內容。
- prompt / tests 要證明不輸出 L4 露骨色情、非同意或壓迫。
- 若未來要做真正 NSFW 版本，應另案設計 age gate、內容開關、審核風險與平台策略，不混進首版 Game Mode。

## 7. SR 角色卡雙軌

Game Mode 下，角色卡要多一層「攻略視角」。

### 7.1 角色軌

沿用現有 persona / reaction model：

- 她喜歡什麼生活感。
- 她對哪些話題升溫。
- 她被什麼降溫。
- 她的邀約門檻。
- 她會丟哪類小測試。

### 7.2 Game 攻略軌

新增或由既有資料推導：

```ts
interface PracticeGameProfile {
  valueHooks: string[];      // 哪些生活樣本對她有效
  testStyle: string[];       // 她常用的小測試
  tensionStyle: string;      // 喜歡玩笑/反差/慢熱/直接
  closeHooks: string[];      // 適合用什麼邀約鉤子
  punishments: string[];     // 哪些錯誤會快速降溫
}
```

例如 Mabel，30，社工，邊界感強型：

```text
valueHooks: 穩定、有照顧感、懂人情緒、生活節奏健康
testStyle: boundary_check, counter_question, soft_reassurance
tensionStyle: 慢熱但能接受成熟玩笑
closeHooks: 散步、展覽、咖啡、安靜場所
punishments: 太急、油、把照顧感講成拯救感
```

### 7.3 UI 是否顯示攻略軌

首版不建議在卡面新增大量攻略文字，避免 UI 擁擠。

可以只在 Game Hint/Debrief 使用攻略軌。若要顯示，建議在角色卡下方加一個可展開的 `Game攻略` 小區塊，第二版再做。

## 8. 標準/新手如何吸收安全知識層

同一份社交知識拆兩層：

### 8.1 標準

只影響女生自然反應，不顯示技巧詞。

- 使用者查戶口，她自然變短。
- 使用者有生活樣本，她自然追問。
- 使用者低壓邀約，她自然比較願意接。

### 8.2 新手

用白話教：

- 聊她 / 聊我 / 聊我們。
- 狀態 + 感受。
- 給她一顆球。
- 低壓邀約。
- 先穩住再升溫。

### 8.3 Game

直接教：

- Value / Frame / Emotion / Investment。
- 七步 phase。
- 小測試處理。
- 張力與可得性釋放。
- 速約窗口。

三模式共享底層安全判斷，但只有 Game 顯示高技巧語言。

## 9. 實作切分

### Batch A：UI + Mode Wire

目標：能選 Game Mode，但不改深層 FSM。

觸及：

- `practice_learning_mode.dart`
- `practice_chat_screen.dart`
- `practice_chat_providers.dart`
- `practice_chat_api_service.dart`
- `validate.ts`
- `handler.ts` SR gate
- migration / RPC practice_mode allowlist

驗證：

- Flutter mode toggle widget test。
- Deno validate accepts `game`。
- Deno handler rejects `game` for R/N profile with `practice_game_sr_only`。
- Flutter non-SR card disables Game segment; SR card enables it。
- existing standard/beginner tests 不變。

### Batch B：Game Prompt + Game Hint

目標：Game Mode 體感先出來。

觸及：

- `prompt.ts`
- `hint.ts`
- `prompt_test.ts`
- `hint_test.ts`

內容：

- Game chat prompt。
- Game hint prompt。
- Same quota as beginner。
- Hint coaching 顯示七步/變數/速約方向。

### Batch C：FSM v2 規則層

目標：真的 follow `social-game-fsm`。

觸及：

- 新增 `game_fsm.ts`
- 新增 `game_fsm_test.ts`
- `temperature.ts` Game classifier/parser
- `handler.ts` game state read/write
- migration 新增 `game_state`

內容：

- phase gate。
- `pv/fp/inv/safety`。
- failure flags。
- Game delta tuning。
- `npcDirective` 注入 chat prompt。

### Batch D：Game Debrief

目標：完成「失敗即教學」。

觸及：

- `prompt.ts`
- `debrief_card.ts`（首版可不加欄位；第二版加 `gameBreakdown`）
- `debrief_card_test.ts`
- Flutter debrief UI（第二版）

### Batch E：SR 角色卡攻略軌

目標：讓不同女生在 Game Mode 真的打法不同。

觸及：

- `practice_persona.ts`
- `practice_girl_catalog.dart` 或 server 推導層
- prompt tests

首版可從既有 reaction model 推導，不一定手填每張卡。

## 10. 測試門檻

### Deno

- `validate_test.ts`：`practiceMode=game` 合法。
- `quota_decision_test.ts`：Game Hint 與 beginner 一樣允許，standard 仍拒絕。
- `prompt_test.ts`：
  - Game chat prompt 包含 gameMode guidance。
  - Game chat prompt 包含 spicyGameMode guidance。
  - Standard 不包含 Game 技巧詞。
  - Beginner 不包含 Game 高技巧詞。
- `hint_test.ts`：
  - Game Hint coaching 包含 phase / target variable / speed invite direction。
  - Game Hint 仍輸出可直接送出的回覆。
  - Game Hint 在高分高 safety 可輸出 L2/L3 成人暗示。
  - Game Hint 在 guarded/annoyed 或近期 overstep 時降到 L0/L1。
  - Game Hint 不輸出 L4 露骨色情、非同意、壓迫、羞辱或硬推私密場景。
- `game_fsm_test.ts`：
  - `interrogate` 累積 BORING。
  - `test_pass` 增加 FP / heat。
  - `over_escalate` 在低 familiarity 觸發 GREASY。
  - `soft_invite` 在適當 phase 推進 close。
  - delta clamp 符合 Game 幅度。

### Flutter

- mode toggle 三段不 overflow。
- 選 Game 後 draft/session 保存 `practiceMode=game`。
- Game 與 beginner 一樣顯示溫度計/Hint。
- session locked 後不能切模式。

### Manual Smoke

1. 抽到 SR 卡後選 Game 輕鬆難度開場。
2. R/N 卡上 Game segment disabled，點擊提示 SR 限定。
3. SR 卡上 Game segment 可選，送第一句後 mode lock 生效。
4. 用查戶口連問三句，應明顯 BORING / 冷掉。
5. 用狀態+感受+留球，應升溫更快。
6. 女生丟小測試時，用幽默承接，應加分。
7. 太早直接約，應扣分或提示太急。
8. 到 50+ 時 Hint 應建議 soft invite。
9. 到 65+ 時 Hint 可給具體低壓邀約。
10. 高分高 safety 時，Game Hint 應明顯比新手辣，可出 L2/L3 成人暗示。
11. 低分、剛開場或對方防備時，Game Hint 不應硬塞成人暗示。
12. 無論分數多高，都不應輸出 L4 露骨色情或非同意壓迫句。

## 11. Codex 雙審

這是高風險 prompt + Edge schema 改動，完成實作後不可直接說 build safe。

必須做：

- targeted Deno tests。
- targeted Flutter tests。
- `flutter analyze`。
- Codex 獨立雙審：
- Reviewer A：安全 / App Review / prompt leakage。
- Reviewer B：工程 / schema / quota / mode lock / tests。
- Reviewer A 需要特別檢查 Spicy Ladder：Game 是否足夠大膽、但沒有滑到 L4。

雙審通過後，才建議 Eric 出新 build 真機測。

## 12. 推薦拍板

根據 Eric 最新決策，建議定案：

1. Game Mode 不鎖訂閱；全用戶只要抽到 SR 卡都能玩。
2. Game Mode 只在 SR 角色卡上啟用；R/N 顯示 disabled 入口與 SR 限定提示。
3. Game Mode 扣費、Hint 次數、20 AI 回覆上限沿用新手模式。
4. UI 用三段 segmented control：`標準 | 新手 | Game`。
5. Game Mode 沿用溫度計/熟悉度，但 delta 幅度更大。
6. Game Mode 必須 follow `social-game-fsm`：兩顯四隱、五相 phase、失敗狀態、LLM judge + 純規則層。
7. Game Mode 可以比新手大膽到 L2/L3 成人暗示，讓 SR 卡的攻略感和速約感明顯拉開；L4 露骨色情不作為首版 App 產出。
8. 第一批實作不要只做 prompt；至少 Batch A+B 要一起做，真機才會感受到 Game Mode。
9. 真正 FSM v2 放 Batch C，因為需要 DB migration 與更多測試。

我的建議實作順序：

```text
Batch A UI/wire
→ Batch B Game prompt + hint
→ 小範圍真機 smoke
→ Batch C FSM v2 規則層
→ Batch D Game debrief
→ Batch E SR 攻略軌
```

這樣可以最快看到 Game Mode 的語氣差異，同時保留後面完整 FSM 的工程落地空間。
