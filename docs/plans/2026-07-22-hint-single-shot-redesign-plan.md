# 練習室 Hint＋Debrief 單發重設計（single-shot v2）實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> 設計真相源：`docs/plans/2026-07-22-hint-single-shot-redesign-design.md`（先讀它，本計畫不重複裁決理由）。

**Goal:** hint（新手＋Game）＋debrief 全改 Claude Sonnet 5 單發＋tool_use 強制 schema＋機械守門，敗一次補發 Haiku 4.5，砍掉 DeepSeek 生成與 semantic reviewer 整層。

**Architecture:** 新增共用 `single_shot.ts`（兩發 failover＋死線夾擠），handler.ts 的 hint／debrief 生成迴圈整段換成單發路徑；機械守門（parser 硬 gate、visible_text_guard、practice_visible_quality、hint_fact_ledger、repair）與 prefetch claim/settle/discard 語意原封保留；`semantic_quality.ts`（3345 行）整檔刪除。聊天本體（chat mode）、draw_profile、`game_fsm.ts` 一律不動。

**Tech Stack:** Supabase Edge Function（Deno）、Anthropic Messages API（tool_use forced schema）、Flutter client（只改一處等待文案）。

**紀律：**
- 直接 main 做（全內測，出事 git revert）。每個 Batch 測試綠才 commit，commit 後立即 push。
- 測試指令（CI 不跑 practice-chat 測試，一律本機跑）：
  `deno test --allow-env --allow-read supabase/functions/practice-chat/`
- 收尾順序鐵則：Batch H 四路黑箱 eval 三軸全綠 → Batch I Codex 雙審（高風險：AI prompt/token/cost）APPROVED → 才可宣稱 dogfood safe、才輪到 Eric 真機測。

**關鍵地圖（勘查於 2026-07-22，行號以當時 HEAD=da7f57bb 為準，動手前重新 grep 校準）：**

| 東西 | 位置 |
|------|------|
| hint 生成主迴圈 | `handler.ts:2870-3300`（DeepSeek 3142、semantic 3022、Claude failover 3201-3262、salvage 2943/3078/3281） |
| debrief 生成迴圈 | `handler.ts:3855-4100`（semantic 3996、DeepSeek 4090、salvage 3921/4054） |
| 常數群 | `handler.ts:128-176`（`HINT_REQUEST_DEADLINE_MS=105000`:148、`HINT_PROVIDER_CALL_BUDGET=11`:161、`HINT_TIMEOUT_MS=24000`:174、`HINT_MAX_TOKENS=1600`:152、`DEBRIEF_TIMEOUT_MS=18000`:139、`DEBRIEF_REQUEST_DEADLINE_MS=85000`:170、`DEBRIEF_IN_FLIGHT_STALE_MS=105000`:144、`DEBRIEF_MAX_TOKENS=1200`:131） |
| Claude caller | `claude.ts:42` `callClaude`；model 常數 `CLAUDE_HAIKU_MODEL="claude-haiku-4-5-20251001"`:5、`CLAUDE_SONNET_MODEL="claude-sonnet-5"`:6；`outputJsonSchema`（output_config 路徑，72-80）**全 repo 零使用＝未經 prod 驗證，不採用** |
| hint prompt／parser | `hint.ts:1239-1360` `buildHintMessages`；`hint.ts:2299` `parseHintResult`；repair `repairGameVisibleLabels`:180、`repairChineseJargon`:251（hint.ts 私有） |
| debrief prompt／parser | `prompt.ts:716-729` `buildDebriefMessages`（**與 chat 的 buildChatMessages 同檔，勿波及 chat**）；`debrief_card.ts:1606` `parseDebriefCard` |
| reviewer | `semantic_quality.ts`（3345 行）；生產 import 只有 `index.ts:5,20`；handler 靠型別 `PracticeSemanticAdjudicator`（handler.ts:121,611）注入 |
| `deferVisibleGuardsToSemantic` | `hint.ts:140,1410,2216`；`handler.ts:2996,3940`；`debrief_card.ts` parseDebriefCard opts |
| telemetry | `telemetry.ts:244-284` `buildPracticeAiLogRow`（pipeline 標記加在 request_body）；`classifyPracticeGenerationFailure`:282；ai_logs insert `handler.ts:661` |
| prefetch | 與冷路徑同一迴圈，`requestIsPrefetch` 分流（handler.ts:2255）；RPC `claim/settle/discard`（handler.ts:893-897、2354、2426）；`hint_prefetch.ts` 只有決策/telemetry helper |
| client 等待文案 | `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart:1741-1747`（渲染 1849） |
| 迴圈行為測試 | `index_test.ts`（mock `callDeepSeek`/`callClaude`/`semanticAdjudicate`，708-769） |

