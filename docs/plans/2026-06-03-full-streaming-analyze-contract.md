# Full Streaming Analyze Contract

> Status: Draft v2. No implementation yet.
> Scope: analyze-chat text path first. Screenshot, opener, Coach 1:1, and follow-up reuse the same UX principles later.
> Note: The v2 Traditional Chinese addendum below is the current decision layer. If it conflicts with older English draft sections, v2 wins.

## v2 繁中決策補充

這份補充先解掉 CC review 指出的兩個阻塞點：

1. Claude stream 到底怎麼變成 UI 事件。
2. 正式推薦回覆出現時，到底怎麼扣額度。

在這兩點沒有鎖死前，不應該開始寫 parser、quota migration、或 Flutter streaming UI。

### 決策 1：採用單一 full prompt stream，不再用 quick prompt 當正式答案

我們選擇：

- 一次分析只呼叫一條 full analyze 路徑。
- Claude 使用 streaming。
- 模型輸出「一行一個完整 JSON event」。
- 後端負責把 Claude 的文字 stream 重新框成 SSE 或 NDJSON event。
- 前端只接收完整 typed event，不解析半截 JSON。

不採用：

- `quick prompt + full prompt` 兩次 Claude call。
- 用 quick 的答案當正式 AI 推薦回覆。
- 前端自行解析 Claude stream 中半完成的 JSON。

原因：

- 多 prompt 會讓 quick / full 品質漂移。
- 使用者通常會採用第一個看到的回覆，所以第一個正式可複製回覆必須來自 full prompt。
- 前端解析 partial JSON 太脆弱，錯誤會直接變成 UI regression。

### Claude 事件輸出格式

模型輸出必須是 JSONL：每一行都是一個完整 JSON object。

Prompt 必須明確要求：

- 每個 event 都只能佔一行。
- 每行都是 minified JSON。
- 不可 pretty-print。
- 字串內容不可包含實際換行；若需要換行意義，使用 `\n` escaped sequence。
- newline 是唯一 record separator。

範例：

```text
{"type":"analysis.progress","step":"read_context","message":"正在讀對話脈絡...","ordinal":1,"total":7}
{"type":"analysis.decision","selectedStyle":"resonate","nextStepTitle":"先接住情緒，不急著推進","nextStepBody":"這回合先讓對方感到被理解。","doThis":"先回一句短而穩的接球。","avoidThis":"不要急著解釋或追問結果。","confidence":"high"}
{"type":"analysis.recommendation","selectedStyle":"resonate","message":"我懂，你最近真的很忙。沒關係，我們就慢慢聊，你方便的時候再說。","reason":"先降低壓力，讓對方保留主導感。","quotedContext":"我最近事情也很多，不太想被催。"}
{"type":"analysis.reply_option","style":"resonate","isSelected":true,"message":"我懂，你最近真的很忙。沒關係，我們就慢慢聊，你方便的時候再說。","approach":"共鳴","reason":"最符合對方目前的壓力訊號。"}
```

後端 reframer 規則：

1. 從 Anthropic SSE `text_delta` 持續累積文字 buffer。
2. 只在遇到 newline 且該行可被 `JSON.parse` 成完整 object 時，才轉成對外 event。
3. 半行、半個 object、或 JSON parse 失敗的內容不得送給前端。
4. stream 結束時若還有半個 object，視為 malformed tail，記錄 telemetry。
5. 後端可以暫存事件並依 contract order 對外輸出，不能把模型亂序直接丟給前端。

### 決策 2：扣額度在「正式推薦回覆事件通過驗證後、對外送出前」執行

推薦採用 charge-before-emit：

1. stream 開始時建立 `analysis_runs` pending row，尚不扣額度。
2. 模型產生 `analysis.recommendation`。
3. 後端驗證 recommendation event 合法。
4. 後端執行 atomic `charge_analysis_run` RPC。
5. RPC 成功後，才把 `analysis.recommendation` event 送給前端。
6. 之後 full report sections 繼續 stream。

`charge_analysis_run` 必須在同一個 Postgres transaction 內同時寫入：

- `charged_at`
- `recommendation_json`
- `selected_style`

也就是：只要資料庫狀態顯示已扣額度，就一定可以 resume 並重送正式推薦回覆。
不得先寫 `charged_at`，再用另一個 statement 補 `recommendation_json`。

為什麼選這個：

