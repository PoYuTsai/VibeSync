# `coach-follow-up` Edge Function

Spec 5 Coach Follow-up v1 — produces a structured 5-field follow-up suggestion card for a partner detail screen, conditioned on user-selected `phase` plus light context.

> **Status:** Phase A T1 skeleton. Full request/response handling lands in T2-T8.
> **Spec:** `docs/plans/2026-05-02-spec5-coach-follow-up-v1-design.md` @ `a66ca5b`
> **Plan:** `docs/plans/2026-05-02-spec5-coach-follow-up-v1-impl.md`

---

## 1. Architecture rules (non-negotiable)

- **Independent** Edge function — sibling of `analyze-chat`, **NOT** a sub-mode.
- **Zero imports** from `supabase/functions/analyze-chat/**` (OCR baseline isolation; CLAUDE.md rule).
- **JWT-verified deploy** — no `--no-verify-jwt` flag. Authenticated user is required to deduct credit.
- **Rejects `images`** field at request validation (`400 invalid_input_for_mode`). v1 is text-only.
- **Never reads/writes** `partnerSummary`, `partnerTraits`, About Me, Partner Style Override, or any long-term memory layer.
- **Never logs** user free-text answers (`q3`), prompt full text, or Claude raw response.

## 2. Phase semantics (design §1.3 / §2.4)

| `phase` | Use case |
|---------|----------|
| `prepareInvite` | 還沒約 / 想約但沒開口 / 開口了沒成 |
| `preDateReminder` | 已經約成、要見面 |
| `postDateReflection` | 剛見完 / 短期內見完，需要復盤節奏 |

Phase keys are stable English `.name` values (used in request payload, telemetry, and Hive storage). 繁中 lives only in client-side `displayLabel` getters.

## 3. Result card (response.card — design §1.3)

| Schema field | UI label | Cap | Required |
|--------------|----------|-----|----------|
| `headline` | (bold, no label) | ≤ 30 字 | ✅ |
| `observation` | 我看到的重點 | ≤ 80 字 | ✅ |
| `task` | 這次建議你做 | ≤ 30 字 | ✅ |
| `suggestedLine` | 可以這樣說 | ≤ 80 字 | optional (nullable) |
| `boundaryReminder` | 邊界提醒 | ≤ 60 字 | ✅ **never null** |

`boundaryReminder` is hard-required server-side. Missing/null → 5xx, **credit NOT deducted**.

## 4. Tone & banned vocabulary (design §2.4)

Hard rules baked into `prompts.ts` AND enforced as a server validator (`assertCardSafe` in `validate.ts`):

- 絕不教用戶裝冷淡 / 用話術逃避責任 / 用承諾綁住對方。
- 絕不出現以下字眼：`收割 / 控住 / 壞女人 / 玩咖 / 高分妹 / 攻略 / PUA`。
- 失敗 / 拒絕 / 對方變淡情境必須降低焦慮、不製造焦慮。
- `partnerHint.name` 純粹拿來 display；prompt 不可從 name 推測對方性格 / 文化背景 / 任何屬性。

Response containing any banned token → 5xx `banned_token`, **credit NOT deducted** (defense-in-depth: prompt guardrail + validator).

## 5. Cost & quota

- Cost = **1 credit** per successful generation.
- Test account email (`vibesync.test@gmail.com`) bypasses cap and is not charged.
- Quota gate runs the same edge-case matrix as `analyze-chat`:
  - Subscription self-heal (missing row → insert as free).
  - Daily / monthly counter reset before cap evaluation.
  - RevenueCat tier refresh attempt on cap exceeded (in case of stale tier).
  - Unknown / null tier → fallback to free limits.
- Deduct happens **only after** schema validation **AND** banned-token check pass.

## 6. Telemetry (design §7)

Server-side events (no free-text / prompt / Claude response leaked):

```
coach_follow_up_invoked    { phase, tier, hasOptionalText: bool }
coach_follow_up_succeeded  { phase, tier, model, latencyMs, costDeducted: 0|1 }
coach_follow_up_failed     { phase, tier, errorClass }   // enum, not free-text
```

Client-side events (`coach_follow_up_regenerated`, `coach_follow_up_phase_switched`) live in the Flutter layer.

## 7. Local dev sanity

```bash
deno run --allow-net index.ts
curl http://localhost:8000/        # → 200 {"status":"ok","function":"coach-follow-up"}
curl -X POST http://localhost:8000/ # → 501 {"error":"not_implemented"} (T1 skeleton only)
```
