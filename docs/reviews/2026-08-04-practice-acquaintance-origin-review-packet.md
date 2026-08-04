# Review Packet：實戰練習室認識管道背景（acquaintance origin）

> 日期：2026-08-04
> 風險：R2（practice-chat AI prompt／現實錨定守門／Hint 事實 ledger／prompt 預算）
> 實作 owner：Claude Code（Opus 5）
> 規格源：無正式 plan 文件；需求＝Eric 口頭「幫 Chat-bots 增加 background knowledge，像是和用戶怎麼認識的，隨機場景」
> 部署授權：**無**。本包只涵蓋 implemented＋tested。Edge deploy／dogfood 需 Eric 另行明示。
> 白話版：`../2026-08-04-practice-acquaintance-origin-plain-summary.md`

---

## Range

- BASE_SHA：`ec13887`
- 審查 range：`ec13887..d444ceb`
- 分支：`claude/ai-chatbot-background-knowledge-nazmr6`（已 push，未開 PR）
- 影響範圍：`supabase/functions/practice-chat/**` 之外**零改動**（無 Flutter、無 migration、無 wire 契約變更、無新 env）

## Commits

1. `d444ceb` 加：實戰練習室陪練女孩補上「你們是怎麼認識的」背景知識（單一 concern）

## Diffstat

```
 supabase/functions/practice-chat/acquaintance_origin.ts      | 277 +++++  (new)
 supabase/functions/practice-chat/acquaintance_origin_test.ts | 138 +++++  (new)
 supabase/functions/practice-chat/handler.ts                  |  19 ++
 supabase/functions/practice-chat/hint.ts                     |  20 +-
 supabase/functions/practice-chat/index_test.ts               |  60 +++++
 supabase/functions/practice-chat/prompt.ts                   |  35 ++-
 supabase/functions/practice-chat/prompt_test.ts              | 110 +++++-
 supabase/functions/practice-chat/visible_text_guard.ts       |   5 +
 supabase/functions/practice-chat/visible_text_guard_test.ts  |  31 +++
 9 files changed, 685 insertions(+), 10 deletions(-)
```

---

## 1. 問題陳述

`practice_persona.ts` 讓陪練女孩對「自己」有完整且穩定的認知（identity／reaction model／signal style／difficulty spec），但對「對方是誰、從哪來」**完全沒有設定**。後果：

- 每一場開場戒心一致，難度只由 persona＋difficulty 決定，缺少真實交友裡最強的變因之一。
- `CHAT_SYSTEM_PROMPT` 的現實錨定（`prompt.ts:209-215`）把「朋友介紹／我們見過」一律當未驗證聲稱，方向正確，但**沒有任何已驗證的關係起點**可以對照，等於所有場景都退化成同一個「純陌生」狀態。

## 2. 設計摘要

新增純資料＋純函式模組 `acquaintance_origin.ts`（零依賴、可 deno test），提供十種認識管道，server 為唯一真相源。

### 2.1 資料形狀（`acquaintance_origin.ts:37-57`）

```ts
interface AcquaintanceOrigin {
  id: AcquaintanceOriginId;      // 十選一 allowlist
  label: string;                 // 「朋友介紹」等可見短標籤
  guardLevel: "low"|"medium"|"high";  // 純資料，不注入 prompt
  sharedFact: string;            // 雙方都知道的既定事實
  stancePrompt: string;          // 她的開場姿態／戒心／投入度
  unverifiedGuard: string;       // 這個管道仍不能自動成立的事
  hintFocus: string;             // Hint 教練用方向
  debriefStandard: string;       // Debrief 評分尺度（不重述管道名）
}
```

十種 id：`friend_intro` / `dating_app` / `street_approach` / `ig_cold_dm` / `nightclub` / `social_gathering` / `campus` / `hobby_class` / `work_encounter` / `travel_trip`。

### 2.2 選擇機制（`acquaintance_origin.ts:243-277`）

```
pool = ACQUAINTANCE_ORIGINS.filter(eligibleFor(girl))      // 永遠非空
seed = `${girl.profileId}|${threadId}|acquaintance-origin`
origin = pool[fnv1a(seed) % pool.length]
```

