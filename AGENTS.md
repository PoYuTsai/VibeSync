# VibeSync Project Context

> Shared project guidance for Codex and Claude Code. Keep this file lean; load detailed docs only when the task needs them.

## Product

- VibeSync is an AI dating coach for Traditional Chinese users.
- Current stage: TestFlight dogfood and App Review readiness stabilization.
- Core product: Coach 1:1, Opener, analyze-chat, and Practice.
- Stack: Flutter, Riverpod, Supabase Auth/Postgres/Edge Functions, RevenueCat, and encrypted Hive.

## Authority And Routing

- Eric describes the outcome in natural language. The active Codex or Claude host is the primary brain and integration owner.
- Do not assign permanent “coder” or “reviewer” roles to a provider. Use the global adaptive router and only the workflows callable on the current host.
- Keep one owner for each implementation phase. Use independent cross-model review only when risk or uncertainty justifies it.
- Product feel and consequential product/payment/data tradeoffs remain Eric's decision.

## Context Loading

- Do not automatically read `docs/snapshot.md`, `docs/shared-agent-rules.md`, review queues, old plans, handoffs, logs, or git history at session start.
- Start from the current request, `git status`, nearby code, relevant tests, and the smallest useful document section.
- Read `docs/snapshot.md` only for project-stage orientation or a real handoff.
- Read `docs/shared-agent-rules.md` only for migration, deployment, high-risk review, or closeout details.
- Search `docs/reviews/ai-arbitration-queue.md` only when the task concerns an explicitly open review item.
- Prefer current code, tests, live service evidence, and recent commits over old chat memory or screenshots.

## Critical Gotchas

- High-risk areas: subscription/paywall/quota/RevenueCat/429, auth/account deletion/Hive, `analyze-chat`, Opener, OCR, Edge schemas, and AI prompt/token/cost behavior.
- Free users keep core access until quota is actually exhausted. Model limits and format failures are not paywalls.
- Never run `supabase db push` against production. Use the targeted migration procedure in `docs/shared-agent-rules.md`.
- `analyze-chat` deployment requires `--no-verify-jwt`.
- OCR changes stay isolated unless the task explicitly requires a cross-cutting change.
- Never expose or commit secrets, `.env` contents, customer data, or production credentials.

## Work And Verification

- Inspect the working tree before editing and preserve unrelated user changes.
- Keep one commit to one concern and use Traditional Chinese commit messages.
- Verify with the smallest meaningful command, then broaden in proportion to risk.
- For material R2/R3 high-risk changes, invoke the configured opposite-frontier reviewer and GLM falsification pass directly through the shared review workflow. Do not ask Eric to carry a Review Packet manually.
- Treat implemented, verified, committed, pushed, deployed, and dogfood-approved as separate states.
- Push, deployment, TestFlight submission, production mutation, and other external actions require Eric's explicit authorization.

## On-Demand References

- Current stage: `docs/snapshot.md`
- Operational rules: `docs/shared-agent-rules.md`
- Product decisions: `docs/decisions.md`
- Durable bug history: `docs/bug-log.md`
- Launch: `docs/testflight-regression-checklist.md`, `docs/app-review-final-checklist.md`, `docs/launch-readiness-checklist.md`
- Integrations: `docs/integrations/`
- Reviews: `docs/reviews/`
- Context design: `docs/ai-harness/context-management.md`
