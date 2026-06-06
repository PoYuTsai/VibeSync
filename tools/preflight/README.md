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