- 避免「正式推薦回覆已經送出，但扣額度 RPC 失敗」造成核心價值被免費拿走。
- 若前端斷線但後端已成功送出 event，這跟一般 API response 成功後 client 掛掉相同，視為已交付。
- retry 時可以沿用同一個 charged run，不重扣。

代價：

- 如果 RPC 成功，但使用者剛好在 event 到達前斷線，可能會被扣但沒看到推薦回覆。
- 這個風險要靠 retry/resume 補救：使用者回來後用同一個 `runId` 取回已產生的 recommendation，不再重扣。

### 扣額度 failure matrix

| 狀態 | Charge RPC | 對外是否 emit recommendation | 正確結果 |
| --- | --- | --- | --- |
| 模型尚未產生 recommendation | 未執行 | 否 | 不扣額度，可重跑整次分析 |
| recommendation JSON malformed | 未執行 | 否 | 不扣額度，回 `STREAM_MALFORMED_RECOMMENDATION` |
| recommendation guardrail 不通過 | 未執行 | 否 | 不扣額度，回可重試錯誤 |
| recommendation 合法，準備交付 | 執行中 | 暫停 emit | UI 繼續顯示「正式回覆整理中」 |
| Charge RPC 成功 | 成功 | 是 | 扣 1 次，使用者看到正式推薦回覆 |
| Charge RPC 失敗 | 失敗 | 否 | 不 emit 推薦回覆，回 `CHARGE_FAILED_RETRYABLE` 或 `QUOTA_EXHAUSTED` |
| Charge RPC 成功後 client 斷線 | 已成功 | 後端已嘗試 emit | 視為已扣；同 runId resume/retry 不重扣 |
| full report 後半段失敗 | 已成功 | recommendation 已送出 | 保留推薦回覆，retry full remainder 不重扣 |
| 使用者 retry 同一 runId | 不再執行 | 可重送已存 recommendation | 不重扣 |
| conversation hash 不一致 | 不執行 | 否 | 阻擋 retry，回 `RUN_CONVERSATION_MISMATCH` |

### Pending run lifecycle

現有 two-stage 設計是 `create_charged_analysis_run`：quick 成功時一次扣費並建立 charged row。

full streaming 需要新的 lifecycle：

```text
pending -> recommendation_ready -> charged -> report_streaming -> done
                              \-> charge_failed
                              \-> report_failed_after_charge
```

建議資料狀態：

| 欄位 | 用途 |
| --- | --- |
| `status` | `pending`, `charged`, `done`, `failed` |
| `recommendation_json` | 已驗證且可重送的正式推薦回覆 |
| `selected_style` | 早期 recommendation 選出的 style |
| `charged_at` | 已扣額度時間；非 null 代表不可再扣 |
| `final_result_json` | 完整分析完成後的 legacy-compatible result |
| `last_error_code` | 最近失敗原因 |

SQL invariant：

- `charge_analysis_run` 必須是 atomic RPC。
- 同一 `analysis_run.id` 只能從 `charged_at is null` 更新成 non-null 一次。
- 同一個 RPC 必須一起寫入 `recommendation_json` 與 `selected_style`。
- `charged_at is not null` 必須代表 `recommendation_json is not null`。
- 若 `charged_at is not null`，retry 只能讀/補 full report，不可再呼叫 `increment_usage`。

### Retry 策略

v1 不做真正的「從 Claude 中途續寫」。

如果 recommendation 已扣額度，但 full report 後半失敗：

1. 保留已存的 `recommendation_json`。
2. retry 時重新呼叫 full prompt，但把已存 recommendation 作為硬性 anchor。
3. 新 full output 必須維持同一 `selected_style` 與同一核心回覆。
4. backend drift check 不通過時，不覆蓋已存 recommendation。
5. retry 不重扣。

這會多花一次 full tokens，但行為清楚、安全，先適合 dogfood。
這也是明確的 AI cost behavior change：retry full report 會重新支付 Claude full prompt 成本，但不會重新扣使用者額度。送 Codex review 時必須主動標示。

### Recommendation-only guardrail

扣額度前的 guardrail 不能等完整 `AnalysisResult`。

因此 guardrail layer 必須支援 recommendation-only payload：

```json
{
  "selectedStyle": "resonate",
  "message": "...",
  "reason": "...",
  "quotedContext": "..."
}
```

如果現有 `server_guardrails.ts` 只接受完整分析結果，v1 需要新增薄 wrapper：

