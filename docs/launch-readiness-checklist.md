# Launch Readiness Checklist

Last updated: 2026-04-05

This is the high-level launch decision sheet.

## Must Have Before iOS Launch

### Auth / Subscription

- [ ] Apple / Google / Email auth all verified
- [ ] Starter / Essential / Restore behavior verified
- [ ] Different Apple ID restore stays `Free`
- [ ] Logout / switch account / account deletion all verified

### OCR / Analysis

- [ ] Main screenshot import path is stable
- [ ] LINE quoted reply handling is stable
- [ ] At least one long / multi-image OCR pass is acceptable
- [ ] User-facing errors remain readable and actionable

### Legal / Review

- [ ] Privacy and terms links are final
- [x] `support@vibesyncai.app` can receive mail
- [ ] App Store Connect privacy disclosure is final
- [ ] App Review package is ready

## Should Have Soon After Launch

- [ ] Remaining OCR edge cases signed off:
  - short continuations
  - stickers / video bubbles
  - name OCR drift
- [ ] Starter downgrade / upgrade timing fully documented
- [ ] Admin dashboard UX polish after server-route hardening
- [ ] Security monitoring / retention / incident runbook walk-through with both founders

## Not Required For iOS Launch

- [ ] Android / Google Play launch
- [ ] Growth content engine
- [ ] LINE OA automation
- [ ] secondary alert sink beyond Telegram

## Platform Rules To Remember

- Same Apple ID restore / transfer:
  - expected
- Different Apple ID restore:
  - should remain `Free`
- `Starter -> Essential`:
  - expected immediate upgrade
- `Essential -> Starter`:
  - expected next-renewal downgrade in most cases

## Go / No-Go Rule

### Go

- All must-have items are complete
- No open `P1`
- No repeated OCR speaker/thread corruption in real tester flows

### No-Go

- Any auth / restore / subscription blocker remains
- Premium state still drifts or fails to refresh
- OCR still repeatedly corrupts thread meaning
- Legal / disclosure remains inaccurate

## Related Docs

- [Current Test Status](./current-test-status-2026-04-03.md)
- [App Review Final Checklist](./app-review-final-checklist.md)
- [TestFlight Regression Checklist](./testflight-regression-checklist.md)
- [OCR Analysis Maturity Benchmark](./ocr-analysis-maturity-benchmark.md)
