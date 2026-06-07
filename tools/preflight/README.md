# Preflight Checks

## Supabase Secrets

Run this before production Edge deploys or App Store/TestFlight releases:

```powershell
powershell -ExecutionPolicy Bypass -File tools/preflight/check-supabase-secrets.ps1 -ProjectRef fcmwrmwdoqiqdnbisdpg
```

The check fails if any required Edge Function secret is missing:

- `CLAUDE_API_KEY`
- `REVENUECAT_IOS_API_KEY`
- `REVENUECAT_WEBHOOK_SECRET`

Why this exists:

- App builds use the public RevenueCat SDK key (`appl_...`).
- Edge Functions need the secret RevenueCat API key (`sk_...`) to verify paid entitlements.
- If the server key is missing, the app can show Essential locally while `analyze-chat` still enforces Free quota from Supabase.

The GitHub Actions release and Edge deploy workflows run this check automatically.

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
