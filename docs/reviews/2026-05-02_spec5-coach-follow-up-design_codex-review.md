# Codex Spec Review — Spec 5 Coach Follow-up v1 Design

**Date:** 2026-05-02
**Reviewed doc:** `docs/plans/2026-05-02-spec5-coach-follow-up-v1-design.md` @ `625b13d`
**Verdict:** REVISED_AND_APPROVED

## Summary

The product shape is approved: Coach Follow-up v1 should be a single-turn, user-triggered coach session with three phases (`prepareInvite`, `preDateReminder`, `postDateReflection`), click-first input, optional text, latest-only local persistence, no push notification, no chatbot, and no long-term memory writes.

The one architecture amendment I would require before implementation planning is:

> Use an independent `coach-follow-up` Edge Function, not an `analyze-chat` mode branch.

This keeps Spec 5's dedicated AI prompt real while avoiding unnecessary coupling to the OCR-stable `analyze-chat` function.

## Required Amendment

### Q-Codex-1 — Edge `mode: coach_follow_up` vs independent Edge Function

**Verdict:** Use independent `supabase/functions/coach-follow-up/`.

**Why:**

- **OCR red line:** `analyze-chat` is the OCR-critical function. Even if the new branch does not call OCR helpers, editing and deploying `analyze-chat` increases blast radius on the path we have explicitly treated as fragile.
- **Isolation:** Spec 5 has a different request schema, response schema, prompt builder, telemetry events, and failure mode from screenshot / conversation analysis. A separate function gives cleaner review boundaries and avoids accidental fallthrough into `recognizeOnly`, `analyzeMode`, `images`, or partner-summary paths.
- **Cost machinery:** Reusing the opener quota pattern is still possible without sharing the whole `analyze-chat` surface. The implementation plan can either extract tiny subscription/quota helpers into a shared module or copy the minimal cost check/deduct sequence with tests. The cost of duplicating a small amount of quota logic is lower than coupling a new coach feature to the OCR baseline.

**Implementation-plan note:** If we create `coach-follow-up`, update `.github/workflows/deploy-edge-function.yml` to deploy it. Because `analyze-chat` still must deploy with `--no-verify-jwt`, do not hide the new function inside a broad "deploy all" step that obscures function-specific flags.

## Open Question Decisions

| Question | Codex verdict | Notes |
|---|---|---|
| Q1 Result card 5 vs 6 fields | 5 fields, with naming revision | Do not copy Spec 4's `learningLink`; Spec 5 v1 has no Learning link. Keep the card lean, but make `boundaryReminder` required. Suggested schema: `title/headline`, `observation`, `task`, `suggestedLine?`, `boundaryReminder`. |
| Q2 Client debounce | Yes | Disable the generate button while a request is in flight. This prevents double spend and duplicate overwrite races. |
| Q3 `lastConversationSummary` | Yes, but constrained | Use option (c), but only send a conversation-level summary capped at 200 chars. Do not send raw messages, `partnerSummary`, partner traits, or cross-conversation aggregate. If Spec 3 data quality is flagged, omit it unless the summary is clearly from the current conversation only. |
| Q4 Storage | Independent Hive box | Use `coach_follow_up_results`, keyed by `partnerId`, matching Partner Style Override / Data Quality patterns. Add `clearAll()` and partner-delete cascade tests. |
| Q5 Regenerate prefill | No | Do not persist answers in v1. Regenerate starts from empty choices. This keeps the "latest card only" privacy model honest. |
| Q6 Free tier | Free open, 1 credit | Approved. This is a demand-discovery feature. Free users should feel the product's coach loop, but it must share the same daily/monthly caps and successful-generation-only credit deduction. |
| Q7 Hint resolver location | Pure Dart function | Put it in a domain service with unit tests. Do not bury trigger logic in widgets. |
| Q8 Delete-account local cleanup | Client local cleanup | Since results are local Hive data, ensure the existing account-clear path clears the new box. Add a regression test like the Spec 1 `clearAll()` privacy test. |
| Q-Eric-1 post-date Q2 option | Product call, recommend add it | Add "太早看不出來" / "還看不出來". It reduces forced judgment and matches the low-pressure positioning. |
| Q-Eric-2 fourth phase for slow replies | Defer | "她回覆變慢" is valuable but likely becomes anxiety coaching / progress nudge. Keep v1 at 3 phases to avoid UI and prompt scope creep. |

## Prompt / Memory Boundary Review

The design correctly says Spec 5 needs a dedicated AI prompt. With the independent function amendment, that becomes concrete:

```text
supabase/functions/coach-follow-up/
  index.ts
  prompts.ts
  schemas.ts
  validate.ts
  README.md
```

Hard boundaries to preserve in the implementation plan:

- Reject `images` with `400 invalid_input_for_mode`.
- Do not import or call `buildAnalysisPrompt`, OCR helpers, screenshot parsers, or `PartnerContextResolver`.
- Do not read or write `partnerSummary`, `partnerTraits`, About Me, or Partner Style Override.
- Do not persist user answers; only persist the final latest result locally.
- Do not log free-text answers or prompt contents. Telemetry should stay at `{phase, tier, hasOptionalText, success/fail, latencyMs, model}`.

`partnerHint.name` can be display-only, but the prompt should not infer personality from it. `heatScore` and `gameStage` are acceptable as lightweight context. `lastConversationSummary` is acceptable only under the constraints above.

## Result Card Naming

I would slightly adjust the names before implementation:

```text
headline              -> title or headline
whatHappened          -> observation
oneThingToPractice    -> task
suggestedLine?        -> suggestedLine?
boundaryReminder      -> boundaryReminder (required)
```

Reason: `whatHappened` sounds like an event log, while this card is a coach interpretation. `oneThingToPractice` is semantically good but long for code and tests; `task` matches the Spec 4 mental model without copying the whole Spec 4 schema.

Visible UI can still use the friendlier labels:

- 我看到的重點
- 這次建議你做
- 先不要 / 邊界提醒
- 可以這樣說

## Free Tier Decision

I support Free tier access in v1.

Reasons:

- We need demand signal before deciding whether this becomes a paid differentiator.
- It costs only 1 message credit and shares existing caps.
- Free users already have limited monthly/daily usage, so the cap naturally prevents abuse.
- Hiding the coach loop behind paywall too early makes the product feel like a report tool, not a coach product.

Implementation detail: the UI should say `生成會使用 1 則額度`, and failed / invalid responses must not deduct.

## Overall Verdict

REVISED_AND_APPROVED once the design is amended to use a separate `coach-follow-up` Edge Function and the result card field names are tightened. After those edits, it is ready for an implementation plan. Do not write production code until Eric confirms Q-Eric-1 / Q-Eric-2 and CC updates the design doc accordingly.
