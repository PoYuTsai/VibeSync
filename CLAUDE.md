# VibeSync

> AI dating coach app for Traditional Chinese users.
> This file is the short project entry point for new Claude/Codex sessions.
> Durable details live in `docs/`; do not let this file become a changelog.

---

## Hard Rule: Current Truth Source

New sessions must not trust old chat memory, Claude persisted output, or screenshots of previous terminal context.

First load, in this order:

1. `docs/snapshot.md`
2. `docs/shared-agent-rules.md`
3. `git log --oneline -15`
4. newest OPEN item in `docs/reviews/ai-arbitration-queue.md`
5. latest handoff if one exists

If memory conflicts with the files above, trust the files and latest commits.

Current product state as of 2026-05-14:

- Coach 1:1 is already shipped into dogfood and is part of the core product.
- Analyze-chat, opener, paywall, quota, RevenueCat, and TestFlight dogfood are the active stabilization tracks.
- Do not revive archived roadmap labels or old planning tracks unless Eric explicitly asks.
- We are in pre-review / pre-launch stabilization, not large feature expansion.

---

## Keep Out Of This File

| Content | Correct place |
| --- | --- |
| Bug timelines | `docs/bug-log.md` |
| Finished feature lists | `git log` or `docs/snapshot.md` |
| Architecture decisions | `docs/decisions.md` |
| Third-party setup details | `docs/integrations/*.md` |
| Low-frequency CLI commands | `README.md` |
| Live dogfood queue | `docs/reviews/ai-arbitration-queue.md` |
| Shared Claude/Codex workflow rules | `docs/shared-agent-rules.md` |

Freshness rule: if a rule is temporary, add an expiry date or move it to the right doc.

---

## Current Priority

Default priority order:

1. P0/P1 TestFlight dogfood bug fixes.
2. Subscription, quota, RevenueCat, 429, upgrade/downgrade safety.
3. Opener, analyze-chat, Coach 1:1 quality and UX stability.
4. App Review / launch-readiness checklist.
5. Workflow tooling such as `!cc-rotate` and `!codex`.

Do not start big roadmap work while a dogfood P0/P1 is open.

---

## Product Overview

Target users: 20-35 year-old Traditional Chinese users who want better dating and social conversation.

Positioning:

- Not a generic LLM chat app.
- VibeSync remembers the person, conversation context, user intent, and coaching history.
- It helps users converge on emotionally intelligent next actions instead of only generating many generic replies.
- Coaching style: practical, grounded, on the user's side, mature about boundaries and consent.

Core surfaces:

- Home: partner list, new conversation, screenshot import, opener entry, new-user guide.
- Analysis: heat score, stage, "本回合怎麼接", suggested replies, coach entry, continue conversation.
- Coach 1:1: follow-up coaching with memory and quota charging only on successful generation.
- Opener: screenshot/manual profile opener, cached draft, follow-up path into conversation analysis.
- Report: radar, health score, trend, Starter/Essential only.
- Learning: 20 Traditional Chinese articles plus practice entry.

Core AI rules:

- 1.8x rule: reply length should usually be no more than 1.8x the other person's message.
- Read the actual Chinese context. Some questions invite answers; some are frames to avoid.
- Prefer "接住情緒 -> 互動感 -> 順勢延伸" over summary-like replies.
- For opener, prioritize curiosity, light frame, and easy-to-reply hooks over long sincere paragraphs.

---

## OCR Stable Baseline

Fresh until: 2026-06-30.

```text
Current OCR-stable baseline: 28c0965
```

Hard rules:

- OCR changes must be isolated in their own commit.
- Do not mix OCR with security, cache, parser, prompt, or multi-agent changes.
- Do not run broad multi-agent optimization on the OCR core path.
- `analyze-chat` deploy must use `--no-verify-jwt`.

Known root cause from 2026-04-05: OCR broke when Edge Function moved to platform JWT verification. If OCR deploy breaks, check `.github/workflows/deploy-edge-function.yml` before changing app code.

Details: `docs/2026-04-05-ocr-rollback-note.md`

---

## Tech Stack

- Frontend: Flutter 3.x, Riverpod, fl_chart.
- Backend: Supabase Auth / Postgres / Edge Functions.
- AI: Claude API. Environment variable must be `CLAUDE_API_KEY`, not `ANTHROPIC_API_KEY`.
- Subscription: RevenueCat, 4 products: monthly + quarterly for Starter and Essential.
- Local DB: Hive with AES-256 encryption.

Model policy:

