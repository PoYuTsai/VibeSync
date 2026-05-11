# 2026-05-11 Prelaunch Security Scan

Scope: public-repo readiness before switching VibeSync to private.

## Summary

- No live Claude/OpenAI/App Store private keys were found in tracked files.
- `.env.local` is gitignored and currently only contains public Supabase URL + anon key.
- GitHub Actions now use minimal `contents: read` token permissions.
- Web deploy no longer passes `VERCEL_TOKEN` inline in the shell command.
- Android staging build no longer stores verbose build logs that include `--dart-define` secret arguments.
- `auth_diagnostics` keeps anon insert support for login debugging, but now caps field and metadata sizes.
- `admin-dashboard` dependencies were updated and `npm audit fix` reduced advisories from 11 to 2 moderate findings.

## Remaining Known Item

`admin-dashboard` still has 2 moderate npm audit advisories through Next's internal `postcss` dependency. `npm audit fix --force` currently proposes a breaking Next downgrade, so do not force it. Re-check after the next safe Next release.

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
