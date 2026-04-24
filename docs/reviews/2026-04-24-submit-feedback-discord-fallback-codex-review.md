# 2026-04-24 submit-feedback Discord Fallback Codex Review

## Scope

- Reviewed commit: `bc7a1e3`
- File: `supabase/functions/submit-feedback/index.ts`

## Finding

### [P1] Bot fallback is unreachable without a webhook URL

`sendDiscordNotification()` returned immediately when
`DISCORD_FEEDBACK_WEBHOOK_URL` was absent, so the newly added bot fallback path
never executed. In the current production setup, the active notification route
uses `DISCORD_BOT_TOKEN` plus `DISCORD_FEEDBACK_CHANNEL_ID`, which meant
negative feedback was persisted but never reached Discord.

## Fix

1. Added `resolveDiscordNotificationTarget()` in
   `supabase/functions/submit-feedback/feedback_utils.ts`
2. Updated `submit-feedback/index.ts` to only warn/return when both webhook and
   bot delivery are unavailable
3. Added regression tests covering webhook priority, bot fallback, and
   incomplete config

## Verdict

- Status: Fixed
- Risk after fix: Low
- Remaining caution: if a webhook URL is configured but invalid, delivery still
  stays on the webhook path and does not auto-fallback to bot
