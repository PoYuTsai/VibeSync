# RevenueCat Ops Guide

Last updated: 2026-04-05

This guide explains what RevenueCat is for in VibeSync, what to check there,
and how to interpret common subscription situations.

## Plain-English Terms

### entitlement

The paid access that is active right now.

In VibeSync terms:

- does this account currently have paid features?
- is it effectively `Starter` or `Essential` right now?

Short version:

- `entitlement = active paid access right now`

### restore

Bringing back a subscription that was already purchased before.

Typical cases:

- reinstalling the app
- logging in again on the same device
- the app lost local tier state
- moving to a new device

Short version:

- `restore = recover what was already purchased`

### transfer

Moving a purchased subscription from one VibeSync app account to another VibeSync app account.

Typical case:

1. the same Apple ID already bought Essential
2. the user signs into a different VibeSync account
3. the user taps restore / sync purchased subscription
4. the subscription moves onto the current VibeSync account

Short version:

- `transfer = the subscription moved from one app account to another`

## Backend Split

- `Supabase`
  - main operations backend
  - local tier copy, AI usage, auth diagnostics, SQL
- `RevenueCat`
  - subscription truth
  - entitlement, restore, transfer, customer timeline
- `App Store Connect`
  - iOS product setup
  - subscription group and upgrade / downgrade rules

Short version:

- operations and SQL -> `Supabase`
- subscription truth -> `RevenueCat`
- iOS store rules -> `App Store Connect`

## What To Check In RevenueCat

### Customers

This is the most important screen.

Use it to inspect:

- active entitlement
- current products
- renewals / cancellations
- restore / transfer behavior
- timeline of what actually happened

This is where you answer:

- "Did this person really buy something?"
- "Why did restore move paid access?"
- "Why is Supabase still showing Free?"

### Project Settings

Important thing to know:

- `Restore Behavior`

For VibeSync, the practical meaning is:

- if the same Apple ID already purchased something
- and another VibeSync account uses restore
- RevenueCat may move that entitlement to the currently signed-in account

That is usually expected behavior, not automatically a bug.

### Products / Entitlements / Offerings

Use these pages to confirm:

- `Starter` and `Essential` products exist
- both are mapped to the right entitlement
- offerings contain the expected packages

## Expected VibeSync Subscription Behavior

### Same Apple ID restore

Expected:

- a Free VibeSync account can become paid after restore
- if that Apple ID already owns the subscription

This is normal under RevenueCat transfer behavior.

### Different Apple ID restore

Expected:

- if that Apple ID never purchased Starter or Essential
- restore should leave the account on `Free`

### Upgrade / downgrade timing

Expected:

- `Free -> Starter`: immediate
- `Free -> Essential`: immediate
- `Starter -> Essential`: immediate upgrade
- `Essential -> Starter`: usually changes on the next renewal, not instantly

## Common Debug Paths

### "The app says Free, but the user says they paid"

Check in this order:

1. `RevenueCat -> Customers`
2. `Supabase -> public.subscriptions`
3. `Supabase -> public.webhook_logs`
4. `Supabase -> public.revenue_events`

Interpretation:

- if RevenueCat shows an active entitlement but Supabase is still Free
  - look at webhook delivery and sync
- if RevenueCat itself shows no active entitlement
  - this is not a Supabase bug first

### "Why did another account become Essential after restore?"

Check:

1. `RevenueCat -> Project Settings -> Restore Behavior`
2. `RevenueCat -> Customers`
3. `Supabase -> public.subscriptions`

If it was the same Apple ID, this is often expected transfer behavior.

### "How do I know if this was a real bug or just same-Apple-ID restore?"

Ask these first:

- Was it the same Apple ID / Sandbox Apple ID?
- Did the user tap restore / sync purchased subscription?
- Did RevenueCat show a transfer or restored entitlement?

If yes, this is usually product behavior, not a broken purchase pipeline.

## Practical Rules For VibeSync

- Same Apple ID restore can move paid access to the current VibeSync account.
- Different Apple ID restore should stay Free if nothing was ever purchased.
- RevenueCat is the subscription truth.
- Supabase is the app-facing copy of that truth.
- App Store Connect defines iOS billing rules and timing.

## Related Docs

- [Supabase Ops Guide](./supabase-ops-guide.md)
- [Current Test Status](./current-test-status-2026-04-03.md)
- [App Review Final Checklist](./app-review-final-checklist.md)