- `threadId` 取自 `threadIdForPracticeRequest({sessionId, visiblePracticeThreadId})`（`handler.ts:1754-1761`），與 relationship thread 身分同源。
- **無 DB 狀態、無 migration、無 client 欄位**：舊 client 不改版即取得一致背景，與 `life_schedule.ts` 的 sceneContext 同一套 deterministic 推導模式。
- 唯一資格過濾：`campus` 需 `professionId ∈ {college_student, graduate_student}`（`acquaintance_origin.ts:62-65, 172`）。其餘管道全對象開放，合理性交給 prompt 自行詮釋（例：不常跑夜店者以「那天被朋友拉去」帶過，`nightclub.stancePrompt`）。

### 2.3 硬保證（review focus 對照）

| 保證 | 實作位置 |
|------|---------|
| 同一 thread 跨輪、跨 chat/hint/debrief 恆為同一管道 | seed 不含時間／輪次（對比 sceneContext 的 seed 含 isoDate＋dayPart） |
| client 無法指定或覆寫管道 | 無 request 欄位、無 validate 分支；`validate.ts` 未動 |
| 管道不改變扣費／額度／rate limit／session ledger | handler 只新增一個區域常數與四處傳參；所有 gate 未動 |
| 管道不改變 invite 成熟度判定 | 未進 `inviteMaturity` 計算；chat prompt 明寫「不會自動讓你答應邀約」 |
| 選出的管道必在該 profile 候選池內 | `acquaintance_origin_test.ts:93-111` |
| 素材不含真實品牌／店名 | `acquaintance_origin_test.ts:113-131`；`dating_app.stancePrompt` 另有「絕不提到任何真實交友軟體的名字」 |

## 3. 注入點逐一

### 3.1 Chat（`prompt.ts:148-161`，注入點 `prompt.ts:526`）

`acquaintanceOriginPrompt()` 產生六個 bullet，串在 `buildProfilePrompt()` 之後、`sceneContextPrompt()` 之前：

1. `sharedFact` — 既定事實
2. `stancePrompt` — 開場姿態
3. 「這件事是既定背景，你本來就知道，不需要對方證明；但 `unverifiedGuard`」
4. 「對方講的認識過程跟這裡對不上 → **以這裡為準**，你會覺得怪、反問、確認或吐槽，不會順著他改口」
5. 「認識管道只決定你們的起點與你的戒心，**不會自動讓你答應邀約**；約不約得出來仍然照你原本的門檻走」
6. 「還在最前面幾句時，回覆要讓對方感覺得出是從這個管道認識的（帶到一個具體的點就好）」

**位置是刻意的**：排在 `CHAT_SYSTEM_PROMPT` 的現實錨定段之後，靠後段權重＋第 3/4 條的明文優先順序解決兩者的張力。`prompt_test.ts` 有 index 順序斷言鎖住。

### 3.2 Debrief（`prompt.ts:163-171`，注入點 `prompt.ts:825`）

`本場認識管道：${label}。${debriefStandard}\n\n`，接在難度判準之後、生活情境之前。刻意**不含** `sharedFact`（同一份事實走 §3.3 的 shared 證據），避免 Game debrief 12 秒預算被重複敘述吃掉。

### 3.3 Hint（`hint.ts:1131-1139`／`1317-1321`／`1360`）

- `hintTrustedFactualEvidence().shared` 新增 `${label}：${sharedFact}`。理由：認識管道是 **server 給的既定共同背景**，不是使用者聲稱，因此提示／拆解卡引用「你們在哪認識」不該被事實 ledger 判成捏造。
- `buildHintMessages()` 新增 `originEvidence` 區塊（`acquaintanceOrigin` / `originContext` / `originFocus` 三個 key），排在 `sceneEvidence` 之前。

### 3.4 可見輸出守門（`visible_text_guard.ts:19-23`）

三個新注入的 latin 標籤同步進 `INTERNAL_VISIBLE_LABELS`：`acquaintanceorigin`／`origincontext`／`originfocus`。

**刻意使用複合詞**：`normalizeVisibleText()` 會剝除所有非 `[a-z0-9]`，單獨列 `origin` 會誤殺 `original` 這類自然英文。測試同時鎖住正例與反例（`visible_text_guard_test.ts`）。

### 3.5 Telemetry（`handler.ts:3851-3852`）

`practice_chat_succeeded` 增 `acquaintanceOriginId`（allowlisted 常數 id，無使用者內容）。供分佈與跨輪一致性觀測。

## 4. Prompt 預算

實測（`practice_girl_001`／normal）：