---

## Batch A — 單發核心引擎（共用，先做因為 hint/debrief 都靠它）

### Task A1: claude.ts 加 tool_use 強制 schema 支援

**Files:**
- Modify: `supabase/functions/practice-chat/claude.ts`
- Test: `supabase/functions/practice-chat/claude_test.ts`

**Step 1: 寫失敗測試**（claude_test.ts 既有測試怎麼 mock fetch 就照抄同款）：
- 傳 `forcedTool: { name: "emit_hint", inputSchema: {...} }` 時，request body 含 `tools:[{name,input_schema}]` 與 `tool_choice:{type:"tool",name:"emit_hint"}`。
- 回應 content 含 `{type:"tool_use", input:{...}}` 時，`callClaude` 回傳 `JSON.stringify(input)`（讓下游 parser 沿用「收字串」契約）。
- 回應沒有 tool_use block → throw `claude_no_tool_use`。
- 未傳 `forcedTool` 時行為 byte-for-byte 不變（chat failover、temperature judge 還在用純文字路徑）。

**Step 2: 跑測試確認 FAIL**
`deno test --allow-env --allow-read supabase/functions/practice-chat/claude_test.ts`

**Step 3: 實作**——`ClaudeArgs` 加選填 `forcedTool?: { name: string; description?: string; inputSchema: Record<string, unknown> }`；有傳時組 `tools`＋`tool_choice`，回應取第一個 `tool_use` block 的 `input` 序列化回傳。逾時/abort/錯誤處理沿用現有路徑不動。Sonnet-5 的 `thinking:disabled`／temperature 分支（47-60）不動。

**Step 4: 跑測試 PASS → Step 5: Commit**
`git commit -m "claude.ts 支援 tool_use 強制 schema（單發重設計基座）"` → push

### Task A2: 新增 single_shot.ts 兩發 failover 引擎

**Files:**
- Create: `supabase/functions/practice-chat/single_shot.ts`
- Test: `supabase/functions/practice-chat/single_shot_test.ts`

**介面（TDD，用 fake callClaude）：**

```ts
export interface SingleShotAttemptFailure {
  model: string;
  code: string;          // "claude_timeout" | "claude_http_5xx" | "gate:<reason>" | ...
  durationMs: number;
}
export interface SingleShotArgs<T> {
  callClaude: ClaudeCaller;               // 依賴注入，handler deps 同款
  apiKey: string;
  messages: ChatMessage[];
  forcedTool: { name: string; description?: string; inputSchema: Record<string, unknown> };
  maxTokens: number;
  perCallTimeoutMs: number;               // hint 15000 / debrief 20000
  deadlineAtMs: number;                   // 請求絕對死線（epoch ms）
  now: () => number;                      // 注入時鐘（測死線夾擠用）
  models: [string, string];               // [CLAUDE_SONNET_MODEL, CLAUDE_HAIKU_MODEL]
  validate: (raw: string, model: string) => T;  // 丟 Error = gate 不過（含 parser/守門）
}
export interface SingleShotOutcome<T> { result: T; model: string; attemptFailures: SingleShotAttemptFailure[]; }
export async function runSingleShot<T>(args: SingleShotArgs<T>): Promise<SingleShotOutcome<T>>
```

