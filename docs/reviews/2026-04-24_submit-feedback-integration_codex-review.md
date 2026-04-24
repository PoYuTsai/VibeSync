# 2026-04-24 submit-feedback integration Codex review

## Scope

- Diagnose mixed-version integration: TF137 old Flutter client vs current
  `submit-feedback` Edge Function
- No code changes in this review

## Verdict

Most likely: **B-like payload rejection**, but **not** because the new Edge
Function added new required fields.

The stronger code-side explanation is:

1. old TF137 still sends a much larger feedback payload
2. current `submit-feedback` still enforces strict length limits
3. `functions.invoke()` throws on non-2xx
4. Flutter catches the exception and collapses everything into the same generic
   snackbar

So the symptom can look like "nothing happened", while the real failure is
likely a silent 400 from optional fields that are too large.

## Why hypothesis B is stronger than A/C

### A. Auth 401/403

- `submit-feedback` JWT behavior did **not** change across the reviewed range.
- `.github/workflows/deploy-edge-function.yml` still deploys
  `submit-feedback` **without** `--no-verify-jwt`, same as before.
- The Flutter caller does not manually add `Authorization`, but that is normal:
  Supabase Dart's `functions.invoke()` uses the auth HTTP client and package
  tests verify the access token is attached automatically when a session exists.

Conclusion:

- A is still possible if the device session is missing/expired at runtime
- but code diff does **not** support "today's server change broke auth"

### B. Payload reject

- Old TF137 payload:
  - always sends `conversationSnippet`
  - sends raw `_lastAiResponse`
- New app payload after `0c343da`:
  - makes `conversationSnippet` opt-in
  - truncates snippet to 1000 chars
  - sends reduced AI context instead of raw `_lastAiResponse`
- Current Edge Function still rejects:
  - strings longer than configured max via `STRING_TOO_LONG`
  - `aiResponse` JSON larger than `AI_RESPONSE_MAX_LENGTH`

Conclusion:

- this is the strongest mixed-version risk surfaced by the diff
- not a required-field mismatch, but a **payload size/shape compatibility**
  mismatch

### C. App never sent request

- The call site is present both before and after `0c343da`
- There is no new early-return around the invoke path besides `conversation ==
  null`
- The more important client issue is not "request never sent" but "4xx/401/network
  all collapse into the same generic catch path"

Conclusion:

- pure C is the weakest of the three from code evidence alone

## Request schema review

Current Edge Function request contract:

- required:
  - `rating`: `"positive"` or `"negative"`
- optional:
  - `category`: enum in `too_direct | too_long | unnatural | wrong_style | other`
  - `comment`: string, max 2000
  - `conversationSnippet`: string, max 4000
  - `userTier`: string, max 50
  - `modelUsed`: string, max 120
  - `aiResponse`: object

Current Edge Function does **not** add new required fields compared with the
pre-`0c343da` version.

JWT verification behavior is also unchanged.

## Old Flutter vs current Edge

| Field | TF137 old Flutter sends | Current Edge expects | Compatibility |
|------|--------------------------|----------------------|---------------|
| `rating` | always sends | required | compatible |
| `category` | sends nullable chip value | optional enum | compatible |
| `comment` | sends nullable trimmed text | optional, max 2000 | compatible unless too long |
| `conversationSnippet` | always sends last 6 messages, untrimmed | optional, max 4000 | **risk** |
| `aiResponse` | sends raw `_lastAiResponse` | optional object, total JSON max 12000 after sanitize | **risk** |
| `userTier` | sends current tier | optional, max 50 | compatible |
| `modelUsed` | sends `_lastAiResponse?['usage']?['model']` | optional, max 120 | compatible |

## Client error handling risk

`functions_client` throws `FunctionException` on any non-2xx. The Flutter
caller catches everything and only shows:

- `回饋暫時沒有送出，稍後可以再試一次。`

That means:

- a 400 payload reject
- a 401/403 auth reject
- or a transport/network failure

all look identical from the app UI.

## Minimal fix recommendation

### Short-term server-side hardening

Make `submit-feedback` tolerant of old TF137 optional fields during the skew
window:

1. truncate `conversationSnippet` instead of rejecting when it is over limit
2. if `aiResponse` is too large, drop or aggressively minimize it instead of
   returning 400

This preserves JWT verification while keeping older clients functional.

### Next TestFlight build

Ship the app-side feedback minimization from `0c343da`:

1. make conversation snippet opt-in
2. truncate snippet before send
3. send reduced AI context instead of raw `_lastAiResponse`
4. surface `FunctionException.status/details` in debug logging so 400 vs 401
   can be distinguished quickly

## Final ranking

1. **B (payload reject due old oversized optional fields)** — most likely
2. **A (runtime auth/session issue on device)** — plausible, but not supported
   by today's server diff
3. **C (request never sent at all)** — least supported by code
