# Current Test Status

Last updated: 2026-04-05

## Summary

The project is in `Phase A / iOS Launch Stabilization`.

Mainline flows are now working:

- auth
- password reset
- account deletion
- RevenueCat purchase flow
- same Apple ID restore / transfer behavior
- `Free -> Essential` premium reply refresh
- OCR mainline screenshot import
- LINE quoted-reply handling

The remaining work is edge-case signoff, not large new feature work.

## Verified Pass

### Auth / Account

- [x] Email sign-up -> verification -> app login
- [x] Forgot password -> email link -> app reset -> login
- [x] Logout -> switch account does not leak old tier or local conversation state
- [x] Delete account -> recreate same email works again

### Subscription

- [x] `Free -> Essential` purchase succeeds
- [x] Returning to analysis after upgrade can refresh into premium replies
- [x] Same Apple ID restore / transfer behavior is understood and behaves as expected
- [x] Same Apple ID restore is no longer being treated as a product bug

### OCR / Analysis

- [x] Main screenshot import flow works
- [x] LINE quoted replies no longer split into fake standalone messages in common cases
- [x] OCR import confirmation / correction flow works
- [x] Retry / force re-recognize / new-thread vs append flow works

## Still Pending

### Subscription

- [ ] `Free -> Starter`
- [ ] `Starter -> Essential` immediate upgrade validation
- [ ] `Essential -> Starter` next-renewal downgrade validation
- [ ] Different Apple ID restore should remain `Free`
- [ ] Reinstall / fresh-device restore validation

### OCR Edge Cases

- [ ] Long screenshots
- [ ] Multi-image overlap cleanup
- [ ] Short continuation bubbles
- [ ] Media / sticker / video bubbles
- [ ] Small-name / small-text OCR drift
- [ ] Reusing the same image batch across different thread contexts

### Launch / Legal

- [ ] In-app privacy link final verification
- [ ] In-app terms link final verification
- [x] `support@vibesyncai.app` can receive mail
- [ ] App Store Connect privacy disclosure final pass

## Expected Subscription Behavior

These behaviors are intentional and should not be logged as bugs:

### Same Apple ID restore

- If the same Apple ID previously purchased Starter or Essential,
  `Restore Purchases` / `Sync purchased subscription` can transfer that entitlement
  to the currently signed-in VibeSync account.

### Different Apple ID restore

- If the Apple ID has never purchased Starter or Essential,
  restore should leave the account on `Free`.

### Upgrade / Downgrade timing

- `Starter -> Essential`: expected to upgrade immediately
- `Essential -> Starter`: expected to take effect on the next renewal in most cases

## Current Go / No-Go Rule

We are ready for iOS launch only when all of the following are true:

- no new `P1` launch bugs
- auth / restore / upgrade flows remain stable
- OCR does not show repeated speaker/thread corruption in real tester cases
- privacy / terms / support / disclosure are all aligned

## Related Docs

- [App Review Final Checklist](./app-review-final-checklist.md)
- [TestFlight Regression Checklist](./testflight-regression-checklist.md)
- [Launch Readiness Checklist](./launch-readiness-checklist.md)
- [OCR Analysis Maturity Benchmark](./ocr-analysis-maturity-benchmark.md)