**行為（各寫一條測試，先 FAIL 再實作）：**
1. 第 1 發 models[0]（Sonnet）成功且 `validate` 過 → 回傳，attemptFailures 空。
2. 第 1 發丟錯（逾時/HTTP/gate）→ **立即**第 2 發 models[1]（Haiku），不 repair 不重試同模型；成功 → 回傳，attemptFailures 記第 1 發。
3. 兩發皆敗 → throw `SingleShotExhaustedError`（帶兩筆 attemptFailures，供 503 分類）。
4. 死線夾擠：每發實際 timeout = `min(perCallTimeoutMs, deadlineAtMs - now() - 1000)`；剩餘 < 3000ms → 該發不打直接記 `deadline_exhausted` 失敗。
5. unsafe/gate 不過的候選文字**絕不**出現在錯誤物件裡（只留 code，不留原文——沿用「unsafe 候選一律丟棄」鐵則）。

**Commit:** `git commit -m "新增 single_shot 兩發 failover 引擎（Sonnet 5→Haiku 4.5＋死線夾擠）"` → push

---

## Batch B — hint 切換單發（新手＋Game 同一條路）

### Task B1: 定義 hint tool schema

**Files:**
- Modify: `supabase/functions/practice-chat/hint.ts`（新增 export）
- Test: `supabase/functions/practice-chat/hint_test.ts`（加一小節）

先讀 `hint.ts:2299` `parseHintResult` 全函式，以 parser 期望為權威定義 `HINT_TOOL_SCHEMA`：top-level 必含 `replies`（array，minItems 2 maxItems 2，元素含 parser 要求的必填欄位）＋`coaching`；**Game 模式若 parser 期望額外欄位（對照 `PracticeHintResult`:96 與 game 分支），schema 用選填欄位涵蓋，不做兩套 schema**。原則：schema 管結構（合法 JSON＋必填鍵＋長度上限），parser 仍是硬 gate 權威——schema 寬、parser 嚴，兩者衝突以 parser 為準。
測試：構造一個過 parser 的合法 JSON，斷言它同時滿足 schema 必填鍵（防 schema 跟 parser 打架）。

### Task B2: index_test.ts 先寫 hint 單發行為測試（FAIL）

**Files:**
- Modify: `supabase/functions/practice-chat/index_test.ts`

沿用既有 mock 注入法（708-769），新增測試組（新手與 Game 模式各覆蓋）：
1. hint 請求只打 `callClaude`，第一發 model=`claude-sonnet-5`、`forcedTool` 有帶、maxTokens=500；**`callDeepSeek` 零呼叫、`semanticAdjudicate` 零呼叫**。
2. 第一發丟 `claude_timeout` → 第二發 model=`claude-haiku-4-5-20251001`；成功回傳 contract 形狀不變（`PracticeHintResult { replies[2], coaching }` 逐欄）。
3. 兩發皆敗 → 503，ai_logs row 的 failureClasses 走 `classifyPracticeGenerationFailure`，request_body 含 `pipeline:"single_shot_v2"`。
4. 機械守門仍生效：回傳含內部標籤/L4 詞 → 該發判敗進第二發（不是 repair 復活）。
5. Game 模式：`repairGameVisibleLabels`／`repairChineseJargon` 白話轉換仍套用（構造含「推拉」的回傳，斷言可見文字已轉換）；gameHintEvidence／`hint_fact_ledger` 事實接地仍擋亂編。
6. prefetch 請求：走同一單發路徑；成功 → settle RPC 被呼叫；失敗 → discard 被呼叫且**絕不落 fallback 快照**；requestId 冪等測試照舊全綠。

### Task B3: handler.ts hint 迴圈整段換成單發

**Files:**
- Modify: `supabase/functions/practice-chat/handler.ts:2870-3300`（整段重寫）＋常數區

改法：
- 常數：`HINT_REQUEST_DEADLINE_MS` 105000→**35000**；新增 `HINT_SINGLE_SHOT_TIMEOUT_MS=15000`；`HINT_MAX_TOKENS` 1600→**500**；刪 `HINT_TIMEOUT_MS`、`HINT_PROVIDER_CALL_BUDGET`。
- 迴圈換成：`buildHintMessages(...)`（原樣）→ `runSingleShot({ validate: raw => 既有 parser＋repair＋visible_text_guard＋practice_visible_quality＋hint_fact_ledger 全套 })` → 過 → 回傳。
- 刪：DeepSeek 呼叫、semanticAdjudicate 呼叫、`salvageHintCandidate`／`bestGatePassingHint` 全部、`deferVisibleGuardsToSemantic:true` 設定點（handler.ts:2996）。
- **prefetch 分流保留**：`requestIsPrefetch` 只影響 claim/settle/discard 與扣費語意；生成路徑與冷路徑同一條（設計拍板：同管線同模型）。salvage 已整個不存在，原「salvage 對 prefetch 停用」條件隨之消失。
- 503 路徑：`SingleShotExhaustedError` → 既有 503 組裝＋`classifyPracticeGenerationFailure`（handler.ts:3176,3255,3297 一帶收斂成一處）。

