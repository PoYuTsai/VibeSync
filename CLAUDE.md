@AGENTS.md

# VibeSync Codebase Guide

> The import above is the authority on collaboration, authorization, delivery,
> and closeout. This file adds only the codebase map, commands, and conventions
> an agent needs before touching code.
>
> Hard limit: 250 lines, enforced by `scripts/hooks/pre-commit` (install with
> `ln -sf ../../scripts/hooks/pre-commit .git/hooks/pre-commit`). The hook also
> rejects dated history entries and completed-feature lists in this file — those
> belong in `docs/bug-log.md`, `docs/decisions.md`, and `docs/snapshot.md`.

## Repository Layout

| Path | What it is |
| --- | --- |
| `lib/` | Flutter app, ~418 Dart files, feature-first Clean Architecture |
| `test/` | ~388 Dart test files mirroring `lib/`, plus contract / lint / visual guards |
| `supabase/functions/` | Deno Edge Functions — the AI backend (~342 `.ts`, ~170 colocated tests) |
| `supabase/migrations/` | 85 SQL migrations; ledger reconciliation in `docs/migrations-ledger.md` |
| `ios/` `android/` `web/` `macos/` `windows/` `linux/` | Platform shells. `ios/VibeSyncKeyboard` + `ios/SharedKeyboard` are the AI keyboard extension (Swift) |
| `admin-dashboard/` | Separate Next.js ops dashboard with its own `package.json`, deployed to Vercel |
| `tools/` | Deno/Dart/Python eval harnesses, benchmarks, preflight scripts |
| `assets/` | Images, articles, ebooks, quizzes, practice photos, audio |
| `docs/` | Durable references; `docs/plans/README.md` lists what is still active |
| `.agent/` `contracts/` `.github/` | Execution contract, auth-callback contract, CI/CD |

Root documents: `AGENTS.md` (rules) · `DESIGN.md` (visual constitution) ·
`PRODUCT.md` (audience, tone, anti-references) · `CONTEXT.md` (coaching
vocabulary — stage snapshot, investment, memory chips; use these exact words in
code, prompts, and copy) · `CHANGELOG.md` (hotfix / rollback log).

## Flutter App (`lib/`)

Boot chain: `main.dart` → `CrashReporting.run` → Hive `StorageService` →
`SupabaseService` → `KeyboardTokenBridge` → `RevenueCatService` →
account-deletion cleanup replay → onboarding prime → local-notification gateway
→ `ProviderScope` → `app/app.dart` → `app/routes.dart` (go_router) →
`app/main_shell.dart` (three tabs: 首頁 / 我的報告 / 學習專區).

- `lib/core/` — `config/environment.dart` (`AppConfig`, selected by
  `--dart-define=ENV=dev|staging|prod`), `constants/app_constants.dart` (tier,
  quota, and scoring constants), `services/` (Hive storage, Supabase,
  RevenueCat, usage/quota, keyboard token bridge, account-deletion cleanup,
  social auth), `theme/`, `animation/`, `observability/` (Sentry).
- `lib/shared/` — cross-feature widgets (`widgets/brand/` is the brand kit) and
  services (image compression, screenshot preflight, link launching).
- `lib/features/<feature>/{data,domain,presentation}` is the standard triad:
  `domain/` holds entities and pure services with no Flutter dependency, `data/`
  holds repositories, Riverpod providers, and API clients, `presentation/` holds
  screens, sections, and widgets.
- `features/analysis/` additionally has `application/` with coordinators and
  `ports/` interfaces — the newest and cleanest pattern. Controllers depend on
  narrow ports; adapters live in `data/`. Follow it when a feature outgrows a
  single notifier.

Where the complexity is (Dart files per feature): `analysis` 87 ·
`practice_chat` 41 · `partner` 40 · `learning` 40 · `user_profile` 23 ·
`conversation` 20 · `coach_chat` 15 · `report` 14 · `subscription` 9 ·
`keyboard` 9 · `onboarding` 8 · `follow_up_notification` 8 · `opener` 7 ·
`new_topic` 7 · `coaching_memory` 6 · `coach_follow_up` 6 · `analysis_history` 5.

State management is Riverpod; providers are declared under
`features/*/data/providers/`. Local persistence is Hive CE with an AES-256
cipher whose key lives in `flutter_secure_storage`; adapters register through
the generated `lib/hive_registrar.g.dart`, never a hand-written list.

## Edge Functions (`supabase/functions/`)

| Function | Notes |
| --- | --- |
| `analyze-chat` | Streaming analysis, OCR, Opener, new topic, reply refine, billing/quota. Deployed with `--no-verify-jwt` |
| `practice-chat` | Practice room: chat FSM, hint/debrief single-shot, draw, moments (posts + generated images) |
| `coach-chat`, `coach-follow-up` | Coach 1:1 and follow-up; JWT-verified |
| `keyboard-reply`, `keyboard-assist` | iOS keyboard; excluded from the generic deploy workflow, migration-gated runbooks only |
| `revenuecat-webhook` | `--no-verify-jwt`; entitlement sync |
| `sync-subscription`, `submit-feedback`, `delete-account` | JWT-verified |
| `_shared/` | `quota.ts`, `model_rate_limit.ts`, `prompt_leak_guard.ts`, `banned_tokens.ts`, `traditional_chinese.ts`, `operational_error_monitor.ts` |

