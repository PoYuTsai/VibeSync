# Keyboard Assist Production Deployment — 2026-07-27

Status: **production backend enabled for all authenticated release users; authenticated iPhone proof pending**

Project ref: `fcmwrmwdoqiqdnbisdpg`

## Source state

- `90df6872` — keyboard screenshot consent and account-cleanup wiring.
- `c5fc2433` — split the recent-screenshot `filter` and `max` operations to fix the Swift parser failure found by GitHub Actions.
- `a4935fc6` — add production guards for the exact Claude model contract, secret preflight, migration grants, and generic-deploy exclusion.
- The two release-guard commits contain the exact ASCII marker `[skip actions]`. They were pushed to `main` without triggering the generic Edge, web, or TestFlight workflows.
- The worktree was clean before production mutation.

## Migration evidence

Only `20260727130000_keyboard_assist_exactly_once.sql` was pending. It was applied with:

```powershell
supabase migration up --linked --yes
```

`supabase db push` and `--include-all` were not used.

Post-migration checks passed:

- Local and remote migration ledgers are aligned.
- `keyboard_assist_contract_version()` returns `keyboard-assist-v1`.
- `keyboard_assist_hmac_key_versions()` initially returns an empty array.
- `public.keyboard_assist_requests` has RLS enabled and zero rows at deployment time.
- `PUBLIC`, `anon`, and `authenticated` cannot access the replay table or the nine Keyboard Assist RPCs.
- `service_role` has the required table and RPC privileges.
- Exactly one active cleanup cron exists at `37 * * * *`.

## Production configuration

The existing `CLAUDE_API_KEY` was preserved. The following configuration names are present; no secret values were printed or persisted in deployment evidence:

- `KEYBOARD_ASSIST_COMPILER_MODEL`
- `KEYBOARD_ASSIST_JUDGE_MODEL`
- `KEYBOARD_SCREENSHOT_PIPELINE_VERSION`
- `KEYBOARD_ASSIST_HMAC_CURRENT_VERSION`
- `KEYBOARD_ASSIST_HMAC_KEYS_JSON`
- `KEYBOARD_SCREENSHOT_V1_ALLOWLIST`
- `KEYBOARD_SCREENSHOT_V1_ENABLED`

The compiler and judge are both pinned to the exact `claude-sonnet-5` model ID. Sonnet 5 thinking is explicitly disabled and non-default sampling parameters are omitted.

The HMAC key was generated from 32 cryptographically random bytes, validated as canonical Base64 in memory, and not written to disk or terminal output.

Deployment began with the feature flag off. After the function gates passed, the allowlist and flag were set together to:

- allowlist: `vibesync.test@gmail.com`
- enabled: `true`

An empty allowlist was never used while the flag was enabled.

## Edge Function evidence

The new function was deployed independently of the generic workflow:

```powershell
supabase functions deploy keyboard-assist `
  --project-ref fcmwrmwdoqiqdnbisdpg `
  --use-api
```

`--no-verify-jwt` and `--prune` were not used.

Final live state:

- `keyboard-assist` version `2`
- status `ACTIVE`
- `verify_jwt=true`
- all 13 expected Edge Functions are present and active
- the 12 pre-existing functions retained their exact versions across the targeted deploy
- an unauthenticated `GET /functions/v1/keyboard-assist?capability=1` returns `401`
- the production secret-name preflight passes

An independent read-only production audit repeated the migration-ledger, 13-function inventory, secret-name, RLS, 9/9 RPC-grant, cleanup-cron, and unauthenticated-401 checks. It returned **PASS with no blocker** and made no production changes.

### Validation-harness incident

The first targeted deployment reached production, but an immediate function-list check ran before Supabase propagation completed. The safe fallback deleted only `keyboard-assist`; no existing function changed.

The second deployment also produced a local false negative because Windows PowerShell 5 treated the JSON array as one pipeline object and an interpolated probe URL lacked explicit variable boundaries. The attempted fallback did not match or delete the target for the same parsing reason. Direct per-row iteration and a corrected URL then proved the final live state above. No pre-existing function, migration, or data was rolled back.