**Step: 跑 B2 測試至 PASS；再跑既有 hint 全部測試**：
`deno test --allow-env --allow-read supabase/functions/practice-chat/`（此時 debrief／semantic 舊測試仍在跑舊路徑，預期仍綠；只有斷言「hint 走 DeepSeek/reviewer」的舊測試會 FAIL——逐條改寫成單發語意，**不得為過測試回加舊路徑**）。

### Task B4: hint.ts 拆 deferVisibleGuardsToSemantic

**Files:** Modify: `supabase/functions/practice-chat/hint.ts:140,1410,2216`

拔掉旗標欄位與分支，守門一律即時 enforce。跑 hint_test.ts 全綠。

**Batch B Commit（可拆 2-3 個 commit：schema／測試＋迴圈／旗標）**，訊息例：`hint 生成改 Sonnet 5 單發＋tool_use schema，砍 DeepSeek/reviewer/salvage 路徑` → push

---

## Batch C — debrief 切換單發（含 Game breakdown 契約）

### Task C1: debrief tool schema

**Files:**
- Modify: `supabase/functions/practice-chat/debrief_card.ts`（新增 export `DEBRIEF_TOOL_SCHEMA`）
- Test: `supabase/functions/practice-chat/debrief_card_test.ts`（加一小節）

以 `parseDebriefCard`（debrief_card.ts:1606 起）為權威：必填 `summary`、`suggestedLine`、`strengths[]`、`watchouts[]`、`vibe`、`dateChance`、`dateChanceReason`；Game breakdown 欄位（`allowGameBreakdown` 分支讀的鍵）做**選填**。同 B1 原則：schema 寬、parser 嚴。測試同 B1 款（合法卡過 schema 必填鍵）。

### Task C2: index_test.ts debrief 單發行為測試（FAIL）

同 B2 六條款式，換 debrief 語境：Sonnet→Haiku 順序、maxTokens=1200、零 DeepSeek 零 semantic、503 分類＋pipeline 標記、守門生效、**Game 模式 debrief 的 breakdown 欄位契約逐欄不變**（舊 client 免升級）。debrief 無 prefetch，免測 claim/settle。

### Task C3: handler.ts debrief 迴圈換單發

**Files:** Modify: `supabase/functions/practice-chat/handler.ts:3855-4100`＋常數區

- 常數：`DEBRIEF_REQUEST_DEADLINE_MS` 85000→**45000**；新增 `DEBRIEF_SINGLE_SHOT_TIMEOUT_MS=20000`；刪 `DEBRIEF_TIMEOUT_MS`；`DEBRIEF_MAX_TOKENS=1200` 不動；`DEBRIEF_IN_FLIGHT_STALE_MS` 105000→**60000**（新死線 45s＋緩衝；防 crash 的 in-flight 標記卡使用者 105 秒）。
- 迴圈：`buildDebriefMessages`（原樣，**prompt.ts 是 chat 共用檔，只讀不改**）→ `runSingleShot` → `parseDebriefCard`＋守門。刪 semantic 呼叫（3996）、`salvageDebriefCandidate`／`bestGatePassingDebrief`、`deferVisibleGuardsToSemantic:true`（3940）。
- `buildFallbackDebriefCard`（debrief_card.ts:202）：查呼叫處——若只服務舊 salvage 路徑則一併刪；若別處（如歷史卡回讀）還用就留。

### Task C4: parseDebriefCard 拆 semantic 旗標

**Files:** Modify: `supabase/functions/practice-chat/debrief_card.ts`

