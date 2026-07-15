# Practice Chat production probes

These scripts preserve the generated-only Hint and Debrief production checks that were previously kept in local `.gstack/` scratch space.

## Safety

- `practice_generated_only_production_smoke.ts` calls the live Supabase project, creates test-account practice sessions, performs profile draws, and invokes live AI providers. Run it only when production verification is intended.
- The three provider probes call DeepSeek and Claude directly and may incur provider cost.
- No credential is stored in this directory.

## Credentials

- Production smoke reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from the repository `.env.local`, plus `TEST_EMAIL` and `TEST_PASSWORD` from `tools/ocr-golden/.env.golden`.
- Provider probes read `DEEPSEEK_API_KEY` and `CLAUDE_API_KEY` from the process environment.

## Commands

Run these commands from the repository root:

```powershell
deno run --allow-read --allow-net tools/practice-chat/practice_generated_only_production_smoke.ts
deno run --allow-env --allow-net tools/practice-chat/practice_hint_provider_probe.ts
deno run --allow-env --allow-net tools/practice-chat/practice_hint_acceptance_probe.ts
deno run --allow-env --allow-net tools/practice-chat/practice_debrief_provider_probe.ts
```

The production smoke accepts an optional existing SR profile id and an optional mode (`beginner`, `game`, or `both`) as positional arguments.