## Verification boundary

No reusable password or authenticated test JWT is stored locally or in GitHub, so the deployment agent could not safely perform the authenticated capability check or a real Claude request.

The first authenticated proof must therefore come from the iPhone signed in as `vibesync.test@gmail.com`. That test will validate:

- allowlist propagation and `capability.enabled=true`
- shared-Keychain authentication from the keyboard extension
- PhotoKit access and the three-minute screenshot window
- the Claude compiler/judge request path
- exact replay, payload-mismatch, speaker-confirmation, and quota behavior

## iOS build state

GitHub Actions run `30276550353` passed Flutter distribution gates, the full Flutter test suite, and Android. Its macOS job found a Swift parser error in `LatestScreenshotProvider.swift`; commit `c5fc2433` fixes that expression and passed independent static review.

Windows cannot run Xcode, so `c5fc2433` is not yet proven by a macOS compile. A new GitHub Actions TestFlight build from current `main` is the required next gate before device testing.

## Device smoke sequence

1. Install the new TestFlight build and open VibeSync once while signed in as `vibesync.test@gmail.com`.
2. Enable the VibeSync keyboard and Allow Full Access.
3. Grant the in-app screenshot-AI consent and Photos access.
4. Take a fresh LINE conversation screenshot, then open that LINE conversation and switch to the VibeSync keyboard within three minutes.
5. Verify preview, confirmation, optional left/right speaker selection, three distinct reply strategies, and candidate insertion.
6. Retry the same request to verify replay stability; a changed image under the same request ID must fail safely.
7. Confirm speaker-selection requests do not consume quota and a completed ready response consumes quota only once.

## Rollback

The first rollback action is:

```text
KEYBOARD_SCREENSHOT_V1_ENABLED=false
```

The additive migration, replay ledger, and HMAC key version must remain. Version 1 must be retained until at least 25 hours after its last referenced ledger row. For an urgent provider or privacy incident, disable the function in addition to turning off the flag.

## Public release rollout — 2026-07-28

Eric explicitly replaced the original single-account dogfood rollout with a
release rollout for all authenticated users. The allowlist secret name remains
present for release preflight, while its comma-separated value normalizes to
zero entries. The checked-in server contract treats a normalized empty list as
allowing any user who already passed Supabase JWT authentication.

No client code, Edge source, database migration, quota rule, model setting,
HMAC key, or consent rule changed. Supabase documents production secret updates
as immediately available without a redeploy. A targeted redeploy of the same
reviewed `keyboard-assist` source was nevertheless performed after the secret
update to force fresh runtime instances and remove warm-isolate ambiguity.

Post-rollout evidence:

- `deno test --allow-read supabase/functions/keyboard-assist`: 56 passed,
  0 failed.
- The remote allowlist digest exactly matches the intended normalized-empty
  configuration; the enabled flag digest remains unchanged.
- The release secret-name preflight still passes.
- The local and remote migration ledgers remain aligned through
  `20260727130000`; no migration was applied.
- `keyboard-assist` is version 4, `ACTIVE`, and `verify_jwt=true`.
- All 13 expected production Edge Functions remain present.
- Capability requests with no bearer token and with a malformed bearer token
  both return `401`.
- `Release to App Stores` run `30288463267` completed successfully for
  `bf9c45d5`; the runtime rollout is not embedded in the IPA and did not require
  another iOS build.
- Claude Fable and GLM 5.2 independently challenged the rollout. Their
  warm-isolate, quoting, preflight, workflow, and negative-auth concerns were
  checked against source and addressed by the exact quoted CLI command,
  post-change secret-name preflight, targeted runtime redeploy, and two
  unauthenticated probes.

The remaining positive proof belongs on physical iPhones because no reusable
user JWT is stored for deployment automation. Eric and a previously
non-allowlisted partner account must each install the new TestFlight build,
open VibeSync once while signed in, reopen the keyboard, and complete the
preview-to-three-candidates flow. A ready result charges the partner account
normally; speaker-side confirmation remains zero-charge.

