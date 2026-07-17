# 2026-05-11 Prelaunch Security Scan

Scope: public-repo readiness before switching VibeSync to private.

## Summary

- No live Claude/OpenAI/App Store private keys were found in tracked files.
- `.env.local` is gitignored and currently only contains public Supabase URL + anon key.
- GitHub Actions now use minimal `contents: read` token permissions.
- Web deploy no longer passes `VERCEL_TOKEN` inline in the shell command.
- Android staging build no longer stores verbose build logs that include `--dart-define` secret arguments.
- `auth_diagnostics` keeps anon insert support for login debugging, but now caps field and metadata sizes.
- `admin-dashboard` dependencies were updated and the original scan reduced advisories from 11 to 2 moderate findings.
- On 2026-07-17, Next was upgraded to 16.2.10, Supabase JS to 2.110.7, and PostCSS was pinned to 8.5.19. `npm audit --omit=dev` now reports 0 production advisories.

## Resolved Follow-up (2026-07-17)

The two PostCSS advisories are resolved with a root-level npm override to 8.5.19. Upgrading Supabase JS also removes the old Realtime dependency path through `ws`. Verification: production audit 0 vulnerabilities, ESLint passes, and Next's production build passes.

## Follow-up Before Private Repo Switch

- Confirm GitHub Actions budget is non-zero for Actions.
- Rotate any keys that were ever pasted into public issue/commit history outside this scan.
- Keep Supabase service-role keys only in GitHub Secrets / Supabase Secrets, never in Flutter code.

## Supabase Apply Status

Applied to linked production project on 2026-05-11:

- `20260401_auth_diagnostics.sql`
- `20260509_fix_check_and_reset_usage_limits.sql`
- `20260511000000_harden_auth_diagnostics.sql`

Verified:

- `auth_diagnostics` exists, RLS is enabled, 2 policies are present, and payload constraints are present.
- `check_and_reset_usage` now matches pricing: Free 30/15, Starter 300/50, Essential 800/120.
- `check_and_reset_usage` and `increment_usage` are executable by `service_role` only, not `anon` or `authenticated`.

Note: `supabase migration list --linked` still shows two old `20260315` local rows missing from remote history because the repo has duplicate `20260315_*` migration filenames. Do not run `supabase db push` blindly; use targeted SQL or clean up migration history deliberately.
