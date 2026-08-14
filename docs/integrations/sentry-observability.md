# Sentry crash/error black box

Status: code-ready, disabled until a DSN is configured.

## What it records

- Flutter/iOS uncaught Dart and native crashes.
- Supabase Edge uncaught exceptions and returned HTTP 5xx responses.
- App release/environment/platform; Edge deployment, function, region, HTTP
  status, error type, and sanitized stack locations.
- Release sessions, so Sentry can calculate crash-free session health.

## What it must not record

- User identity, email, IP address, request URL/body/headers, chat content,
  partner names, screenshots, view hierarchy, breadcrumbs, logs, performance
  traces, profiles, replay, attachments, or local variables.
- Do not add `Sentry.setUser`, request capture, screenshots, breadcrumbs,
  replay, tracing, or log forwarding without a new privacy review.

Dart/Flutter and Edge events are rebuilt from small allowlists covered by
automated tests. Native iOS hard crashes are sent later by Sentry Cocoa and do
not pass through the Dart allowlist. They may retain non-content device, OS,
and app diagnostics, so activation also requires inspecting a real native
test-crash payload before accepting the privacy boundary.

## One-time activation checklist

Do these in order. Do not put the DSN in a committed file.

1. Create one private Sentry project for VibeSync and require 2FA for both
   operators. Limit project access to those two operators and choose the
   shortest retention period that is operationally useful.
2. Before sending an event, enable Sentry's default data scrubbing and
   **Prevent Storing of IP Addresses** under Security & Privacy.
3. Keep Session Replay, Performance, Logs, User Feedback, and automatic AI
   analysis disabled for this project.
4. Add the project's DSN as the GitHub Actions repository secret
   `SENTRY_DSN`. `Build & Distribute` and `Release to App Stores` already pass
   it to the app at compile time.
5. Add the same DSN as the Supabase Edge Function secret `SENTRY_DSN`.
6. Redeploy the affected Edge Functions through the repository's existing
   targeted workflows. `analyze-chat` must retain `--no-verify-jwt`; keyboard
   functions retain their dedicated deployment workflows.
7. Review the App Store Connect privacy answers and public privacy policy for
   the addition of diagnostic crash data before submitting 1.0.1. Whether
   Apple considers the data linked depends on the final Sentry account and IP
   scrubbing settings, so verify the live configuration rather than guessing.
8. Dart crashes are readable without Flutter obfuscation. Native iOS frames
   may still need dSYM upload. In a test-only TestFlight/internal build,
   trigger one deliberate native crash, relaunch so it is uploaded, inspect
   the raw event for unexpected identifiers or content, and verify
   symbolication before calling native crash diagnosis or privacy complete.

If either secret is absent, that side remains a safe no-op and the product
continues to start and serve requests normally.

## Where to look after activation

- **Something broke:** Sentry → Issues. Filter `environment:Production` and
  the current release. Edge events include the `edge_function` tag.
- **Is the release healthy:** Sentry → Releases → current 1.0.1 build →
  crash-free sessions.
- **Was the backend involved:** filter Issues by
  `runtime:supabase-edge`; then use the timestamp and function name to open
  Supabase Dashboard → Edge Functions → Logs for the detailed server log.
- **Did Sentry drop events:** Sentry → Stats/Usage shows accepted, filtered,
  rate-limited, and invalid events.

Create two alert rules after the first sanitized smoke event arrives:

- Alert immediately when a new production issue first appears.
- Alert when one production issue occurs at least 5 times in 5 minutes.

Email both operators first. Add chat integrations only if the team already
uses them operationally.

## Smoke check before 1.0.1 review

1. Build with a real DSN and confirm the app opens with no new consent or UI.
2. Send one synthetic Dart exception containing a unique fake marker, never
   real user data.
3. Confirm the Dart issue arrives and the marker does **not** appear anywhere in
   the event JSON, attachments, breadcrumbs, request, or user fields.
4. From a test-only build, trigger one deliberate native iOS crash and relaunch
   the app. Inspect its raw event JSON separately because it bypasses the Dart
   allowlist. Confirm there is no user/chat/request content or unexpected
   identifier, and confirm native frames are symbolicated.
5. Confirm both events have the correct release and useful stack locations.
6. Delete/discard the synthetic issues, then enable the two alert rules.

Do not intentionally crash the App Store production build for this check; use
a TestFlight/internal build or a test-only Edge invocation.
