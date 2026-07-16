# Preflight Checks

## Supabase Secrets

Run this before production Edge deploys or App Store/TestFlight releases:

```powershell
powershell -ExecutionPolicy Bypass -File tools/preflight/check-supabase-secrets.ps1 -ProjectRef fcmwrmwdoqiqdnbisdpg
```

The check fails if any required Edge Function secret is missing:

- `CLAUDE_API_KEY`
- `KEYBOARD_REPLAY_HMAC_KEY`
- `REVENUECAT_IOS_API_KEY`
- `REVENUECAT_WEBHOOK_SECRET`

Why this exists:

- App builds use the public RevenueCat SDK key (`appl_...`).
- Edge Functions need the secret RevenueCat API key (`sk_...`) to verify paid entitlements.
- If the server key is missing, the app can show Essential locally while `analyze-chat` still enforces Free quota from Supabase.

The GitHub Actions release and Edge deploy workflows run this check automatically.

`KEYBOARD_REPLAY_HMAC_KEY` must be a Base64-encoded random value of at least 32
bytes. Generate it outside the repository, then set it directly in Supabase:

```powershell
openssl rand -base64 32
npx.cmd --yes supabase secrets set KEYBOARD_REPLAY_HMAC_KEY="<generated-value>" --project-ref fcmwrmwdoqiqdnbisdpg
```

Do not rotate this key while 24-hour replay rows still exist. Either wait at
least 24 hours after pausing keyboard traffic or introduce a versioned-key
migration first; otherwise valid retries will become replay mismatches.

## Keyboard Exactly-Once Contract

After applying the keyboard migration and deploying `keyboard-reply`, verify
that the Edge binary, DB RPCs, and HMAC configuration agree:

```powershell
$env:SUPABASE_PROD_ANON_KEY = "<production-anon-key>"
powershell -ExecutionPolicy Bypass -File tools/preflight/check-keyboard-contract.ps1
```

Release and Firebase distribution workflows run this live production check and
fail closed unless the DB-owned capability reports
`keyboard-reply-exactly-once-v1`.

## RevenueCat Server Key Smoke

Run this before production Edge deploys or App Store/TestFlight releases when the
server key is available in the shell:

```powershell
$env:REVENUECAT_IOS_API_KEY = "<secret server key>"
powershell -ExecutionPolicy Bypass -File tools/preflight/check-revenuecat-secret-smoke.ps1
```

The smoke check calls RevenueCat `GET /v1/subscribers/<redacted>` with a Bearer
token and fails if the key is missing, is an `appl_` public SDK key, is rejected,
or cannot return a subscriber payload. It does not print the key or response
body.

GitHub Actions passes `${{ secrets.REVENUECAT_IOS_API_KEY }}` to this check.
Supabase can list Edge secret names but cannot reveal secret values for a direct
local smoke test, so keep the GitHub Actions secret synchronized with the
Production Supabase `REVENUECAT_IOS_API_KEY`.
