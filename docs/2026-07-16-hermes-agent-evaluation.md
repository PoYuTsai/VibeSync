# Hermes Agent 評估（2026-07-16）

> 研究 Nous Research 的 Hermes Agent，評估對 VibeSync 的具體應用方式。
> 結論：不嵌入產品後端；借鏡其架構模式 + 可選部署為內部 DevOps 助理。

## Hermes Agent 是什麼

2026 年 2 月由 Nous Research 開源的「自我改進」AI agent（MIT、Python 3.11+、可自架於 $5 VPS）：

1. **學習迴圈**：複雜任務（5+ tool calls）後自動生成可重用 skill 文件，使用中自我修補，`hermes curator` 定期整併。
2. **持久記憶三層**：`MEMORY.md` 事實檔 + FTS5 全文檢索過往 session（LLM 摘要輔助）+ Honcho 辯證式用戶建模（跨 session 累積用戶畫像）。全部存 SQLite。
3. **40+ 工具**：網頁搜尋/瀏覽、圖像生成、TTS、終端執行（6 種後端）、MCP 支援。
4. **多平台 gateway**：Telegram/Discord/Slack/WhatsApp/Signal/CLI 單一進程接入（無 LINE）。
5. **排程自動化**：自然語言 cron，`/api/jobs` REST API（SQLite 持久化、Idempotency-Key）。
6. **OpenAI 相容 API server**：`/v1/chat/completions`、`/v1/responses`、SSE 串流、`X-Hermes-Session-Id` 會話維持。
7. **模型不鎖定**：Nous Portal（300+ 模型）/OpenRouter/OpenAI/自訂端點即時切換。

**關鍵限制：本質是單用戶個人助理架構**。Profiles 功能只提供多個獨立 instance，無多租戶共用基礎設施。

## 對照 VibeSync 現況

- 所有 AI 都是 Edge Function 單發 prompt→response，無 agent loop、無 tool-use（`supabase/functions/analyze-chat/`、`coach-chat/`、`coach-follow-up/`、`practice-chat/`）。
- Coach 1:1 無跨 session 長期記憶：每次對話不記得用戶的曖昧對象、過往建議、進展。
- OCR 左右歸屬準確率 61.3%（目標 ≥98%，見 `docs/ocr-analysis-maturity-benchmark.md`）。
- 已有 Discord rotation 工具（`tools/cc-rotate/`）與 Codex review gate。

## 判斷：不嵌入產品後端

1. 單用戶架構 vs VibeSync 多租戶需求，每用戶一個 instance 不現實。
2. 約會截圖高度敏感，經 Nous Portal/第三方工具增加隱私外流面。
3. 會繞過現有 quota/RevenueCat/guardrails 體系。
4. Agent loop 多輪呼叫使 token 成本倍增，牴觸現有成本管理。
5. 現階段為 TestFlight 穩定期，優先序不支持大型架構改造。

## 四個可行應用方向（按價值排序）

### A. 借鏡記憶架構，為 Coach 1:1 建原生記憶層（產品價值最高）

把 Hermes 三層記憶模式移植到 Supabase：`coach_memory` 用戶畫像表（曖昧對象、關係階段、有效/無效建議）+ session 摘要表 + 檢索注入 `coach-chat/prompts.ts` 的 system prompt。不引入 Hermes 程式碼，只借架構模式。

### B. 部署 Hermes 當內部 DevOps 助理（最快落地、零產品風險）

VPS 跑一個 instance + Discord gateway + cron：每晚自動跑 `tools/ocr-golden` 回歸並回報 Discord、摘要 dogfood bug、檢查 `docs/reviews/ai-arbitration-queue.md` OPEN 項。單用戶架構在此完全適配，且學習迴圈會把重複維運固化成 skills。符合工作流工具優先序。

### C. 借鏡 cron 排程模式做主動教練追蹤

用 pg_cron + push notification 實作「三天後追蹤進展」，強化既有 `coach-follow-up`。

### D. 借鏡 agent loop 解 OCR 準確率問題

在 analyze-chat 引入有限的 tool-use 自我驗證迴圈（裁圖重檢左右歸屬）。屬高風險區，需 Codex review。

## 來源

- <https://github.com/NousResearch/hermes-agent>（README）
- <https://github.com/mudrii/hermes-agent-docs>（社群技術文件）
- <https://hermes-agent.nousresearch.com/docs/>（官網被 Cloudflare 擋直接抓取，僅取得搜尋摘要）
