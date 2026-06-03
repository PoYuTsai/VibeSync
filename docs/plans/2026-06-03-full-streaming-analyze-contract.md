# Full Streaming Analyze Contract

> Status: Draft. No implementation yet.
> Scope: analyze-chat text path first. Screenshot, opener, Coach 1:1, and follow-up reuse the same UX principles later.

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
| D1 | Charge at recommendation or final done? | Charge at valid recommendation event. |
| D2 | Keep old quick code during dogfood? | Yes, hidden fallback only. |
| D3 | Manual text first or screenshot too? | Manual text first, screenshot next. |
| D4 | If final style differs from early style? | Log drift and preserve early official recommendation in dogfood. |
| D5 | Use SSE or NDJSON? | SSE if Supabase Edge handles it reliably, otherwise NDJSON. |

## Review Gate

This is high-risk because it touches:

- `analyze-chat`
- quota charging
- AI prompt/token behavior
- Edge response schema
- frontend analysis state

Codex review is required before dogfood/build can be called safe.

