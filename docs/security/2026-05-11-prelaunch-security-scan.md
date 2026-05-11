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
