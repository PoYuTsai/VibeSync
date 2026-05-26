# Finance Dashboard + Partner Settlement V1

> Status: design draft, no implementation yet.
> Audience: Eric / Bruce / future Claude-Codex sessions.
> Goal: build a shared operations and finance dashboard for VibeSync after App Review approval.

## Product Principle

This dashboard is for Eric and Bruce to use together.

It should feel like a shared operating ledger, not like one person reporting to
the other. The UX should make income, expenses, and settlement transparent from
both sides:

- Eric and Bruce can both see how money moved.
- Eric and Bruce can both record expenses they paid.
- The system calculates who should transfer money to whom.
- In the current real-world setup, App Store proceeds are expected to arrive in
  Eric's bank account, so Eric will usually manually transfer Bruce's share.

The dashboard should still reflect reality:

- Apple Developer account, App Store proceeds, and most recurring costs are
  currently under Eric's control.
- Bruce may pay specific costs such as domain fees or future agreed marketing
  costs.
- Not every payment is automatically part of profit sharing.
- Personal labor/time is not counted unless Eric and Bruce explicitly agree.

## Current Repo Baseline

Existing pieces that can be reused later:

- `admin-dashboard/` exists as a Next.js admin surface.
- Supabase has `admin_users`, `revenue_events`, `token_usage`,
  `monthly_revenue`, `monthly_profit`, `test_users`, `real_users`,
  `real_subscriptions`.
- RevenueCat webhook updates subscription status and logs events.
- `ai_logs` records analyze-chat AI usage and estimated cost.

Known gaps:

- Existing `monthly_revenue` is not settlement-grade proceeds.
- Existing `monthly_profit` only subtracts token usage-like cost and does not
  model partner settlement.
- RevenueCat is an operating signal, not the official money source.
- Manual expenses, amortization, settlement lock, and Eric/Bruce transfer logic
  do not exist yet.
- Current admin dashboard Traditional Chinese copy has mojibake and should be
  cleaned before broad use.

## Money Source Rules

Official settlement income should use store financial reports / actual proceeds:

- App Store / Google Play collect user payments.
- Platforms deduct commission, taxes, refunds, chargebacks, and adjustments.
- Platforms send proceeds to the configured primary bank account.
- RevenueCat tracks subscriptions, entitlements, renewals, cancellations, and
  events, but is not the official receiving account.

Current App Store banking direction as of 2026-05-26:

- App Store Connect banking was changed to a Thai Kasikorn account for Eric.
- Tax forms remain active and were not changed.
- Formal settlement should still rely on Apple proceeds / financial reports,
  not RevenueCat MRR.

## Core Ledger Model

V1 should be a simple ledger first, not a full accounting system.

Each row answers:

- What happened?
- Which month should it belong to?
- Was it income or expense?
- Who actually received or paid it?
- Should it be included in partner settlement?
- Is it confirmed, excluded, or still pending agreement?

### `finance_entries`

Proposed columns:

| Column | Notes |
| --- | --- |
| `id` | UUID primary key |
| `entry_date` | Actual date of payment, charge, report, or receipt |
| `settlement_month` | Month this row belongs to, e.g. `2026-06-01` |
| `type` | `revenue` / `expense` |
| `title` | Human-readable item name |
| `category` | Optional helper: `app_store_proceeds`, `google_play_proceeds`, `claude`, `apple_developer`, `domain`, `hosting`, `marketing`, `tooling`, `other` |
| `amount` | Decimal amount in entry currency |
| `currency` | `TWD`, `USD`, `THB`, etc. |
| `amount_twd` | Optional normalized amount for settlement display |
| `fx_rate_to_twd` | Optional, used when source is not TWD |
| `paid_by` | `eric` / `bruce` / `platform` / `none` |
| `received_by` | `eric` / `bruce` / `platform` / `none` |
| `settlement_treatment` | `included_in_profit_split` / `personal_not_shared` / `pending_agreement` |
| `amortization_months` | Nullable; e.g. 12 for annual developer/domain fees |
| `amortization_start_month` | Nullable month |
| `receipt_url` | Private receipt/report URL |
| `source` | `manual`, `apple_report`, `google_report`, `revenuecat_observation`, `system_estimate` |
| `notes` | Free-form note |
| `created_by` | Admin user id |
| `created_at` | Timestamp |
| `updated_at` | Timestamp |

Defaults for V1:

- `paid_by` default: Eric for expense rows, unless changed.
- `received_by` default: Eric for revenue rows, unless changed.
- `settlement_treatment` default: `pending_agreement` for manually added
  expenses, so uncertain costs do not silently affect settlement.
