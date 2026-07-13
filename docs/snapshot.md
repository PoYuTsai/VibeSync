# VibeSync Snapshot

> Rewrite when the project phase changes. This file is the current-state anchor for Claude/Codex sessions.

## 2026-05-14 Current Focus Guardrail

Rotate / new sessions must treat this file plus `git log --oneline -15` as the source of truth.
Old chat memory, Claude persisted output, and terminal screenshots are supporting context only.

Do not revive archived roadmap labels or old planning tracks unless Eric explicitly asks.

Current state:

- Coach 1:1 is shipped into dogfood and is part of the core product.
- Older spec discussions are product fuel, not active task labels.
- Consumer-facing headline: `你專屬的 AI 約會教練`.
- Internal moat: VibeSync remembers the person, conversation, user intent, and coaching context, then helps users converge on a better next action.
- We are in TestFlight dogfood / App Review readiness stabilization.

Default priority:

1. P0/P1 dogfood bugs from Eric/Bruce.
2. Subscription, quota, RevenueCat, 429, paywall upgrade/downgrade safety.
3. Opener, analyze-chat, Coach 1:1 quality and UX stability.
4. App Review / launch-readiness cleanup.
5. Workflow tooling such as `!cc-rotate` and `!codex`.

## Recent Stabilization Train

Recent commit themes, newest first:

- Practice Hint／Debrief Claude-primary train（2026-07-14，branch `codex/no-canned-practice-ai`）：一般 chat 維持 DeepSeek；Beginner＋Game Hint／Debrief 改 Sonnet 單 writer、最多 3×24s，無同步二審與罐頭成功。user-fact 填答、經歷來源、單一下一句、Game 邀約分類與 hidden-scene 邊界已收斂；Deno 951/951，Edge `practice-chat` v129 production smoke 全 PASS。server 修正已 live；user-fact 視窗需新 TestFlight build。
- Analyze-chat full streaming is the current product path. The old user-visible two-stage quick/full plan is superseded; frontend legacy naming cleanup landed in `d12009e`. Backend `quick/full` compatibility remains hidden rollback / old-client support only.
- `!codex` Phase 1 read-only Discord review gate: `dfde5f2`, `ec84bb0`.
- `!cc-rotate` external/mobile session rotation and bootstrap hardening: `80ce48a` through `abd8200`.
- CC dogfood handoff, queue, and current-state correction: `8b748c4`, `050f50e`, `e111550`, `128879f`, `2f72839`.
- Opener/paywall/quota/RevenueCat P0 fixes:
  - `6b18863` Free quota thresholds.
  - `4184c75`, `7c19994`, `1f49470` opener/analyze malformed JSON protection.
  - `26790b4` format failure no quota charge.
  - `4954581` paid tier cannot regress to Free on transient RevenueCat miss.
  - `a01cb0f`, `6dc38a2`, `54c0906` Paywall package mapping/fallback fixes.
  - `f0546c0`, `ce4aa9e`, `e660bcd` RevenueCat client key and paid quota sync.
  - `5f267c5` opener draft/save path.

If a new session sees older memory claiming an archived roadmap label is the current track, override it with this snapshot.

## Active Risk Areas

High-risk changes require Codex review before telling Eric/Bruce the build is safe to test:

- subscription, paywall, quota, RevenueCat, 429
- auth, account deletion, Hive/local persistence
- `analyze-chat`, opener, OCR, Edge response schema
- AI prompt changes that affect reply quality, safety, or token/cost behavior

Free user rule:

- Free users must be able to try core features until monthly/daily quota is exhausted.
- When exhausted, show a clear quota/paywall path.
- Do not accidentally block first-use opener/analyze/coach before quota is actually consumed.

RevenueCat rule:

- App client uses public `appl_` SDK key.
- Server/Edge uses secret RevenueCat key.
- Paid tier must not be downgraded to Free just because RevenueCat temporarily returns empty or delayed entitlement data.

Paywall rule:

- Monthly/quarterly products must map by exact product/package id.
- Do not use fuzzy title matching.
- Upgrade/downgrade behavior must be safe for all Free/Starter/Essential monthly/quarterly paths.

Opener rule:

- Opener is a "pioneer" feature: generate a useful first move, cache/save the paid result, and make the next step into analyze-chat/Coach 1:1 clear.
- If AI returns raw JSON or malformed schema, repair/retry and do not show raw JSON to users.
- Format failure should not charge quota.

Coach 1:1 rule:

- Coach should be practical, grounded, non-judgmental, and on the user's side.
- It can discuss dating escalation, nightlife, sexuality, short-term intent, and safety maturely.
- It must still maintain consent, boundaries, STI/contraception, and personal safety reminders without becoming preachy.

Analyze-chat rule:

- Current analyze-chat UX is full streaming analyze. Do not revive the old two-stage quick/full UX unless Eric explicitly reopens that decision.
- Existing backend `responseMode: quick/full` and `analysis_runs` artifacts are compatibility / rollback surfaces, not the official user-visible analyze design.
- Reply suggestions should read the actual conversation.
- Prefer "接住情緒 -> 互動感 -> 順勢延伸" over summary-like suggestions.
- For multiple incoming messages, identify catchable points and when useful suggest split replies; not every point needs a reply.

## Current Workflow State

External/mobile mode:

- Discord listener runs via tmux / `~/.claude/channels/discord-vibesync/start.sh`.
- Use `!cc-rotate` to handoff and start a fresh CC session when context approaches the orange/red zone.
- `!cc-rotate` must read this snapshot, shared rules, newest OPEN queue item, latest handoff, and recent commits before taking work.
- Codex review is the read-only review gate. Codex does not edit files in external mode.
- Default 2026-06-26 workflow: Claude/CC does not self-trigger Codex as part of its own fix/feature flow. Claude/CC prepares a review packet; Eric routes it to a separate Codex review thread for the double-check. Direct `!codex review ...` from CC is opt-in only when Eric explicitly asks for that run.

Known setup note:

- Codex CLI in WSL may need one-time login: `codex login --device-auth`.
- Verify with `!codex setup`.

## Validation Baseline

Recent targeted validations have included:

- `flutter analyze` after major Flutter changes.
- opener service/cache unit tests.
- targeted Edge Function tests around schema, quota, and malformed JSON.
- local bridge tests for `!cc-rotate` and `!codex` wrappers.

Before claiming a fix is safe, state what was actually tested. Do not imply full regression if only targeted tests ran.

## Next Default Action

When Eric or Bruce reports a bug:

1. Acknowledge the specific reporter and symptom.
2. Ask for missing repro details if needed: build number, account/tier, expected vs actual, screenshots, exact steps, reproducibility.
3. Investigate root cause.
4. Fix only the scoped issue.
5. Run targeted tests.
6. Commit + push.
7. If high risk, trigger Codex read-only review before saying "safe to build/test".