- Free: Haiku.
- Starter / Essential: Sonnet.
- Any image input: force Sonnet.

Key resources:

| Resource | Value |
| --- | --- |
| Supabase project | `fcmwrmwdoqiqdnbisdpg` |
| Edge Functions | `analyze-chat`, `coach-chat`, `coach-follow-up`, `submit-feedback`, `sync-subscription`, `revenuecat-webhook`, `delete-account` |
| Bundle ID | `com.poyutsai.vibesync` |
| Team ID | `TTQHTVG8CC` |
| Test account | `vibesync.test@gmail.com` |
| Web preview | `https://web-beta-tawny.vercel.app` |

Subscription quotas:

| Tier | Monthly | Daily | AI |
| --- | ---: | ---: | --- |
| Free | 30 | 15 | Haiku |
| Starter | 300 | 50 | Sonnet |
| Essential | 800 | 120 | Sonnet |

Free users must be able to try core features until quota is exhausted, then get a clear paywall path.

---

## Common Pitfalls

- Hive access before `StorageService.initialize()`.
- Riverpod provider not disposed; use `autoDispose` when appropriate.
- External APIs without try/catch and user-facing fallback.
- Flutter Web with `dart:io`.
- Edge Function cold starts without loading / timeout state.
- New Edge Function variable name collision; grep before adding common names.
- RevenueCat tier sync can temporarily regress users to Free if not protected.
- Paywall package selection must use exact product/package mapping, not fuzzy title matching.
- App client uses RevenueCat public SDK key (`appl_...`); server/Edge uses secret key.
- Opener image payload must use `ImageData`, not raw base64 string.
- Partner delete must guard by actual conversation count, not aggregate rounds.

---

## Git And Testing

Git:

- Traditional Chinese commit messages.
- One commit = one concern.
- Commit then push immediately.
- Never revert or reset user changes unless explicitly asked.

Tests:

```bash
flutter test
flutter test test/unit/services/foo_test.dart
flutter test --coverage
```

Edge deploy example:

```bash
SUPABASE_ACCESS_TOKEN=sbp_xxx npx supabase functions deploy analyze-chat \
  --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg
```

---

## Debugging Protocol

For bugs:

1. Record in `docs/bug-log.md` if it is durable.
2. Find root cause, not only surface symptom.
3. Add or run targeted tests.
4. If it is a new recurring trap, update Common Pitfalls or `docs/shared-agent-rules.md`.
5. Commit and push.

High-risk fixes require Codex review before telling Eric/Bruce the build is safe:

- subscription, paywall, quota, RevenueCat
- auth, data deletion, Hive schema
- `analyze-chat`, opener, OCR, Edge response schema
- AI prompt or token/cost behavior

External mode uses `!codex review latest` / `!codex result <job-id>` as defined in `docs/shared-agent-rules.md`.

---

## Claude / Codex Collaboration

Shared workflow source: `docs/shared-agent-rules.md`.

Default roles:

- Claude: Flutter UI, product flow, copy, frontline dogfood fixes.
- Codex: code review, OCR, algorithmic logic, performance, refactor plans, adversarial checks.
- External/mobile mode: Claude fixes first-line bugs; Codex is read-only review gate.
- At home mode can use multiple review sessions, but durable findings still go into docs/queue/commits.

Anti echo-chamber:

- Codex review must cite evidence.
- Do not say "Codex approved" without a job id/result, review doc, queue update, or linked commit.
- Two review rounds maximum; unresolved P1/P2 becomes `WAITING_ON_ERIC`.

---

## Docs Pointer

| Need | File |
| --- | --- |
| Current stage | `docs/snapshot.md` |
| Shared agent workflow | `docs/shared-agent-rules.md` |
| Dogfood/review queue | `docs/reviews/ai-arbitration-queue.md` |
| Bug history | `docs/bug-log.md` |
| ADRs | `docs/decisions.md` |
| TestFlight checklist | `docs/testflight-regression-checklist.md` |
| App Review checklist | `docs/app-review-final-checklist.md` |
| Launch readiness | `docs/launch-readiness-checklist.md` |
| RevenueCat | `docs/integrations/revenuecat.md` |
| Auth | `docs/integrations/auth.md` |
| Pricing | `docs/pricing-final.md` |
| OCR benchmark | `docs/ocr-analysis-maturity-benchmark.md` |
| Discord rotate tooling | `tools/cc-rotate/README.md` |
| Discord Codex bridge | `tools/codex-bridge/README.md` |
