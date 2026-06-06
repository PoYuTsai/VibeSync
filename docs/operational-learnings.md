# Operational Learnings

Durable engineering lessons that should transfer across VibeSync workstreams and future projects.

## 2026-06-07 - Live Secrets Are Part Of The Product

### Incident

A TestFlight partner account showed Essential in the app and RevenueCat SDK diagnostics, but `analyze-chat` still returned Free-tier behavior:

- one reply style instead of five
- `Daily limit exceeded` at exactly 15 daily uses

The app was not lying about local RevenueCat state. The server was missing the production `REVENUECAT_IOS_API_KEY`, so Edge Functions could not verify the paid entitlement or update the Supabase subscription row.

### Lesson

Client-side state is not enough for paid features. For subscription, quota, auth, AI, and deployed Edge flows, the real system is:

```text
client SDK -> app state -> Supabase row -> Edge Function env -> external SaaS API -> Edge quota/feature gate
```

If any link is missing, dogfood can look like a code regression even when the final blocker is infrastructure.

### What Was Useful, Not Waste

The earlier fixes were still valuable because they removed real failure modes:

- RevenueCat identity could fall back to anonymous ids.
- Local paid snapshots could be overwritten by transient Free states.
- Restore/startup flows could show paid locally before server confirmation.
- Analyze requests did not consistently send paid entitlement hints.
- Streaming analysis still had one-style fallback paths.

Those fixes reduced the state space. The final blocker became visible only after a partner video showed the server enforcing the Free daily cap.

### Prevention Rule

Do not rely on manual dashboard memory for launch-critical external dependencies.

Release and Edge deploy paths must fail fast when required live secrets are absent. VibeSync now checks these Supabase secrets before production release/deploy:

- `CLAUDE_API_KEY`
- `REVENUECAT_IOS_API_KEY`
- `REVENUECAT_WEBHOOK_SECRET`

Command:

```powershell
powershell -ExecutionPolicy Bypass -File tools/preflight/check-supabase-secrets.ps1 -ProjectRef fcmwrmwdoqiqdnbisdpg
```

### Debugging Rule

When a paid/quota issue appears inconsistent, compare all boundaries before patching more code:

- App UI tier
- RevenueCat `currentAppUserId`, `originalAppUserId`, active entitlements
- Supabase `subscriptions.tier`, limits, usage counters
- Edge Function request payload: `expectedTier`, `revenueCatAppUserId`
- Edge Function live secrets and deploy revision
- RevenueCat webhook delivery for renew/expire/cancel events

Repo grep and unit tests are necessary but not sufficient for live integration bugs.