- Store proceeds imported/entered from Apple/Google reports default to
  `included_in_profit_split`.

### `monthly_settlements`

Proposed columns:

| Column | Notes |
| --- | --- |
| `id` | UUID primary key |
| `settlement_month` | Unique month |
| `status` | `draft` / `locked` / `paid` |
| `revenue_total_twd` | Included revenue |
| `expense_total_twd` | Included expenses |
| `profit_twd` | Revenue minus included expenses |
| `distributable_profit_twd` | `max(profit_twd, 0)` |
| `eric_actual_cash_twd` | Eric received included revenue minus Eric paid included expenses |
| `bruce_actual_cash_twd` | Bruce received included revenue minus Bruce paid included expenses |
| `eric_entitlement_twd` | Default 50 percent of distributable profit |
| `bruce_entitlement_twd` | Default 50 percent of distributable profit |
| `carry_in_twd` | Prior unpaid balance |
| `amount_eric_should_transfer_to_bruce_twd` | Positive when Eric pays Bruce |
| `amount_bruce_should_transfer_to_eric_twd` | Positive when Bruce pays Eric |
| `carry_out_twd` | Unpaid or loss balance carried forward |
| `locked_by` | Admin user id |
| `locked_at` | Timestamp |
| `paid_at` | Timestamp |
| `notes` | Free-form note |

### `settlement_line_items`

Snapshot rows copied from `finance_entries` when a month is locked.

Why:

- Locked settlements should not silently change if a historical ledger row is
  later edited.
- Eric and Bruce should be able to reconstruct what was included in a month.

### `finance_audit_logs`

Track:

- who created/edited/deleted an entry,
- who changed `settlement_treatment`,
- who locked/unlocked a settlement,
- who marked it paid,
- old/new values for money fields.

This is partner money, so history matters.

## Settlement Treatment

Each expense should be explicitly categorized by settlement treatment:

### `included_in_profit_split`

Counts before profit split.

Examples:

- Claude actual API usage for production.
- Apple Developer annual fee, amortized monthly if agreed.
- Domain fee, amortized monthly if agreed.
- Hosting/tools/marketing if Eric and Bruce agree it belongs to VibeSync
  operating cost.

### `personal_not_shared`

Visible in ledger if desired, but does not affect settlement.

Examples:

- personal time,
- personal device costs,
- unrelated tools,
- expenses Eric/Bruce choose not to share.

### `pending_agreement`

Visible, but excluded from settlement until decided.

Examples:

- future advertising spend before Eric/Bruce agree how it is treated,
- one-off tool purchases,
- ambiguous business/personal mixed expenses.

## Calculation

Only rows with `settlement_treatment = included_in_profit_split` participate.

Definitions:

```text
included_revenue = sum(included revenue rows)
included_expense = sum(included expense rows)
profit = included_revenue - included_expense
distributable_profit = max(profit, 0)

eric_entitlement = distributable_profit * 50%
bruce_entitlement = distributable_profit * 50%

eric_actual_cash =
  included revenue received by Eric
  - included expenses paid by Eric

bruce_actual_cash =
  included revenue received by Bruce
  - included expenses paid by Bruce

eric_balance = eric_actual_cash - eric_entitlement
bruce_balance = bruce_actual_cash - bruce_entitlement
```

Interpretation:

- If `eric_balance > 0`, Eric has more cash than his share and should transfer
  money to Bruce.
- If `bruce_balance > 0`, Bruce has more cash than his share and should transfer
  money to Eric.
- If `profit < 0`, there is no distributable profit; expense imbalance becomes
  carry-forward unless Eric and Bruce manually settle the loss.

Current likely default:

```text
App Store proceeds received_by = Eric
Most infrastructure expenses paid_by = Eric
Domain or some future costs may be paid_by = Bruce
System usually calculates Eric should transfer Bruce's share after month close.
```

## UX

The UX should feel equal and transparent.

Avoid language like:

- "Eric's ledger"
- "Bruce reimbursement only"
- "owner report"

Prefer:

- "共同營運帳本"
- "月結"
- "收入與支出"
- "列入月結"
- "待協議"
- "本月應轉帳"
- "標記結算完成"

### Page 1: Overview

Cards:

- 本月收入
- 本月支出
- 本月利潤
- 待協議支出
- Eric 本月已收 / 已付 / 應得
- Bruce 本月已收 / 已付 / 應得
- 本月應轉帳方向與金額