- 驗證推薦回覆不是空字串。
- 驗證沒有 prompt injection / unsafe instruction leakage。
- 驗證沒有要求使用者做危險、騷擾、威脅、越界行為。
- 驗證 `selectedStyle` 是合法五風格之一。
- 驗證 message 與 quoted context 不明顯矛盾。

只有 recommendation-only guardrail 通過後，才可以呼叫 `charge_analysis_run`。

### Drift anchor 改定義

舊 two-stage：

```text
quick recommendation -> full final result
```

新的 full streaming：

```text
analysis.recommendation -> analysis.done finalResult
```

也就是：

- `analysis.recommendation.message` 成為本次 run 的 official anchor。
- `analysis.done.finalResult.finalRecommendation` 必須與 anchor 同方向。
- final 可做輕微潤飾，但不可換策略、換情緒方向、換 selected style。

初版 dogfood 建議：

- 嚴重 drift：不覆蓋 recommendation，記錄 `streaming_recommendation_drift`.
- 輕微措辭差異：允許，但 UI 要能標示 final 是「完整分析後版本」。

### Flutter streaming spike

實作前要先做 1 小時 spike：

- 確認 Flutter 不能用 `supabase.functions.invoke` 讀 stream。
- 改用 raw `http.Client().send(...)` 或 Dio stream。
- 手動帶 `Authorization: Bearer <accessToken>`。
- 測試 iOS/TestFlight 對 SSE 或 NDJSON response 是否穩定。

若 SSE 在 Supabase Edge + Flutter 上不穩，v1 改用 NDJSON response。

### 下一步實作前的停止線

在開始 code 前，必須先完成：

1. 事件生產機制已寫進 contract：單一 full prompt JSONL + backend reframer。
2. 扣額度 failure matrix 已寫進 contract。
3. pending run lifecycle 已寫進 contract。
4. Codex review contract，確認沒有 P1/P2。
5. Flutter streaming spike 通過。

沒有通過以上 5 點，不進 `analyze-chat` 實作。

## Why This Exists

The two-stage analyze experiment improved perceived latency, but it introduced a product risk:

- `quick` used a smaller prompt and could disagree with `full`.
- The first visible answer became the answer users may copy.
- Full analysis could later change direction, style, or recommended reply.

For VibeSync's core value, the official reply recommendation must come from the same full reasoning path that produces the detailed analysis.

The new direction is:

1. Keep one official full analyze path.
2. Stream useful milestones from that full path.
3. Show early progress and early decision output.
4. Do not treat a separate quick prompt as the official recommendation.

## Product Target

The user experience should feel like this:

| Time | User sees | Source |
| --- | --- | --- |
| 0-1s | Analysis started, clear loading copy | App state |
| 1-3s | "reading context / judging next move" progress | Backend events |
| 6-8s max | `本回合怎麼接` + official recommended reply | Full prompt stream |
| 8-20s | Five styles, radar, deeper strategy gradually appear | Full prompt stream |
| done | Final report is complete and stable | Full prompt assembled result |

The 6-8s target is the practical upper bound. If the full prompt cannot produce an official recommendation by then, the app should show meaningful progress copy, not a fake recommendation from a separate prompt.

## Current Problem

Current code shape:

- Full prompt lives in `supabase/functions/analyze-chat/index.ts` as `SYSTEM_PROMPT`.
- Claude calls go through `supabase/functions/analyze-chat/fallback.ts`.
- `fallback.ts` waits for `response.text()` before returning anything.
- The full JSON schema places large structures like `replyOptions`, radar, strategy, and other report fields in one final object.

This means the client sees nothing useful until the entire JSON is complete.

Naively turning on Claude streaming is not enough. If the model streams one giant JSON object in the old order, the app may still not get the useful recommendation early.

## Core Decision

The official recommendation does not need to wait until all five reply styles are fully printed.

It does need to satisfy all of these:

1. It comes from the full prompt, not a separate quick prompt.
2. It declares which reply style it selected.
3. The final full report later agrees with that selected style.
4. If the later full report disagrees, the backend treats it as drift and logs or rejects it.

This keeps latency lower without giving up the full prompt's judgment.

## Streaming Event Contract v1

The backend should stream complete JSON events, one per line or SSE event. The frontend should not parse half-finished JSON fragments.

### Event Types