| 路徑 | 基準 | 新增（worst case） |
|------|------|------------------|
| Chat system prompt | 3539 字 | +393 ~ +462（最長 `nightclub`） |
| Hint messages | — | +148（最長 `ig_cold_dm`） |
| Debrief user message | — | +65（最長 `social_gathering`） |

既有預算測試上限依實測固定 bytes 調高並註明理由（`prompt_test.ts`）：

- Hint `5400 → 5550`
- Debrief `4500 → 4570`
- Debrief+Hint `6100 → 6170`
- Game Debrief 12 秒預算 `4500 → 4570`

預算測試改為以 `longestHintOrigin` / `longestDebriefOrigin`（依欄位長度排序取第一）自動當 worst case，日後新增更長的管道會自己被抓到，不需人工重挑。Chat prompt 無既有預算天花板測試。

## 5. 安全分析

### 5.1 與現實錨定的互動（本次最需要對抗審的點）

改動前，`CHAT_SYSTEM_PROMPT` 對「我是你朋友介紹的」一律當未驗證。改動後**引入了一個已驗證的關係起點**，必須確保它不成為升級管道。三層防護：

1. **來源隔離**：管道由 server 決定，request 無任何欄位可影響它。使用者無法選、無法翻牌重抽指定場景（重抽會換 thread，但抽到哪個管道不可控）。
2. **範圍最小化**：既定的只有「管道」本身。人名、店名、日期、共同回憶、見過幾次一律留在 `unverifiedGuard` 明文標成未驗證（例：`friend_intro.unverifiedGuard` 明講不會自己補出介紹人的名字或往事）。
3. **衝突判定**：對方描述與 server 管道不符時明文「以這裡為準」，且要求她反問／吐槽而非改口。

### 5.2 不成為難度旁路

`friend_intro` 這類低戒心管道最可能被模型自行外推成「有社交背書 → 可以直接約」。chat prompt 明文切斷：「認識管道只決定你們的起點與你的戒心，不會自動讓你答應邀約；約不約得出來仍然照你原本的門檻走。」`inviteMaturity` 與 persona 的 `inviteThreshold` 完全未動。

### 5.3 內容安全

- `nightclub.stancePrompt` 明文「不會把喝酒當成推進關係的理由，對方拿酒精、續攤或當晚的曖昧當籌碼，你會冷掉」——避免夜店場景被當成灌酒／續攤敘事的入口。既有 L4 守門未動。
- `campus` 只發給 catalog 內的成年學生 profile（`practice_persona.ts` 的 college_student prompt 本身即禁止暗示未成年），不新增任何年齡敘事。
- `ig_cold_dm` 使用平台名「IG」是 Eric 需求原文；catalog 的品牌禁令針對公司／醫院／航空／商品品牌，此處為溝通管道敘述，未提及任何真實帳號、店家或商品。**此判斷請 Codex 覆核。**

## 6. 測試

新增 13 個測試，全套件 **1085 passed / 0 failed**（基準 1072）。

| 檔案 | 新增 | 覆蓋 |
|------|------|------|
| `acquaintance_origin_test.ts` | 7 | 欄位完整性／標籤唯一／thread 內恆定／跨 thread 與跨對象有分佈／campus 資格對稱／選出必在池內／品牌禁詞 |
| `prompt_test.ts` | 4 | chat 注入內容與段落順序、缺席時不注入、debrief 尺度行且不洩標籤、hint 三 key＋shared 可信事實 |
| `index_test.ts` | 1 | handler 端到端：chat prompt 帶到 server 解析的管道、只注入一個管道、同 thread 續聊仍是同一個 |
| `visible_text_guard_test.ts` | 1 | 三個新標籤被攔＋`original`／`origin story` 不誤殺 |

補充實測（非測試檔，手動 probe）：100 位 profile × 20 threads = 2000 次抽樣，九個無限制管道分佈 197~235 次（均勻），`campus` 27 次且全數落在 11 位學生 profile（11×20＝220 次抽樣、10 個候選，期望值約 22）。

### 6.1 驗證環境限制（Codex 請在自己的環境覆核）

本容器**無法連外**取得 `deno.land/std` 與 `jsr.io`（皆 403），因此：