Tests are colocated (`foo.ts` + `foo_test.ts`). Several read migration SQL or
source text directly (`*_migration_source_test.ts`, `*_source_test.ts`,
`moments_*_migration_postgres_test.ts` via PGlite) so a schema or prompt change
cannot land without its migration and guards.

## Everyday Commands

Read `.agent/environment.json` before Git/Flutter/build/test work: the Git index
and Flutter artifacts belong to WSL; Windows runs only the listed read-only
commands. The contract carries routing and pins, never authorization.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs  # required before analyze
flutter analyze --no-fatal-infos
flutter test --concurrency=1              # serial: tests share Hive/Supabase globals
flutter test test/unit/<path>_test.dart   # start targeted, broaden with risk

deno check supabase/functions/<fn>/*.ts
deno test --allow-env --allow-read supabase/functions/<fn>

dart test/lint/slop_baseline_generator.dart  # only to tighten after paying design debt
```

Most `.g.dart` files are committed, but `lib/hive_registrar.g.dart` is not, and
`storage_service.dart` imports it — so `flutter analyze` reports hundreds of
phantom errors until `build_runner` has run. No freezed in this project; codegen
is Hive adapters only.

## Testing Conventions

| Directory | Purpose |
| --- | --- |
| `test/unit/` | ~209 files: entities, services, repositories, config, plus `android/` and `workflows/` contract tests that parse real manifest XML and workflow YAML |
| `test/widget/` | ~130 files: screens, shared widgets, app shell |
| `test/visual_proof/` | ~33 files: render PNG evidence for design changes |
| `test/lint/` | Mechanical guards: `slop_ratchet_test.dart` + `slop_baseline.json`, font/chip/asset-parity guards |
| `test/helpers/`, `test/mocks/`, `test/fixtures/` | In-memory repositories, widget harnesses, shared fixtures |
| `test/integration/`, `test/features/`, `test/tools/` | Cross-layer flows and tool recorders |

- Always run the suite with `--concurrency=1`; parallel workers produce false
  reds because Hive and Supabase state is process-global.
- The slop ratchet compares `lib/` against `slop_baseline.json` for four
  mechanically detectable design defects (sub-12px text, out-of-scale radii,
  non-allowlisted colored shadows, hard-coded `Color(0x…)` outside the theme).
  Over baseline is red. Never regenerate the baseline to admit new slop —
  register a deliberate exception in `DESIGN.md` §7 and `slop_scan.dart`.
- Visual changes need a before/after PNG comparison for Eric before commit.
- New Edge test files must be added to the explicit allowlist in
  `.github/workflows/flutter-ci.yml`, or they never run in PR CI.

## CI And Delivery Surfaces

| Workflow | Trigger | What it gates |
| --- | --- | --- |
| `flutter-ci.yml` | PR to `main` | Edge contracts (Deno check + allowlisted tests + PGlite), iOS keyboard compile on macOS, `flutter analyze` + full serial test suite |
| `distribute.yml` | push to `main`/`develop`, dispatch | Flutter gate, keyboard gate, Android APK + install smoke + Firebase distribution, signed iOS IPA artifact |
| `deploy-edge-function.yml` | push to `main` touching `supabase/functions/**` | Redeploys the generic function set one by one, with per-function JWT flags |
| `deploy-keyboard-assist.yml` | dispatch only | Single migration-gated keyboard function |
| `deploy-web.yml` | push to `main` | Flutter web → Vercel |
| `release.yml` | dispatch only | TestFlight / Play submission — Eric's manual action, agents never trigger it |
| `discord-notify.yml` | labels, closed PRs, workflow runs | Metadata-only handoff notifications; never checks out PR code |

All workflows pin Flutter 3.47.0 and pin actions by commit SHA. Those pin
sources are listed in `.agent/environment.json`, so a Flutter bump must update
every workflow together.

## Conventions That Bite

- Commit messages are Traditional Chinese, one commit per concern.
- User-visible copy is Traditional Chinese; `PRODUCT.md` sets the tone and
  `CONTEXT.md` fixes the vocabulary. `約會教練` is retired — the category word is
  `戀愛教練`.
- Deterministic text problems (你/妳, simplified/traditional, punctuation) are
  fixed in data-layer helpers such as `outgoing_message_text`, never by adding
  another prompt rule.
- Client and server constants are mirrored by hand: `AppConstants` quota and
  draw limits mirror `draw_decision.ts` and `billing.ts` in the Edge Functions.
  Change one, change both.
- Visible investment score maxes at 90 (`investmentVisibleMax`); the server
  finalizes as `ceil(raw × 0.9)`. Never render `/100`.
- `.gitattributes` forces LF everywhere to stop WSL/Windows CRLF drift.
- Never run `supabase db push`; use the targeted migration procedure in
  `docs/shared-agent-rules.md`.
- Free users keep core access until quota is actually exhausted. Format,
  deadline, and model-limit failures must not charge quota or look like a
  paywall.
- Secrets: the app ships the public RevenueCat `appl_` key; Edge Functions use
  the secret key. `.env` is never committed — see `.env.example`.

## Where To Look Next

Load on demand only, per the context rules in the import above:
`docs/snapshot.md` (current stage) · `docs/shared-agent-rules.md` (migration,
Edge delivery, high-risk review, closeout) · `docs/decisions.md` ·
`docs/bug-log.md` · `docs/integrations/` (auth, RevenueCat, Sentry, funnel) ·
`docs/reviews/` · `docs/plans/README.md` · `docs/ai-harness/context-management.md`.