拔 opts：`semanticAdjudicated`、`deferHintAssessmentToSemantic`、`deferVisibleGuardsToSemantic`；`guardVisibleText` 的 defer 參數移除、一律即時 enforce。改完跑 debrief_card_test.ts，斷言舊旗標行為的測試改寫成一律 enforce 語意。

**Batch C Commit** → push

---

## Batch D — reviewer 整層拆除

### Task D1: 刪 semantic_quality.ts 與注入點

**Files:**
- Delete: `supabase/functions/practice-chat/semantic_quality.ts`（3345 行）
- Delete: `supabase/functions/practice-chat/semantic_quality_test.ts`（全綁 `adjudicatePracticeCandidate`）
- Modify: `supabase/functions/practice-chat/index.ts:5,20`（拔 import＋`semanticAdjudicate` 注入）
- Modify: `supabase/functions/practice-chat/handler.ts:121,611`（拔 `PracticeSemanticAdjudicator` 型別與 deps 欄位）
- Modify: `supabase/functions/practice-chat/index_test.ts:25-26,727,731`（拔 mock 注入與 import）

**動刀前先跑**：`grep -rn "semantic_quality\|adjudicatePracticeCandidate\|PracticeSemanticAdjudicator\|semanticAdjudicate" supabase/ lib/ --include="*.ts" --include="*.dart"`——清單以 grep 結果為準，上表行號僅供定位。

### Task D2: migration／schema-version 測試逐檔判定（別順手刪）

- `practice_hint_review_schema_migration_test.ts`、`hint_quality_schema_migration_test.ts`、`practice_semantic_owner_window_migration_test.ts`：這些是**釘死歷史 SQL migration 字串**的測試。判準：只要它 import 的是 migration SQL／`hint_prefetch.ts` 常數而非 `semantic_quality.ts`，**留下**（migration 是歷史事實，不隨 reviewer 死）。
- `HINT_QUALITY_SCHEMA_VERSION`／`HINT_REVIEW_SCHEMA_VERSION`（hint_prefetch.ts:6-7）與 settle RPC payload：**本案不改**——RPC 契約與 DB 欄位原封，值照舊寫入（管線世代改由 telemetry `pipeline` 標記區分）。改版本字串會連動 migration＋RPC SQL，超出本案範圍。

### Task D3: 全量回歸

```
deno test --allow-env --allow-read supabase/functions/practice-chat/
flutter analyze   # release gate＝全 repo 0 warning
```
**Commit:** `拆除 semantic reviewer 整層（semantic_quality.ts −3345 行）` → push

---

## Batch E — PUA／情緒勒索禁令拆除（逐項，Eric 拍板 2026-07-22）

### Task E1: prompt 條款逐項拆（只動 hint／debrief，chat 絕不動）

**Files:** Modify: `supabase/functions/practice-chat/hint.ts:1174,1301`；`prompt.ts` 只在確認條款屬 `buildDebriefMessages` 專用段時才動

逐項歸屬（**移除＝PUA/情勒類；保留＝硬安全類，兩類混在同一句時拆句改寫，絕不整句刪**）：
- 移除：「PUA」「製造罪惡感」「操控」「貶低」「打壓」「羞辱」（negging 類）等字面禁令。
- 保留：「性壓力」「私密施壓」「強迫邀約」「威脅」（L4 硬安全鄰接類）。
- `prompt.ts:197`「禁 PUA、攻略、收割、控制」——先讀上下文確認歸屬：屬 chat prompt（`buildChatMessages`）→ **不動**（chat 不在本案範圍）；屬 debrief 專段才拆。

### Task E2: 機械守門詞表逐項 audit（預期零移除，audit 結論寫進 commit message）

**Files:** Read-only audit: `supabase/functions/practice-chat/visible_text_guard.ts`＋`hint.ts:247-266`

