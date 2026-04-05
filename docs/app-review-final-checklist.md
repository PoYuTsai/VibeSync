# App Review Final Checklist

Last updated: 2026-04-05

Use this as the final go / no-go checklist before submitting the iOS build for review.

## 1. Auth / Session

- [ ] Apple sign-in passes end to end
- [ ] Google sign-in passes end to end
- [ ] Email sign-up / verify / resend passes end to end
- [ ] Forgot password passes end to end
- [ ] Logout / switch account does not leak old tier, session, or local thread data
- [ ] Delete account flow works end to end

## 2. Subscription

- [ ] Starter purchase works
- [ ] Essential purchase works
- [ ] `Free -> Essential` refreshes into premium replies without stale free state
- [ ] Restore Purchases / Sync purchased subscription works
- [ ] Same Apple ID restore behavior is understood and documented
- [ ] Different Apple ID restore remains `Free`
- [ ] `Starter -> Essential` upgrade behavior is confirmed
- [ ] `Essential -> Starter` downgrade timing matches Apple expectations

## 3. OCR / Analysis

- [ ] Normal screenshot import works
- [ ] LINE quoted reply screenshots work
- [ ] Long screenshots are acceptable
- [ ] Overlapping multi-image imports are acceptable
- [ ] Media / sticker / video bubbles are acceptable
- [ ] Name OCR drift is acceptable
- [ ] Import confirmation / correction flow is stable
- [ ] User-facing errors stay human-readable and do not leak raw backend/debug text

## 4. Release / Legal

- [ ] Latest TestFlight build installs and launches cleanly
- [ ] Privacy page opens correctly in app
- [ ] Terms page opens correctly in app
- [x] `support@vibesyncai.app` can receive mail
- [ ] App Store Connect privacy disclosure matches the real data flow

## 5. Final Launch Gate

Do not submit if any of the following are still true:

- [ ] known `P1` auth bug
- [ ] known `P1` subscription / restore bug
- [ ] known `P1` OCR speaker / thread corruption bug
- [ ] known `P1` release / deep-link / session bug

## Related Docs

- [Current Test Status](./current-test-status-2026-04-03.md)
- [TestFlight Regression Checklist](./testflight-regression-checklist.md)
- [Launch Readiness Checklist](./launch-readiness-checklist.md)