To shrink the rollout back to the original cohort, restore
`KEYBOARD_SCREENSHOT_V1_ALLOWLIST` to `vibesync.test@gmail.com`. For urgent
containment, set `KEYBOARD_SCREENSHOT_V1_ENABLED=false`. Do not roll back the
migration or HMAC keyring.


## Contract update deployment — 2026-07-28

`keyboard-assist` was redeployed to version `5` for the screenshot assist
upgrade. Two additive contract changes shipped together:

- Request gains an optional `priorTurn` (`offeredTexts`, `insertedText`). Absent
  is treated as null, so a keyboard build that predates the field is unaffected.
  It never introduces facts; it stops the next batch repeating itself and lets
  the server reject a transcript that contains this keyboard's own previous
  candidates. That rejection returns `unsupported_conversation` and is therefore
  never charged.
- Ready results gain `alternates`, a second batch of three candidates produced
  by the same judge call. The compiler already generated six candidates and
  three were discarded; serving both batches makes "換一批" cost no second
  request and no second charge. Absent `alternates` still validates, so results
  stored before this change continue to replay.

The replay input hash deliberately still excludes `priorTurn`: a same-payload
retry is rebuilt from stored pending metadata, which cannot reproduce the hint,
so hashing it would turn a safe retry into a `409`.

Delivery path repair: `keyboard-assist` is excluded from
`deploy-edge-function.yml` both by push path and by deploy list, which left the
only path as a local `supabase` CLI invocation that Eric's Windows host cannot
run. `.github/workflows/deploy-keyboard-assist.yml` now reproduces the
checked-in runbook as a manual-dispatch workflow: one function, no
`--no-verify-jwt`, no `--prune`, gated on `deno test` and the production
secret-name preflight, verified afterwards. It deploys source only and never
applies a migration or writes a secret. The push-trigger exclusion is unchanged.

Evidence — `Deploy Keyboard Assist` run `30299835205` (`3123bade`):

- `deno test --allow-read supabase/functions/keyboard-assist`: 68 passed,
  0 failed.
- The production secret-name preflight passed; no secret was added or changed.
- `keyboard-assist` is version `5`, `ACTIVE`.
- All 13 expected Edge Functions remain present; the other 12 kept their exact
  versions across the targeted deploy.
- An unauthenticated `GET /functions/v1/keyboard-assist?capability=1` returns
  `401`.
- No migration was applied; the local and remote ledgers remain aligned through
  `20260727130000`.

The consent version moved to `keyboard_screenshot_ai_202607_v2`. Version 1
disclosed a local preview and a per-upload confirmation; a detected screenshot
now runs on its own, which is materially different, so the previous grant cannot
be honoured and every user is asked again. The retired v1 keys are swept on the
next privacy purge.


### Follow-up hardening, same day

Two failure modes surfaced while reviewing the two-batch change and were fixed
before the final deployment:

- The judge's `max_tokens` was `1200`, sized for a single batch. Six options
  each carrying `text`, `why` and `effect` reach roughly 2k output tokens at the
  contract's per-field maxima, and truncation is correctly rejected by
  `stop_reason === "max_tokens"` — meaning a failed request rather than a short
  one. Raised to `2600`, with the judge call cap raised from 8s to 12s. The
  judge deadline (start + 35s) still governs; `phaseSignal` clips the cap to
  whatever remains after the compiler.
- Two batches of three distinct strategies require the compiler's six candidates
  to cover at least three strategies twice over. Forcing `alternates` in the
  judge schema would have made a conversation that cannot support that either
  fail outright or pad the second batch with unreliable duplicates. `alternates`
  is no longer a required schema field; the prompts ask for it, allow omitting
  it when the situation genuinely cannot support it, and forbid padding. Both
  the server and the client already treat an absent second batch as valid.

Final live state — `Deploy Keyboard Assist` run `30301101211` (`6563ad68`):

- `deno test --allow-read supabase/functions/keyboard-assist`: 68 passed,
  0 failed.
- `keyboard-assist` is version `6`, `ACTIVE`.
- The unauthenticated capability probe returns `401`.
- No migration was applied and no secret was added or changed.
