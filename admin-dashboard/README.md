# VibeSync Admin Dashboard

Internal admin dashboard for VibeSync operations.

## What it is for

- overview metrics
- user and subscription inspection
- auth diagnostics
- AI health and error trends
- revenue and cost visibility
- security signals and alert history

## Security model

- browser pages do **not** query Supabase directly for admin data
- dashboard pages fetch server-side `/api/admin/*` routes instead
- those routes require:
  - a valid admin session cookie
  - a matching row in `public.admin_users`
  - server-side Supabase access through `SUPABASE_SERVICE_ROLE_KEY`

## Required environment variables

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

## Local development

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Quality checks

```bash
npm run lint
npm run build
```

Both should pass before shipping dashboard changes.
