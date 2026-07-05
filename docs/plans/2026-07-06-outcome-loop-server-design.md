# 案 1：Outcome Loop Server 化 — 設計定稿

> 2026-07-06 brainstorming 定稿。狀態：APPROVED（Eric 拍板「全做＋改掉只存本地承諾」＋晶片兩段式改版納入）。
> 上游：`docs/plans/2026-07-06-post-review-optimization-roadmap.md` 案 1 段。

## 拍板紀錄（含舊決策衝突處理）

- 2026-05-15 Eric 曾拍板 outcome loop 本機 only、`930bf46` 暫停 digest 注入 coach prompt（理由：UI 契約寫「只存本地」＋晶片沒收齊 userAction 會 misleading）。
- 2026-07-06 Eric 在知情下**明確重開這條線**：範圍 1–4 全做，UI「只存本地」文案與隱私頁同批改成誠實版；晶片改兩段式收齊 userAction，解除 misleading 根因。
- 複製自動記錄的高調程度：默默記＋toast 順帶提（「已複製，發出後記得回來回報結果」），不彈窗。

## 一、使用者體驗

### 兩段式晶片（coach / opener / analyze 三處共用元件）

1. 第一段「這則建議你怎麼處理？」→ 照著發了／改一改才發／沒有發／回頭問了教練
   （對應 `CoachingUserAction`：sentAsIs／editedAndSent／didNotSend／askedCoach）
2. 答 sentAsIs／editedAndSent 才出第二段「她的反應？」→ 有接話／冷回／已讀沒回／反應不好
   （對應 `CoachingOutcomeSignal`：engaged／cold／noReply／negative）
3. 答 didNotSend／askedCoach 直接結束，不問第二段。
4. 後選覆蓋前選（沿用現行一 advice 一 event 機制）。
5. 現有 coach 卡 `_CoachOutcomeCaptureCard`（`coach_chat_card.dart:919`，5 顆混軸晶片、userAction 固定 unknown）改版為上述兩段式。

### 複製即自動記錄

- 四個複製觸點：`analysis_screen.dart:4384` 系（:4420/:4466/:4590/:4612/:6668）、`reply_style_card.dart:199/:266`、`shared/widgets/reply_card.dart:125`、`opening_rescue_screen.dart:1528`。
- 複製當下自動記一筆 `userAction=sentAsIs`、`outcome=pending`；同一張卡重複複製冪等（同 adviceId upsert，不疊加）。
- 複製後卡片下方浮出收合的「後來呢？」晶片條，之後回報覆蓋 pending。
- 使用者之後的晶片作答一律覆蓋自動記錄值。

### 「只存本地」承諾改版

- 現行「只存本地」UI 文案改為方向：「建議採用情況會去識別化上傳以改善服務；你的對話內容與筆記永遠只存在手機」。
- 隱私頁同批更新。
- 上傳白名單見下；`outcomeTextPreview`（對方回覆原文）與 `userNote`（使用者筆記）**絕不上傳**。

### 教練有記憶（digest 回注）

- `CoachingOutcomeDigest.hasEnoughSignal`（≥3 筆）才注入；不足時完全不注入，行為與現在一致。
- 注入內容＝現成 `localInsightLines`（`coaching_outcome_digest.dart:203`）。

## 二、資料與通道

### 關聯鍵（現況無穩定 id，client 自補）

- coach：沿用 `result.id`（現行 `coach:<resultId>`，`coaching_outcome_providers.dart:60`）。
- opener：server payload 無 id（`opener_service.dart:170`）→ client 在解析回包時自產 requestId（UUID），adviceId＝`opener:<requestId>:<typeKey>`（typeKey＝extend/resonate/tease/humor/coldRead）。
- analyze：同法，client 在結果解析時對每句建議自產 adviceId（`analyze:<requestId>:<index>`）。
- adviceId 掛在卡片 model 上，複製與晶片回報共用，保證冪等。

### 本機（真相源）

- Hive `coaching_outcome_events` 不變，`CoachingOutcomeEvent` 全欄位照存（含 preview/note）。

### 上傳（best-effort）

- 通道：現有 `submit-feedback` Edge Function 加一種事件 kind（如 `kind: 'outcome'`）分支，驗證後寫**新表** `outcome_events`（不塞現有 `feedback` 表）。復用其 JWT 驗證骨架（`index.ts:158`）。
- 上傳白名單欄位：id、source、adviceType、adviceId、userAction、outcome、suggestedMoveSummary（≤160，AI 產物非用戶對話）、createdAt、userTier。
- 時機：本機寫入成功後 fire-and-forget POST；失敗不重試、不擋 UI、不回滾本機。Hive 為唯一真相源。
- 不碰計費、不碰 analyze-chat 主線、不碰 quota。

### digest 回注（高風險批）

- client：`coach_chat_api_service.dart:152` body 新增 `outcomeInsightLines`（string[]，client 端截長度上限）。
- server：`coach-chat/schemas.ts` 加選填欄位（缺席＝現行為，向後相容）；`coach-chat/prompts.ts:8` context 加一節「近期建議結果」。
- **動 Edge schema＝高風險區，此批必走 Codex 雙審**，獨立 commit，排最後。

## 三、實作批次與風險

| 批 | 內容 | 風險 | 審查 |
|---|---|---|---|
| 1 | 晶片兩段式改版（coach 卡先行，抽共用元件） | 低（純 client UI） | 單審 |
| 2 | opener/analyze 補晶片入口＋adviceId 自產＋複製自動記 pending | 低（純 client） | 單審 |
| 3 | submit-feedback 加 outcome kind＋新表 migration＋上傳封裝＋「只存本地」文案與隱私頁改版 | 中（低風險 function＋新表；不碰計費） | 單審，migration 照帳本協議走 MCP apply |
| 4 | digest 注入 coach prompt（client body＋Edge schema＋prompt） | **高（Edge schema）** | **Codex 雙審** |

每批各自 targeted tests；批 4 需含「欄位缺席＝現行為」的向後相容測試。

## 四、不做的事（YAGNI）

- 不做上傳重試佇列／離線同步。
- 不做 48h 跟進提醒（那是案 4）。
- 不做 dashboard 消費 outcome 數據（後台先用 SQL 看）。
- 不上傳 outcomeTextPreview／userNote，永遠。