判準：PUA 拆的是「禁止產出 PUA『行為』的內容規則」；守門詞表擋的是「內部術語洩漏到可見文字」與「硬安全」，是**被保留的類別**：
- `INTERNAL_VISIBLE_LABELS`（1-66）＝內部標籤防洩漏 → 保留。
- `L4_UNSAFE_VISIBLE_PATTERNS`（68-122）＝性/脅迫硬安全 → 保留。
- `INTERNAL_TEMPERATURE_LABELS_LATIN`（129-139）＝溫度機制防洩漏 → 保留。
- `INTERNAL_MECHANISM_PHRASES`（143-153，升溫指數/篩選/推拉/可得性/賦格/框架）＝**術語洩漏類而非 PUA 行為禁令** → 保留（拆掉會讓 jargon 直接漏給使用者）。
- `repairChineseJargon` 白話轉換表（hint.ts:247-266，推拉→輕鬆張力等）＝洩漏白話化 → 保留。

若 audit 發現確屬「禁止 PUA 行為內容」的守門項（目前勘查認定沒有），才移除該單項並補測試。

**Step: 跑 hint／debrief prompt 相關測試**——斷言禁令字樣存在的測試同步改。
**Commit:** `拆 hint/debrief prompt PUA／情勒禁令（Eric 拍板承擔）；守門詞表 audit 零移除` → push

---

## Batch F — telemetry 標記＋client 文案

### Task F1: pipeline 標記

**Files:**
- Modify: `supabase/functions/practice-chat/telemetry.ts`（`buildPracticeAiLogRow` 279-284 的 request_body 物件加 `pipeline: "single_shot_v2"`；由呼叫端傳入，hint／debrief 兩處都帶）
- Test: `supabase/functions/practice-chat/telemetry_test.ts`（若無此檔就在 index_test.ts 斷言，B2/C2 已含）

不動 ai_logs 表 schema、不動 `request_type` 格式（migration 測試釘著）。

### Task F2: client 等待文案對齊新管線

**Files:**
- Modify: `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart:1741-1747`

新分段（秒數門檻 8/25 → **8/20**）：
- `<8s`：「教練正在讀你們最後幾句…」（不變）
- `8-20s`：「正在想兩種回法…」
- `≥20s`：「快好了，正在做最後檢查…」（**移除「品質雙重複核」字樣——reviewer 已拆，文案不得說謊**）

跑該 screen 既有 widget test（若有斷言文案的測試同步改）＋`flutter analyze`。
**Commit:**（telemetry＋client 可同 commit 或拆二）→ push

---

## Batch G — docs 同步＋總回歸

### Task G1: 文件同步（policy change 必帶 docs）

**Files:**
- Modify: `CLAUDE.md`＋`AGENTS.md`（**byte-for-byte 同步**）——Models 段「Practice stays DeepSeek-first with its existing tiered Claude failover/reviewer」改為：練習聊天本體 DeepSeek 不變；hint／debrief 改 Sonnet 5 單發＋Haiku 4.5 第二發，reviewer 已拆除。
- Modify: `docs/snapshot.md`（現況一句話＋指到設計檔）

### Task G2: 總回歸

```
deno test --allow-env --allow-read supabase/functions/practice-chat/
flutter analyze          # 0 warning（release gate）
flutter test test/features/practice_chat/   # 若該路徑存在；否則跑受影響最近測試
```
全綠才進 Batch H。**Commit＋push**（push 即自動部署 practice-chat Edge Function——確認測試全綠才 push）。

---

## Batch H — 四路黑箱 eval（Codex 雙審前必跑，Eric 拍板 2026-07-22）

> 目的：不看程式碼、只打真管線，用「穩定度／速度秒數／風險品質」三軸驗收四條路——新手 hint／Game hint／新手 debrief／Game debrief。這是 dogfood 前的量化 gate；Codex 雙審附上報告當證據。

### Task H1: eval 腳本＋fixtures

**Files:**
- Create: `tools/practice_single_shot_eval/run_eval.ts`（Deno 腳本，直接 import practice-chat 的生成入口＋真 `CLAUDE_API_KEY`，比照先前難度重設計 bakeoff／503 案離線 eval 的做法）
- Create: `tools/practice_single_shot_eval/fixtures/`（四路各 5 組真實感對話 fixture：新手短對話、Game 各 FSM 階段含 gameHintEvidence、debrief 用整場逐字稿；Game debrief fixture 必含會觸發 breakdown 的完整局）
- Create: `tools/practice_single_shot_eval/README.md`（跑法一行：`deno run --allow-env --allow-net --allow-read run_eval.ts`）