Charts:

- revenue vs expense trend,
- profit trend,
- paid users and conversion rate,
- AI cost trend.

### Page 2: Ledger

Main table:

- month,
- date,
- type,
- title,
- amount,
- paid by / received by,
- settlement treatment,
- receipt,
- notes.

Primary actions:

- Add revenue.
- Add expense.
- Mark as included / pending / not shared.
- Attach receipt.

Important UI behavior:

- `pending_agreement` rows should be visibly separate.
- Included rows should show how they affect settlement.
- Annual costs can show monthly amortization preview.

### Page 3: Monthly Settlement

Draft state:

- show included rows,
- show pending rows excluded from calculation,
- show calculation details,
- show proposed transfer.

Locked state:

- freeze line-item snapshot,
- show who locked and when,
- disable edits unless reopened.

Paid state:

- show transfer marked complete,
- show paid date,
- optionally attach transfer proof.

### Page 4: Users / Subscriptions

Reuse existing admin data but clean copy and focus on operational metrics:

- new users,
- paid users,
- plan,
- active/cancelled/expired,
- test user flag,
- AI usage / cost estimate.

This page is not the official revenue settlement source.

### Page 5: RevenueCat / Store Reports

Separate official money from operating signals:

- RevenueCat events: operational health.
- App Store / Google Play proceeds: official settlement input.

Display both, but label clearly:

```text
RevenueCat MRR is an estimate / operating signal.
Apple/Google proceeds are settlement source of truth.
```

## Permissions

V1 roles:

### `owner`

Likely Eric.

- View all finance pages.
- Add/edit/delete all entries.
- Change settlement treatment.
- Lock/reopen settlements.
- Mark settlements paid.
- Manage admin users.

### `partner`

Likely Bruce.

- View all finance pages.
- Add expenses paid by himself.
- Attach receipts.
- Comment on entries.
- See settlement calculations.
- Cannot silently edit official store proceeds.
- Cannot lock/reopen/pay settlement unless later granted.

This preserves the real control surface while keeping the product experience
transparent and respectful.

## Security

Finance data should be more restricted than normal admin analytics.

Recommended implementation guardrails:

- Do not expose finance tables directly through browser-side Supabase anon
  reads.
- Use Next.js server routes or server actions to check admin role before
  querying finance data.
- Never put service role keys in client code.
- Store receipts/reports in private storage and serve signed URLs only.
- Audit all financial edits.
- Locked settlement snapshots should be immutable unless explicitly reopened.
- Avoid storing full user chat content in finance views.
- Keep test users excluded from operating metrics by default.

## Implementation Phases

### Phase 1: Design + DB

- Add finance ledger tables.
- Add monthly settlement tables.
- Add RLS / server-side access model.
- Add audit logs.
- Add docs and seed examples.

### Phase 2: Manual Ledger UI

- Build ledger page.
- Build monthly settlement draft page.
- Support manual entries, treatment flags, receipts, and amortization.

### Phase 3: Store Proceeds Workflow

- Add manual Apple/Google proceeds entry flow.
- Later support CSV/import helper if useful.
- Clearly separate proceeds from RevenueCat estimates.

### Phase 4: Operating Metrics

- Clean admin dashboard Traditional Chinese copy.
- Connect users/subscriptions/AI cost pages.
- Fix or replace legacy `monthly_profit` with settlement-aware views.

### Phase 5: Settlement Lock + Paid Flow

- Lock month.
- Generate line-item snapshot.
- Mark settlement paid.
- Attach transfer proof.
- Carry forward unpaid/loss balance.

## Open Questions

- Should settlement currency be TWD by default, even if Apple proceeds arrive
  in THB?
- Which FX rate should be used: actual bank conversion, Apple report rate, or
  manually entered rate?
- Should Apple Developer annual fee and domain fee be amortized automatically
  by default, or entered manually each month?
- Should Bruce be allowed to edit `pending_agreement` rows entered by Eric, or
  only comment?
- When should a settlement be considered locked: after Apple proceeds report,
  after bank payout, or after Eric/Bruce both review?

## Recommendation

Start with a manual, transparent ledger. Do not overbuild accounting categories
yet.

The first valuable version is:

```text
Eric/Bruce enter revenue and expenses
each row says who paid/received and whether it is included
system calculates fair 50/50 settlement
Eric manually transfers Bruce if needed
month gets locked and marked paid
```

That gives VibeSync a fair operating back office without pretending the bank
account, legal control, or cost payment pattern is more symmetrical than it
currently is.
