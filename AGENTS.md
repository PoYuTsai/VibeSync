# VibeSync

> AI dating coach app for Traditional Chinese users.
> Lean always-on entry for Claude/Codex. Durable detail lives in `docs/`.

## Current Truth

At every new session, rotation, or handoff, load only this bootstrap set first:

1. `docs/snapshot.md`
2. `docs/shared-agent-rules.md`
3. `git log --oneline -15`
4. newest `OPEN` item in `docs/reviews/ai-arbitration-queue.md`
5. latest handoff if one exists

Trust those files and latest commits over old chat memory, persisted output, or terminal screenshots.
`CLAUDE.md` and `AGENTS.md` must stay byte-for-byte synchronized and must not contain injected memory blocks.

## Current Stage

VibeSync is in TestFlight dogfood / App Review readiness stabilization. Coach 1:1 is core product.

Default priority:

1. P0/P1 dogfood bug fixes.
2. Subscription, quota, RevenueCat, 429, paywall upgrade/downgrade safety.
3. Opener, analyze-chat, Coach 1:1 quality and UX stability.
4. App Review / launch readiness.
5. Workflow tooling such as Discord rotation and Codex review gate.

## Tech Stack

- Frontend: Flutter 3.x, Riverpod, `fl_chart`.
- Backend: Supabase Auth / Postgres / Edge Functions.
- AI: Claude API. Server env var is `CLAUDE_API_KEY`, not `ANTHROPIC_API_KEY`.
- Subscription: RevenueCat, monthly + quarterly for Starter and Essential.
- Local DB: Hive with AES-256 encryption.
- Models: every customer-facing Claude primary path outside Practice uses Sonnet 5: Free/paid Analyze, Opener, Coach/Follow-up, Keyboard, and images. Practice stays DeepSeek-first with its existing tiered Claude failover/reviewer; `analyze-chat` alone keeps 4.6 then Haiku as an outage fallback. Test-only forced models are not production routing.

## Workflow

- One commit = one concern. Use Traditional Chinese commit messages. Commit and push after finished work.
- Bugs: find root cause, run targeted tests, and write durable history only when needed.
- High-risk fixes need Codex review evidence before saying dogfood/build is safe.
- High-risk zones: subscription/paywall/quota/RevenueCat, auth/delete/Hive, `analyze-chat`, opener, OCR, Edge schemas, AI prompt/token/cost behavior.
- OCR changes stay isolated. `analyze-chat` deploy uses `--no-verify-jwt`.
- Free users must keep core access until quota is actually exhausted.

## Context Budget

- Keep root always-on files short, synchronized, and near 3.5 KB each.
- Do not paste long docs, old plans, test logs, `/context` output, or command dumps into agent files or chat.
- Read docs on demand, then summarize only the needed facts.
- Slash commands must not auto-inject file or shell output by default.
- Project skills must be VibeSync-specific. Quarantine generic skills under `.claude/skills.disabled/`.
- If a fresh session still starts large, inspect global/user skills, plugins, MCP metadata, and hooks before blaming project docs.

## Docs Index

- Current truth: `docs/snapshot.md`, `docs/shared-agent-rules.md`, `docs/reviews/ai-arbitration-queue.md`
- History and decisions: `docs/bug-log.md`, `docs/decisions.md`, `docs/reviews/`
- Launch: `docs/testflight-regression-checklist.md`, `docs/app-review-final-checklist.md`, `docs/launch-readiness-checklist.md`
- Integrations: `docs/integrations/revenuecat.md`, `docs/integrations/auth.md`, `docs/pricing-final.md`
- AI/OCR: `docs/ocr-analysis-maturity-benchmark.md`, `docs/2026-04-05-ocr-rollback-note.md`
- Harness: `docs/ai-harness/context-management.md`, `tools/cc-rotate/README.md`, `tools/codex-bridge/README.md`

## Links

- Supabase project: `fcmwrmwdoqiqdnbisdpg`
- Edge Functions: `analyze-chat`, `coach-chat`, `coach-follow-up`, `practice-chat`, `keyboard-reply`, `submit-feedback`, `sync-subscription`, `revenuecat-webhook`, `delete-account`
- Bundle ID: `com.poyutsai.vibesync`
- Team ID: `TTQHTVG8CC`
- Test account: `vibesync.test@gmail.com`
- Web preview: `https://web-beta-tawny.vercel.app`