腳本行為：每路 fixture × 4 次重複 = 每路 20 發（四路共 80 發，成本約 US$1-2，Eric 已拍板不省）；逐發記錄：路徑、首發/次發/503、耗時 ms、gate 打回原因（若有）、served 文字。**絕不**打 prod Edge Function（本機直呼生成函式，不碰 prod 扣費/ledger）。

### Task H2: 三軸驗收 gate（任一紅 → 回去修，不進 Codex 雙審）

**速度（秒數 benchmark，對齊設計目標）＋穩定度：**

| 路徑 | p50 目標 | p90 目標 | 穩定度 gate |
|------|---------|---------|-------------|
| 新手 hint | 5-8s | ≤15s | 首發成功 ≥95%；20 發 0×503 |
| Game hint | 5-8s | ≤15s | 同上；gate 打回率另記（預期略高於新手，非結構性差異） |
| 新手 debrief | 8-12s | ≤20s | 首發成功 ≥95%；0×503；max_tokens 截斷 0 |
| Game debrief | 10-15s | ≤20s | 同上（四路最慢＝正常；超標才是問題） |

**風險品質（自動＋人工）：**
- 自動：80 發 served 文字全量掃 `INTERNAL_VISIBLE_LABELS`／`L4_UNSAFE_VISIBLE_PATTERNS`／`INTERNAL_MECHANISM_PHRASES` 詞表——**0 洩漏**（gate 理論上擋了，這裡驗 end-to-end 沒縫）；debrief 事實接地抽 5 發人工比對逐字稿無腦補。
- 人工目檢重點（reviewer 拆掉後最裸排序：**Game hint > debrief > 新手 hint**）：Game hint 取 10 樣本，逐一看「這步棋跟 FSM 現階段合不合理」——機械 gate 驗不了策略合理性，這是唯一靠眼睛的縫。

### Task H3: 報告落檔

**Files:** Create: `docs/reviews/2026-07-22-single-shot-eval.md` — 三軸結果表＋Game hint 10 樣本原文＋結論（PASS/FAIL 逐 gate）。Commit＋push（eval 工具與報告一起進 repo）。

---

## Batch I — Codex review（高風險：AI prompt/cost/安全守門）

用 `codex:rescue` 直呼雙審，**附 Batch H eval 報告當證據**，重點審：
1. 單發 validate 閉包是否涵蓋舊路徑全部機械守門（漏一個 gate＝品質裸奔）。
2. prefetch claim/settle/discard 與扣費語意是否原封（消費才扣、失敗絕不落快照）。
3. PUA 拆除是否精準（硬安全條款不得被順刪）。
4. max_tokens 500 截斷風險（opener 502 前科：MAX_TOKENS 截斷）——tool_use input 被截斷會 JSON 壞掉進第二發，需確認 failure class 可觀測。
5. contract 逐欄不變（舊 client 免升級）。

**APPROVED 才可宣稱 dogfood safe。** verdict 留給 Eric：真機 dogfood 重點盯 Game hint 品質（reviewer 拆掉後最裸的縫）＋ai_logs 盯 p50/p90/失敗率（`pipeline:"single_shot_v2"` 對比）。

---

## 上線後觀測（不屬實作，列著別忘）

- ai_logs 查詢按 `request_body->>'pipeline'` 分組對比新舊 p50/p90/失敗率。
- 若 hint 出現 max_tokens 截斷 failure class 聚集 → 開小案調 500→700，不回加重試層。
- `DEBRIEF_IN_FLIGHT_STALE_MS` 60s 若造成重複生成 → 回 105s（一行 revert）。

## 明確不做（本案範圍鐵絲網）

- chat 本體（DeepSeek、L4 chat 守門 handler.ts:4555）、draw_profile、`game_fsm.ts`：一行不動。
- schema version 字串（`semantic-quality-v2`／`dual-semantic-assessment-v1`）與 settle RPC 契約：不動。
- client 等待窗機制、debrief 等待畫面：不動（只改 F2 那一處文案）。
- prompt few-shot／Game-新手分岔內容：不動（品質責任移回 prompt，但 prompt 本體只拆 PUA 條款）。
