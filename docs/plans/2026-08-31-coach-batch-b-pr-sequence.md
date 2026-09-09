# 教練 Batch B 實作序（3 個獨立交付包）

基線：main `f1237ac0`（Batch A 已交付）。母規格：`2026-08-31-coach-knowledge-integration-verified-plan.md` §Batch B。
Work 單：`w-e548e454-9219-47ff-92ff-3c59d5438719`（R2，coding=claude，review=codex，雙 AI 審查）。

## 先講最重要的查證結論：三包都不用動 computeCoachInputHash

`billing.ts:64` 的 canonical 陣列只含 `userId/userQuestion/sessionId/activeSessionTurns/forceAnswer/scopeKey/lifecyclePhase`。`recentMessages`、`analysisSnapshot`、`effectiveStyleContext` 本來就**不入 hash**（2026-08-03 cross-review 已核的先例，見 `coach_chat_providers.dart:236-239` 註解）。Batch B 的新輸入（partner 對話補送、provenance、inviteHistory）全是同類 context 欄位 → 沿用先例不入 hash，replay ledger 的 input 端完全不動。

唯一要動 ledger 的是 **B2 的 result 端**：card 白名單在三層同組——DB CHECK＋settle RPC 驗證（`20260721120000_coach_exactly_once.sql:39-50,296-302`）、Edge `COACH_CARD_ALLOWED_KEYS`（`billing.ts:109`）、`ResponseCardSchema .strict()`。加欄位必須三層同步，且 **migration 先上 production 驗證，Edge 才能跟**（AGENTS.md 既有順序；否則 settle 直接被 CHECK 拒）。

審查時的翻案點（留給主審）：若認定 inviteHistory 該影響 replay 身分，canonical version 升 `["coach-chat", 2]` 即可——舊 rows 24h 自然過期，requestId 是 per-intent 新生，無跨版卡死風險。預設不升。

## PR-B1 — Partner scope 補最近有效對話＋provenance（client 為主）

- Client（`coach_chat_providers.dart`）：partner scope 下 `conversation` 目前為 null → recentMessages 空。改為挑該對象「最近一段有效對話」（有訊息、freshness 窗內），補送 `recentMessages`＋`conversationSummary`；`analysisSnapshot` 從 `scope.isConversation` 限定放寬到 partner（帶 freshness 判斷）。
- Edge（`schemas.ts` RequestSchema strict）：新選填欄 `contextProvenance { sourceConversationId, lastMessageAt }`，缺席＝現行為；`prompts.ts` partner 版標注來源與新鮮度。
- UI：「教練本次參考」顯示——client 自己知道送了什麼，**不加回傳欄位**。
- 相容：欄位選填、雙向缺席安全 → Edge 先上、新 build 後補，順序無風險。
- 呼應 Batch A A5：partner 首輪證據制釐清，補了對話＝有證據，體驗閉環。
- 驗證：`prompts_test`/`index_test` 回歸＋新欄 schema 測試；Flutter 端 provider 測試。

## PR-B2 — CoachAnswerV2：evidenceQuality＋messageDecision 三態＋UI 三態卡

- **Targeted migration（先行）**：更新 `coach_requests` CHECK＋`settle_coach_request` 白名單，加 `evidenceQuality`、`messageDecision` 兩鍵（白名單增鍵，舊 card 仍合法；不 rewrite 舊 rows）。走 shared-agent-rules 的 targeted migration 程序，禁 `db push`。
- Edge：`ResponseCardSchema` 加兩欄（**選填**——24h 內舊 replay rows 沒有新欄，驗證不得炸）；`COACH_CARD_ALLOWED_KEYS`＋`isValidCoachLedgerResult` 同步；`migration_source_test.ts` 加對應 assert；generation prompt 產出三態。
- messageDecision 三態把 Batch A 的「suggestedLine=null＋do_not_send ⇒ 先別傳」正式化；**計費不變量不動**：釐清 0／完整過驗答案 1（含 do_not_send）／fallback 0。
- Client：三態卡 UI（`coach_surface.dart`）；json_serializable 對缺席欄容忍（舊 Edge 期間）。
- 相容順序：migration → Edge → build，三步各自可驗。
- 驗證：`billing_test`（新舊 card 皆過驗）、`migration_source_test`、golden 三態 UI 測試。

## PR-B3 — inviteHistory 結構化＋deterministic 禁再邀＋priorAdvice 標註

- Client：邀約結果結構化記錄（sent/accepted/no_uptake…）進現有 outcome digest（Hive），送新選填欄 `inviteHistory`（上限小陣列）。
- Edge：RequestSchema 加 `inviteHistory`；`generation.ts` deterministic gate——兩次未承接 → 邀約句型禁入（**復用 Batch A A3 的邀約語意偵測詞群**，retry→耗盡收句、不扣費語意照舊）；`prompts.ts` 把舊建議標 `priorAdvice`＋明文「不得當對方反應證據」。
- 不動 hash、不動 ledger。
- 驗證：`generation_test` 加禁再邀 invariants（比照 Batch A golden 寫法）；誤殺觀測沿用 log counter。

## 順序與依賴

B1 → B2 → B3（B1 無依賴先行；B2 是唯一動 migration 的包，獨立可撤；B3 復用 A3 詞群、與 B1/B2 無耦合，可視 Eric 節奏並行）。每包獨立可測可 revert，各自走雙 AI 審查（coach-chat＝Edge schema＋AI 成本高風險區）。