| Event | Required fields | Purpose |
| --- | --- | --- |
| `analysis.started` | `runId`, `conversationHash`, `etaSeconds` | Create one server-owned analysis session. |
| `analysis.progress` | `step`, `message`, `ordinal`, `total` | Reduce waiting anxiety with human-readable progress. |
| `analysis.decision` | `selectedStyle`, `nextStepTitle`, `nextStepBody`, `doThis`, `avoidThis`, `confidence` | First official "本回合怎麼接". |
| `analysis.recommendation` | `selectedStyle`, `message`, `reason`, `quotedContext` | First official reply recommendation. |
| `analysis.reply_option` | `style`, `message`, `approach`, `reason`, `isSelected` | One of the five reply styles. May arrive one by one. |
| `analysis.coach_hint` | `action`, `copy`, `riskLevel` | Coach card / next action. |
| `analysis.metrics` | `enthusiasm`, `dimensions`, `topicDepth` | Radar and score data. |
| `analysis.report_section` | `section`, `payload` | Psychology, strategy, warnings, profile hints, health check. |
| `analysis.done` | `finalResult`, `usage`, `durationMs` | Final legacy-compatible result. |
| `analysis.error` | `code`, `message`, `recoverable`, `retriesRemaining` | Retry or user-facing failure. |

### Selected Style Values

Use the existing five-style vocabulary:

- `extend`
- `resonate`
- `tease`
- `humor`
- `coldRead`

The UI can localize labels, but the transport values should stay stable.

## Output Order

The full prompt must be reshaped to emit events in this order:

1. `analysis.started`
2. 2-4 `analysis.progress` events
3. `analysis.decision`
4. `analysis.recommendation`
5. `analysis.reply_option` for selected style first
6. `analysis.reply_option` for the other four styles
7. `analysis.metrics`
8. `analysis.coach_hint`
9. remaining `analysis.report_section` events
10. `analysis.done`

This order is the main performance design. The model still reasons through the full prompt, but it is instructed to reveal the highest-value decision first.

## UI Contract

The analysis screen should have one clear progress surface.

Recommended above-the-fold order:

1. Conversation preview
2. Progress / current analysis status
3. `本回合怎麼接`
4. `AI 推薦回覆`
5. Full report sections as they arrive

During streaming:

- Do not show the screenshot upload block as the main waiting area.
- Do not show copy buttons for unfinished generated content.
- Do show stable labels like "完整分析還在整理中".
- If a section has not arrived yet, show a named placeholder, not an empty blank.

Suggested progress copy:

- `正在讀對話脈絡...`
- `正在判斷這回合怎麼接...`
- `已抓到方向，正在整理正式回覆...`
- `正式回覆已完成，完整分析繼續整理中...`
- `五種回覆風格整理中...`
- `互動雷達整理中...`
- `深層策略整理中...`

## Quota And Run Rules

The current two-stage design charges on quick success. Full streaming should replace that with one streaming run.

Proposed v1 rule:

- Create a server-owned `analysis_runs` row when streaming starts.
- Charge quota exactly once when `analysis.recommendation` is successfully emitted.
- If no official recommendation is emitted, do not charge.
- If the user leaves the screen after recommendation is emitted, it remains charged because the core value was delivered.
- If full report fails after recommendation, the user can retry the remaining report using the same `runId` without another quota charge.

This matches product value better than charging only at final `analysis.done`, because the user may already copy the official reply before the long report finishes.

Required invariants:

1. One run can be charged at most once.
2. Retry never creates a second charge for the same `runId`.
3. A client cannot submit a fake `runId` for another user.
4. Conversation hash mismatch blocks retry.
5. If the model emits malformed decision/recommendation events, no quota is charged.

## Drift Rules

The backend should validate consistency between early events and final result.

Minimum drift checks:

- `analysis.recommendation.selectedStyle` must equal the selected style in final result.
- The selected `reply_option` should preserve the same core message.
- `analysis.decision.nextStep` should not contradict final `coachActionHint`.

Recommended v1 behavior:

- If final result lightly polishes wording, allow it.
- If final result changes direction, log `streaming_recommendation_drift`.
- If drift is severe, keep the early official recommendation visible and show a "完整分析未能完成一致性檢查" recoverable error for dogfood.

For App Review readiness, severe drift should be rare before shipping.

## Backend Shape

Add a streaming path instead of extending the old two-stage quick/full contract forever.

Possible request mode:

```json
{
  "responseMode": "stream",
  "messages": [],
  "context": {}
}
```

Response format:

