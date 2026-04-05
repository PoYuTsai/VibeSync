# TestFlight Regression Checklist

Last updated: 2026-04-05
Target build: `v82`

Use this checklist when validating a new TestFlight build. It is intentionally narrower than
the full launch checklist and focuses on regression safety.

## 0. Test Setup

- [ ] Confirm the installed build number
- [ ] Prepare at least 2 VibeSync accounts
- [ ] Prepare at least 3 OCR test screenshots
- [ ] Confirm privacy / terms / support links are reachable

## A. Auth / Session

- [ ] Apple sign-in
- [ ] Google sign-in
- [ ] Email sign-up + verify
- [ ] Resend verification
- [ ] Forgot password from warm start
- [ ] Forgot password from cold start
- [ ] Logout / switch account with no stale tier or local thread leakage

## B. Subscription / Paywall

- [ ] Paywall copy is readable and launch-facing
- [ ] Privacy / terms links work
- [ ] Starter purchase
- [ ] Essential purchase
- [ ] Restore Purchases / Sync purchased subscription
- [ ] `Free -> Essential` returns to premium reply state correctly
- [ ] Already-premium users are not pushed through a broken or misleading upgrade loop

## C. OCR / Import

### C1 Core import cases

- [ ] Single screenshot import
- [ ] 2-3 screenshot import
- [ ] New thread import

### C2 Speaker / thread structure

- [ ] `only_left`
- [ ] `only_right`
- [ ] `mixed`
- [ ] Speaker warnings appear only when appropriate

### C3 LINE quoted replies

- [ ] Left-side quoted reply
- [ ] Right-side quoted reply
- [ ] Quote preview does not become a fake standalone message
- [ ] `quotedReplyPreview` stays attached as context

### C4 OCR edge cases

- [ ] Image bubble
- [ ] Sticker bubble
- [ ] Video / shared-media bubble
- [ ] Short text / emoji-only bubbles
- [ ] Long screenshot overlap cleanup

## D. Analysis UX

- [ ] Loading / processing states are visible and understandable
- [ ] `Unlock full replies with upgrade` CTA appears only when appropriate
- [ ] Free / premium reply sets do not drift
- [ ] OCR import guidance feels clear and actionable

## E. Telemetry / Guardrails

Check at least 3 representative runs:

- [ ] normal OCR
- [ ] LINE quoted reply OCR
- [ ] long or multi-image OCR

Confirm telemetry captures the expected fields:

- [ ] classification
- [ ] side confidence
- [ ] uncertain side count
- [ ] quoted preview attach / remove count
- [ ] overlap removed count
- [ ] payload size / round-trip / AI latency

## F. Regression Result

- [ ] A passed
- [ ] B passed
- [ ] C passed for the tested cases
- [ ] D passed
- [ ] E captured enough telemetry for review

If `C3` or `C4` fails, update [Current Test Status](./current-test-status-2026-04-03.md)
before closing the regression pass.