- 測試以本地手寫的 `assert`／`assertEquals` shim 經 import map 替換遠端 std，並以 `--no-check` 執行（shim 的型別簽章比 std 寬，會在 `single_shot_test.ts` 產生假型別錯）。**測試邏輯本身未被修改**，但 Codex 應在能取得 std 的環境重跑一次確認。
- `deno check` 對本次改動的所有原始碼模組（`handler.ts`／`prompt.ts`／`hint.ts`／`acquaintance_origin.ts`／`visible_text_guard.ts`）**通過**。`index.ts` 因遠端依賴無法解析而未能檢查（該檔未改動）。
- `deno lint` 對改動模組通過。`deno fmt` 只套用在兩個新檔；既有檔案本來就不是 fmt-clean（75 檔中 19 檔），未順手重排以免污染 diff。
- 無 Flutter 工具鏈，但本次**零 Dart 改動**，`flutter analyze`／`flutter test` 不適用。

## 7. 未做 / 非目標

- **未新增任何 client 顯示**。使用者目前從她的第一則回覆推斷場景（prompt 第 6 條刻意要求首幾句帶出管道）。要不要在開場卡片顯示「你們是在朋友聚會上認識的」是產品手感決定，需 Eric 拍板，且要動 Flutter＋出新 build。
- **未把管道寫進 `practice_relationship_threads`**。目前靠 deterministic 推導，好處是零 migration、舊 client 相容；代價見 §8 的 Q-3。
- **未觸發 `Build & Distribute`**。本 diff 零 Flutter／iOS 檔案，exact-SHA app build 對此改動不提供任何證據，只消耗 macOS runner 分鐘數。要驗證需要的是 Edge 部署，而 Edge 部署只在 push `main` 時觸發，該落地需 Eric 另行授權。

## 8. 請 Codex 對抗審的問題

**Q-1（現實錨定，最高優先）** §5.1 的三層防護是否足以擋住「使用者用聲稱把 server 管道換掉／擴大」？特別是：當 server 給 `dating_app`、使用者堅持「我們是你朋友 XXX 介紹的」並反覆施壓時，prompt 的「以這裡為準」是否足夠？是否需要把衝突處理寫成更硬的 invariant（例如比照 `memorySummary` 的 `<..._untrusted>` 標記模式）？

**Q-2（邀約旁路）** 「認識管道只決定起點與戒心，不會自動讓你答應邀約」一行是否足以擋住 `friend_intro`／`social_gathering` 這類低戒心管道被模型外推成 invite 綠燈？是否應同步在 `standardInviteMaturityPrompt`／`inviteMaturityPrompt` 補一句明確排除？

**Q-3（deterministic vs 持久化）** 目前管道由 `profileId|threadId` 推導而非落庫。若日後調整 `ACQUAINTANCE_ORIGINS` 陣列順序或增刪管道，**既有進行中的 thread 會改變場景**（她的說法會前後矛盾）。可接受，或應改為 thread 落庫（需 migration）？若維持推導，是否應加一條 source-scan 測試禁止對陣列做順序性修改？

**Q-4（Hint 事實 ledger）** 把 `${label}：${sharedFact}` 放進 `shared` 可信事實是否過寬？例如 `nightclub.sharedFact` 含「夜店或酒吧」，是否可能讓 Hint 產出「那家店」這類具體場所而通過 grounding gate？`hint_fact_ledger.ts` 的 `venue` domain 判定請一併看。

**Q-5（守門詞表）** 三個複合標籤 `acquaintanceorigin`／`origincontext`／`originfocus` 是否足夠？`normalizeVisibleText()` 剝除非 alphanumeric 後，是否有其他可能被抄出的形態（例如模型輸出「認識管道：朋友介紹」這種中文標籤形）需一併列管？

**Q-6（預算）** Game Debrief 的 12 秒預算上限 `4500 → 4570` 是否仍在安全邊界內？實測 worst case 為 +65 bytes，但該路徑同時受 memorySummary、appliedHintTurns 影響，是否有我沒測到的疊加組合？

**Q-7（IG 品牌）** §5.3 對「IG」使用的判斷（溝通管道敘述，非品牌背書）是否成立？若不成立，改用「社群私訊」是否會弱化 Eric 要的場景辨識度？

**Q-8（`campus` 資格）** 只放行 `college_student`／`graduate_student` 是否過窄？`language_tutor`（語言家教）等場域相鄰職業是否也該納入？納入會提高 campus 出現率（目前 100 位中僅 11 位有此候選）。
