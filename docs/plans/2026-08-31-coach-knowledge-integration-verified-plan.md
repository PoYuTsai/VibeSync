# 問教練知識導入：規格驗證結果與修正後實作計畫

> 驗證基線：本機 `main` HEAD `372deec4`（coach-chat 相關檔與 `c7292848` 相同；B1/B2 只動 admin-dashboard）
> 驗證對象：《VibeSync「問教練」魅力知識全面導入規格》（spec sha256 `3460ea69…`）＋《魅力聊天核心知識庫》
> Durable work：`w-0218d329-2eb2-4230-912b-6684ef36501f`（R2，knowledge sentinel 已綁 snapshot）
> 本文只做驗證與計畫；未改任何 runtime code。

---

## 1. 規格書六大根因逐條驗證結果

| # | 規格書主張 | 驗證結果 | 證據 |
|---|---|---|---|
| 3.1 | Coach 與 Analyze Chat 是知識孤島；Coach 只拿簡化 snapshot | **屬實** | `coach-chat/prompts.ts` 獨立 `SYSTEM_PROMPT_BASE`；`schemas.ts:78-85` AnalysisSnapshot 只有 heatScore/stage/summary/nextStep/coachActionType/keySignals；`analyze-chat/analyze_prompt/` 的 reasoning_core／conversation_policy／reply_voice 未被 coach 引用 |
| 3.2 | Partner scope 沒有逐字對話仍可產個案戰術 | **屬實** | `coach_chat_providers.dart:193-258`：partner scope 下 `conversation=null` → `recentMessages=[]`、`conversationSummary=null`、`analysisSnapshot=null`，只送 partnerHint＋風格＋outcome digest |
| 3.3 | 釐清強制閘門只保護 global scope | **屬實** | `clarification_policy.ts:21-31` `mustClarifyFirstRound` 硬綁 `scope.type === "global"`；partner/conversation 零證據也不會被擋 |
| 3.4 | 輸出契約把「寫一句」放在決策之前 | **部分屬實，需修正** | Schema 已允許 `suggestedLine=null`＋`rewriteDecision="do_not_send"`（`schemas.ts:196-197`），prompt 也寫「不適合傳訊息時用 null」。真正缺的是：(a) 沒有伺服器端 deterministic 決策層，「要不要傳」全靠模型當輪心情；(b) fallback 永遠產一句罐頭（`generation.ts:653-655`）；(c) UI 沒有「這輪先別傳」的正式狀態呈現（`coach_surface.dart:935-956` 只有有句/無句兩態） |
| 3.5 | Validator 只驗格式，不擋 Beta 模式 | **屬實** | `generation.ts` 現有守門＝schema／語言／少量時間與動機詞／explicit-no-question／釐清閘門。無 placeholder 擋（`（店名）`/`OO`/`___` 直接外洩，截圖 G-04/G-05 重現）、無自貶/全面配合擋、無邀約歷史、無 boundaryReminder 矛盾檢查。Fallback 文案本身就是 conversation-rescue：「把球丟回一個好回答的小問題」（`generation.ts:645`） |
| 3.6 | 使用者真實風格沒進 Coach；findCompatiblePartner 語意抹掉篩選 | **屬實** | `effective_style_prompt_builder.dart:49-86` `buildForCoachFollowUp` 只送 stuckPoints/practiceGoals/notes，無 interactionStyle/secondaryStyle/長度/問句密度；`:122`「保持開放…不要急著篩選或設限」原文在案 |
| 3.7 | 舊 Coach 建議會自我強化 | **屬實（低嚴重度）** | `coach_chat_providers.dart:284-300` 教練 answer 回種進 activeSessionTurns；prompt 有標「教練(kind)」角色但無「舊建議不算對方證據」規則 |

**對規格書的兩個重要修正**：

1. **「no_message」不是從零開始**。契約層（null suggestedLine＋do_not_send）已存在，第一刀不需要動 schema／client——把「會停」做進伺服器端守門與 fallback，UI 只需正確呈現既有的 null 態。規格書的 `messageDecision`/`CoachAnswerV2` 改版留給第二批。
2. **釐清免費已是既成事實**（schema transform 強制 clarifyingQuestion `costDeducted=0`），規格 §6.2 的計費要求已達成；缺的只是 partner/conversation scope 的證據判斷。

另外規格書低估的一個成本：`inviteHistory`（兩次未承接禁再邀）目前**完全沒有資料源**，client 沒有結構化的邀約結果欄位；deterministic 版需要新 client 欄位＋wire 改動（動到 `computeCoachInputHash` 與 replay ledger），屬第二批，不是止血包。

## 2. 設計約束（來自 Dev Brain 既有踩坑）

- **不要往 prompt 堆規則**：現行 prompt 已有「回覆速度低權重」「邀約被拒四格」「1.8x 護欄」「不腦補負面動機」，截圖照樣翻車——證明規則再多也擋不住 prior（坑：prompt 規則堆太多後面幾條會被忽略）。止血一律走伺服器端 deterministic 守門＋針對性 retry prompt，模式照抄現有 `temporal_drift`/`language_drift` 的成熟做法。
- **硬擋只給無歧義違規**（placeholder、建議句與邊界提醒矛盾）；詞群類 Beta 模式（自貶、全面配合）走「擋下→帶指令重試→仍中才 fail-closed 收句」，不直接砍到罐頭 fallback（坑：LLM 守門會安靜殺掉品質最好的候選；守門把合格輸出打回時該降級成偏好而不是否決權）。每類守門加 log counter，上線後看誤殺率。
- **fail-closed 的終點是 null，不是罐頭句**：任何重試耗盡的情境，寧可出「策略＋suggestedLine=null」，不得再退回「丟一個好回答的小問題」。