```text
data: {"type":"analysis.started","runId":"...","etaSeconds":18}
data: {"type":"analysis.progress","step":"read_context","message":"正在讀對話脈絡...","ordinal":1,"total":7}
data: {"type":"analysis.decision","selectedStyle":"resonate",...}
data: {"type":"analysis.recommendation","selectedStyle":"resonate","message":"..."}
data: {"type":"analysis.reply_option","style":"resonate","isSelected":true,...}
data: {"type":"analysis.done","finalResult":{...}}
```

Implementation principle:

- Claude streams text.
- Backend converts model output into complete typed events.
- Backend also buffers enough data to assemble the existing legacy `AnalysisResult` at `done`.
- Client receives typed events and updates UI incrementally.

Avoid:

- Client-side parsing of partial JSON.
- Showing text before the backend knows which field it belongs to.
- Letting an early event become official if final validation fails badly.

## Prompt Shape

The full prompt needs a streaming-specific output contract.

It should still include core VibeSync reasoning:

- situation classification
- emotional risk
- pressure and boundary detection
- five reply style selection
- conversation stage
- recommended reply
- coaching action
- radar and deeper report

But it should stop requiring the model to write the whole report before the recommendation can be seen.

Prompt output instruction should be closer to:

1. First decide the safest next move.
2. Emit `analysis.decision`.
3. Emit official `analysis.recommendation`.
4. Then expand into five styles and full report.

## Frontend Shape

Replace the user-visible quick answer with streaming state.

State machine:

| State | UI |
| --- | --- |
| `idle` | normal screen |
| `connecting` | progress card |
| `decisionLoading` | progress card with current step |
| `decisionReady` | show `本回合怎麼接`, keep recommendation placeholder |
| `recommendationReady` | show official `AI 推薦回覆`, keep report placeholders |
| `reportStreaming` | sections appear one by one |
| `done` | full stable report |
| `failedBeforeRecommendation` | no charge, retry whole analysis |
| `failedAfterRecommendation` | charged, preserve recommendation, retry remaining report |

## Rollout Plan

Do not remove quick immediately.

Suggested sequence:

1. Write this contract and get Eric/Bruce/Codex alignment.
2. Add backend streaming parser and event tests.
3. Add `responseMode: "stream"` behind dogfood flag.
4. Add frontend streaming notifier and UI behind dogfood flag.
5. Dogfood manual text analyze with hard cases.
6. Dogfood screenshot analyze after text path is stable.
7. Remove quick as official answer source.
8. Archive the two-stage quick/full plan.

## Test Cases Before Dogfood

Backend:

- Emits `decision` before `recommendation`.
- Emits `recommendation` before all five `reply_option` events.
- Charges only after valid recommendation event.
- Does not charge on malformed early event.
- Retry after post-recommendation failure does not recharge.
- Final result selected style matches early selected style.

Frontend:

- Leaving and returning during `decisionLoading` does not show stale old analysis.
- Leaving and returning after `recommendationReady` preserves official reply.
- Failure before recommendation shows retry and no consumed quota.
- Failure after recommendation preserves reply and retries report only.
- Copy button appears only after `recommendationReady`.

Dogfood:

- Simple chat, low risk.
- Boundary setting / pressure.
- Apology and repair.
- Mixed signal.
- Long message.
- User adds "我說" after analysis.
- Screenshot path after text path passes.

## Non-Goals For v1

- Coach 1:1 streaming.
- Coach follow-up streaming.
- Opener streaming.
- Rewriting all report cards.
- Perfect token-level live text display like Claude Code.

Those can come after analyze-chat text path proves stable.

## Open Decisions

| ID | Decision | Suggested default |
| --- | --- | --- |
| D1 | Charge at recommendation or final done? | Resolved in v2: charge-before-emit after valid recommendation, and persist recommendation in the same RPC. |
| D2 | Keep old quick code during dogfood? | Yes, hidden fallback only. |
| D3 | Manual text first or screenshot too? | Manual text first, screenshot next. |
| D4 | If final style differs from early style? | Resolved in v2: early `analysis.recommendation` is the anchor; severe final drift cannot overwrite it during dogfood. |
| D5 | Use SSE or NDJSON? | SSE if Supabase Edge handles it reliably, otherwise NDJSON. |

## Review Gate

This is high-risk because it touches:

- `analyze-chat`
- quota charging
- AI prompt/token behavior
- Edge response schema
- frontend analysis state

Codex review is required before dogfood/build can be called safe.
