# Streaming Spike Results — NDJSON on Supabase Edge → Flutter/iOS

> Status: spike artifacts built + server-side verified locally. iOS/TestFlight
> leg pending (needs a Mac + device). THROWAWAY — delete after the transport
> question is answered and folded into the full streaming contract.
> Branch: `spike/streaming-ndjson` (do NOT merge to main).
> Companion: `docs/plans/2026-06-03-full-streaming-analyze-contract.md`.

## Question this spike answers

Does a real Supabase Edge Function deliver an NDJSON body to an iOS client
**incrementally** (event by event), or does iOS wait for the whole packet?

If iOS buffers the whole response, the full streaming analyze path is dead and
we must change approach (criterion 5).

## Scope guardrails (per Eric, 2026-06-03)

The spike function is intentionally inert: no analyze-chat, no DB read/write, no
quota, no schema change, no Claude call. It only emits a scripted timeline so we
can measure per-event arrival time on the device.

This round: spike only. No main merge, no analyze-chat deploy, no quota/charge
changes. The eventual real streaming analyze-chat is high-risk and needs Codex
review before it can be called safe — that is a later workstream.

## Artifacts

| File | Role |
| --- | --- |
| `supabase/functions/spike-stream/index.ts` | Throwaway Edge Function. NDJSON, one line/sec, `progress→recommendation→reply→section→done`. `?intervalMs=` overrides cadence. |
| `lib/spike/streaming_spike_main.dart` | Standalone Flutter entrypoint. Raw `http.Client().send()`, manual `Authorization: Bearer`, reads NDJSON line by line, stamps each event's arrival second, shows INCREMENTAL/BUFFERED verdict. |

## Format decision: NDJSON first

Per Eric: `Content-Type: application/x-ndjson`, one minified JSON object per
line, newline as the only record separator. SSE was not tested this round.
Rationale: NDJSON is simpler to frame on both ends and avoids SSE `data:`/event
parsing; the contract's D5 says "SSE if reliable, else NDJSON" — we go straight
to the simpler one and only revisit SSE if NDJSON has an iOS-specific problem.

`spike-stream` deploys with `--no-verify-jwt` on purpose: it removes the JWT
gateway as a buffering variable, so this is the *purest* transport test. The
Flutter harness still attaches a real `Authorization`/`apikey` header, so header
plumbing is still exercised end to end.

## Evidence produced in this session (server-side, local)

Ran the function under local Deno and curled it with `-N` (no client buffering),
stamping each line's arrival elapsed from request start, at `?intervalMs=300`:

```text
+ 0.29s  {"type":"progress","message":"正在整理這段對話...","t":1,...}
+ 0.59s  {"type":"progress",...,"t":2}
+ 0.89s  {"type":"progress",...,"t":3}
+ 1.19s  {"type":"progress",...,"t":4}
+ 1.49s  {"type":"recommendation","title":"本回合怎麼接",...,"t":5}
+ 1.79s  {"type":"progress",...,"t":6}
+ 2.09s  {"type":"reply",...,"t":8}
+ 2.39s  {"type":"section","name":"五種回覆風格",...,"t":10}
+ 2.70s  {"type":"section","name":"互動雷達",...,"t":12}
+ 3.00s  {"type":"section","name":"深層策略",...,"t":14}
+ 3.30s  {"type":"done","t":15}
```

Lines arrived ~300ms apart, evenly spread 0.29s→3.30s — **not** buffered into a
single packet. Conclusion: the function code and Deno's `ReadableStream` flush
per-enqueue correctly. The only unverified hop is Supabase's deployed Edge
gateway → iOS network stack.

`flutter analyze lib/spike/streaming_spike_main.dart` → No issues found.

## How to run the iOS leg (Eric / Bruce, on a Mac)

1. Authenticate the Supabase CLI once (interactive — run it yourself):

   ```bash
   supabase login
   ```

2. Deploy the throwaway function (does NOT touch main, does NOT auto-deploy):

   ```bash
   npx supabase functions deploy spike-stream \
     --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg
   ```

3. Sanity-check from the Mac terminal (should print lines ~1s apart, not all at once):

   ```bash
   curl -N -s -X POST \
     "https://fcmwrmwdoqiqdnbisdpg.supabase.co/functions/v1/spike-stream?intervalMs=1000" \
     -H "Authorization: Bearer <anon-or-session-token>" \
     | while IFS= read -r l; do printf '%s  %s\n' "$(date +%T.%2N)" "$l"; done
   ```

4. Run the harness on a connected iPhone (real device, not simulator, to match
   the production network stack):

   ```bash
   flutter run -t lib/spike/streaming_spike_main.dart -d <iphone-device-id>
   ```

   Tap **開始 spike**. Read the verdict banner + per-row arrival seconds.

## Criteria scorecard — fill after the device run

| # | Criterion | Local (this session) | iOS device |
| --- | --- | --- | --- |
| 1 | Flutter calls Edge with auth header, gets streaming response | ✅ header plumbing + stream works under Deno/curl | ⬜ |
| 2 | iOS does NOT wait for the whole packet | n/a (not iOS) | ⬜ |
| 3 | Events arrive step by step (progress/recommendation/section) | ✅ ~300ms apart, in order | ⬜ |
| 4 | Mid-disconnect / leave page / timeout behavior is understood | ⬜ (use 中途取消 button) | ⬜ |
| 5 | Result written to docs before backend parser design | ✅ this file | — |

### Numbers to read off the device (Eric wanted these)

| Milestone | Expected ~t | iOS observed |
| --- | --- | --- |
| First loading/status event | ~1s | ⬜ |
| `recommendation` / 本回合怎麼接 | ~5s | ⬜ |
| `reply` / AI 推薦回覆 | ~8s | ⬜ |
| First full `section` | ~10s | ⬜ |
| `done` | ~15s | ⬜ |

If the harness shows **BUFFERED ✗** (every row lands together near 15s), the
streaming path does not survive on iOS and we change approach before any backend
parser work.

## Next steps (gated on the device run)

- iOS INCREMENTAL ✓ → proceed to design the real backend reframer parser
  (Claude text stream → typed NDJSON events) per the full streaming contract,
  then Codex review before any analyze-chat change.
- iOS BUFFERED ✗ → test SSE variant, or fall back to a polling/chunked design;
  do not build the parser yet.
- Either way: delete `supabase/functions/spike-stream/` and
  `lib/spike/streaming_spike_main.dart` once the decision is locked.