## 3. 修正後分批計畫

### Batch A — 止血（只動 Edge server＋一處 UI 呈現；無 schema/wire 改動）

一句話：**讓系統會停、不外洩模板、不出自貶句**。

| 項 | 改動 | 檔案 |
|---|---|---|
| A1 | Placeholder 硬擋：`___`/`OO`/`ＯＯ`/`（店名）`/`[…]`/`<…>` regex，中擋→retry prompt→耗盡則收掉 suggestedLine（null），不進罐頭 fallback | `generation.ts`（新 assert＋attempt prompt 分支） |
| A2 | 自貶求接住/無限配合詞群擋（「好可憐」「我都可以」「都配合你/妳」「時間我可以配合」等）：retry 型守門 | 同上 |
| A3 | 建議句／邊界提醒矛盾擋：boundaryReminder 含「先別約/不要再邀/先收手」類詞而 suggestedLine 含邀約語意（「要不要」「約」「一起去」＋時間詞）→ retry→耗盡收句 | 同上 |
| A4 | suggestedLine 問號上限 1（通用版；現行只在使用者明說不要追問時才擋） | 同上 |
| A5 | 證據制釐清：partner scope 首輪且 `recentMessages` 空＋無 activeSessionTurns → 比照 global 強制免費釐清（釐清卡引導使用者選對話或貼對方原句）；`mustClarifyFirstRound` 從 scope-based 改 evidence-based | `clarification_policy.ts`、`prompts.ts`（partner 版首輪指引）、`generation.ts` |
| A6 | Fallback 去 conversation-rescue：罐頭建議句改為 `suggestedLine=null`＋保守策略文字；保留免扣費語意 | `generation.ts:630-737` |
| A7 | UI：`suggestedLine=null`＋`rewriteDecision=do_not_send` 時顯示「這輪先別傳」判斷卡（用現有欄位，不改 wire） | `coach_surface.dart` |
| A8 | Golden regression：截圖病灶中「確定性守門可鎖」的案型寫成 `generation_test.ts` invariants（G-01 零證據、G-02 自貶、G-04/G-05 placeholder、G-07 無限配合/矛盾；不驗 exact sentence）。G-03 空鉤子與 G-06 實體無來源**不屬 Batch A 確定性守門範圍**，只有 prompt 層規則，留待 Batch B/D | `generation_test.ts` |

驗收門檻（沿用規格 §13.3，範圍限確定性守門可及者）：placeholder 外洩 0%（含 fallback 草稿路徑）、建議/提醒矛盾 0%、golden invariants 全過、既有 prompts_test/generation_test 回歸綠。

### Batch B — 資料與決策統一（動 schema/client/wire）

- Partner scope 補「最近一段有效對話」＋analysis freshness＋provenance（`sourceConversationId`/`lastMessageAt`）；前台顯示「教練本次參考」。
- `evidenceQuality` 欄位＋`messageDecision` 三態進 schema（CoachAnswerV2）；UI 三態卡。
- `inviteHistory` 結構化（client 記錄邀約結果）→ 兩次未承接 deterministic 禁再邀。
- 舊建議標 `priorAdvice`，prompt 明文「不得當成對方反應證據」。
- 注意：動到 `computeCoachInputHash`／replay ledger 的欄位要走既有 ledger 相容程序。

### Batch C — 共享知識核心

- 從 `analyze-chat/analyze_prompt/` 抽 feature-neutral 決策核心到 `supabase/functions/_shared/social/`；知識原子做 typed registry＋deterministic selector（62 原子不上向量庫）。

### Batch D — 風格與 semantic critic

- `buildForCoachFollowUp` 帶入 interactionStyle/secondaryStyle/長度/問句密度；`findCompatiblePartner` 語意加回雙向篩選平衡。
- 二次 LLM critic（固定 rubric）＋fail-closed 重寫上限 2。

### Batch E — 閉迴路

- 新 feedback 分類（too_beta/should_not_send/…）、72 案 eval harness、三輪後投入變化追蹤。

## 4. 不採用／延後的規格項

- `messageDecision` schema 改版不進 Batch A（現有欄位已可表達「先別傳」，先讓行為對，再換契約）。
- 整份知識庫進 system prompt：規格書自己也反對，維持。
- `userIntent` LLM 分類器：Batch A 用「scope＋證據有無」的 deterministic 近似即可，B 再細分。

## 5. 風險

- 詞群守門有誤殺可能（正常語境的「我都可以」）：靠 retry-first 設計＋log counter 觀察，不做一刀 fail。
- A5 會改變 partner scope 首輪體驗（多一次免費釐清）：這是規格的核心意圖（Eric 已在方向上認可「先讓系統會停」），但屬產品行為改變，上線前 Eric 需在 TestFlight 實測確認。
- coach-chat 屬高風險區（AI 成本/計費路徑）：Batch A 實作完成須雙 AI 審查（AGENTS.md 規定），且每項守門不得改變計費語意（釐清 0／答案 1／fallback 0 維持不變）。
