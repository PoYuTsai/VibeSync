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
- When was it paid?
- Is it monthly, annual, one-time, usage-based, or campaign-based?
- Should it be deducted before profit sharing this month?
- Is it confirmed, excluded for now, or still pending agreement?

### `finance_entries`

Proposed columns:

| Column | Notes |
| --- | --- |
| `id` | UUID primary key |
| `entry_date` | Actual date of payment, charge, report, or receipt |
| `paid_at` | Actual payment date; useful when invoice month and payment date differ |
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
| `billing_cycle` | `monthly` / `annual` / `one_time` / `usage_based` / `campaign_based` |
| `recognition_method` | `cash_basis` / `amortize_evenly` / `usage_based` / `manual_schedule` |
| `cost_role` | `direct_variable_cost` / `fixed_overhead` / `growth_investment` / `personal` / `other` |
| `include_before_profit_split` | Boolean checkbox; whether this row is deducted before 50/50 profit sharing |
| `settlement_treatment` | `included_before_profit_split` / `excluded_for_now` / `pending_agreement` |
| `service_period_start` | Nullable; start of service period for annual/campaign costs |
| `service_period_end` | Nullable; end of service period for annual/campaign costs |
| `amortization_months` | Nullable; e.g. 12 for annual developer/domain fees |
| `amortization_start_month` | Nullable month |
| `next_renewal_date` | Nullable reminder for annual/monthly recurring costs |
| `receipt_url` | Private receipt/report URL |
| `source` | `manual`, `apple_report`, `google_report`, `revenuecat_observation`, `system_estimate` |
| `notes` | Free-form note |
| `created_by` | Admin user id |
| `created_at` | Timestamp |
| `updated_at` | Timestamp |

Defaults for V1:

- `paid_by` default: Eric for expense rows, unless changed.
- `received_by` default: Eric for revenue rows, unless changed.
- `cost_role` default: `fixed_overhead` for manual expenses, unless changed.
- `include_before_profit_split` default:
  - true for `direct_variable_cost`,
  - false for `fixed_overhead`, `growth_investment`, `personal`, and `other`.
- `settlement_treatment` default:
  - `included_before_profit_split` for direct variable costs,
  - `excluded_for_now` for early fixed overhead,
  - `pending_agreement` for uncertain growth investment such as ads.
- Store proceeds imported/entered from Apple/Google reports default to
  included revenue.

This preserves the early-stage agreement:

```text
Eric may keep paying Claude, Apple Developer, tools, and other burn for now.
Fixed overhead rows are visible for transparency, but they do not automatically
reduce Bruce's share or create debt unless the include checkbox is enabled.
Direct user-driven costs, such as Claude API usage for real users, should still
be deducted before profit sharing by default.
```

### `cost_recognition_schedule`

Optional but recommended once annual costs matter.

One payment can generate monthly recognition rows:

| Column | Notes |
| --- | --- |
| `id` | UUID primary key |
| `finance_entry_id` | Parent payment/cost row |
| `recognition_month` | Month this portion belongs to |
| `amount` | Original currency amount recognized in this month |
| `amount_twd` | TWD amount recognized in this month |
| `include_before_profit_split` | Copied from parent by default, editable before lock |
| `created_at` | Timestamp |

Examples:

- Apple Developer annual fee: one payment row, 12 monthly recognition rows.
- Domain annual fee: one payment row, 12 monthly recognition rows.
- Ad campaign crossing two months: one payment row, manual schedule by campaign
  dates or manual split.

### `monthly_settlements`

Proposed columns:

| Column | Notes |
| --- | --- |
| `id` | UUID primary key |
| `settlement_month` | Unique month |
| `status` | `draft` / `locked` / `paid` |
| `settlement_mode` | `contribution_split` / `net_profit_split` / `no_distribution` |
| `revenue_total_twd` | Settlement revenue |
| `recorded_expense_total_twd` | All visible operating expenses, whether included or not |
| `deducted_expense_total_twd` | Expenses checked for deduction before split |
| `operating_profit_twd` | Revenue minus all recorded operating expenses; informational |
| `settlement_profit_twd` | Revenue minus deducted expenses; used only in net-profit mode |
| `distributable_amount_twd` | Amount to split for the selected settlement mode |
| `eric_actual_cash_twd` | Eric received settlement revenue minus Eric paid deducted expenses |
| `bruce_actual_cash_twd` | Bruce received settlement revenue minus Bruce paid deducted expenses |
| `eric_entitlement_twd` | Default 50 percent of distributable amount |
| `bruce_entitlement_twd` | Default 50 percent of distributable amount |
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

## Billing Cycles And Cost Recognition

V1 should separate real payment from monthly settlement recognition.

### Monthly

Use for costs like Vercel, Supabase, RevenueCat paid plan, or monthly tools.

Recommended recognition:

```text
billing_cycle = monthly
recognition_method = cash_basis
settlement_month = invoice/payment month
```

### Annual

Use for Apple Developer annual fee, domains, or annual tools.

Recommended recognition:

```text
billing_cycle = annual
recognition_method = amortize_evenly
amortization_months = 12
```

The parent row records the actual payment. The schedule records monthly cost
recognition. Whether each monthly recognition row affects settlement depends on
the include checkbox.

Example:

```text
Payment:
Apple Developer Program, USD 99, paid by Eric, paid_at 2026-02-28

Recognition:
2026-03 through 2027-02, USD 8.25 per month
include_before_profit_split = false by default during early burn
```

### Usage-Based

Use for Claude API.

Recommended recognition:

```text
billing_cycle = usage_based
recognition_method = usage_based
```

The cost should be based on actual API usage for the month when possible, not
credit-card top-up or prepaid balance movement.

Claude production usage should usually be marked:

```text
cost_role = direct_variable_cost
include_before_profit_split = true
```

Reason: this cost scales with real user usage. Even during the early stage, it
is cleaner to split revenue after direct AI cost, while Eric can still absorb
fixed overhead such as Apple Developer fee, tools, and other baseline burn.

### Campaign-Based

Use for ads.

Recommended recognition:

```text
billing_cycle = campaign_based
recognition_method = manual_schedule
```

Ad spend should default to `pending_agreement` until Eric and Bruce decide how
that campaign affects settlement.

## Settlement Treatment

Each expense should be explicitly categorized by settlement treatment:

### `included_before_profit_split`

Counts before profit split.

Examples:

- Claude actual API usage for production.
- other direct per-user generation or fulfillment costs.
- Apple Developer annual fee, amortized monthly if agreed.
- Domain fee, amortized monthly if agreed.
- Hosting/tools/marketing if Eric and Bruce agree it belongs to VibeSync
  operating cost.

### `excluded_for_now`

Visible in ledger if desired, but does not affect settlement.

Examples:

- early-stage burn Eric chooses to absorb,
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

V1 supports three settlement modes per month.

### Mode A: `contribution_split`

Early-stage default when Eric is absorbing fixed overhead, but direct user-driven
costs still need to be deducted.

```text
settlement revenue = App Store / Google Play proceeds
direct variable costs = Claude API production usage and similar per-user costs
distributable_amount = settlement revenue - direct variable costs
Eric/Bruce split max(distributable_amount, 0) 50/50
fixed overhead is visible but not deducted
```

Use this when:

- revenue is still low,
- Eric is choosing to absorb early fixed burn,
- Bruce should not accumulate debt from fixed overhead,
- Claude/API costs should still be paid from the revenue they helped generate,
- the goal is transparent contribution-margin sharing without complex cost
  recovery.

### Mode B: `net_profit_split`

Use when Eric and Bruce agree that more costs should be deducted first.

Rows with `include_before_profit_split = true` participate as deducted expenses.
This usually includes direct variable costs plus any fixed overhead or growth
investment Eric/Bruce explicitly agree to include.

Definitions:

```text
settlement_revenue = sum(settlement revenue rows)
deducted_expense = sum(expense rows checked for deduction)
settlement_profit = settlement_revenue - deducted_expense
distributable_amount = max(settlement_profit, 0)

eric_entitlement = distributable_amount * 50%
bruce_entitlement = distributable_amount * 50%

eric_actual_cash =
  settlement revenue received by Eric
  - deducted expenses paid by Eric

bruce_actual_cash =
  settlement revenue received by Bruce
  - deducted expenses paid by Bruce

eric_balance = eric_actual_cash - eric_entitlement
bruce_balance = bruce_actual_cash - bruce_entitlement
```

Interpretation:

- If `eric_balance > 0`, Eric has more cash than his share and should transfer
  money to Bruce.
- If `bruce_balance > 0`, Bruce has more cash than his share and should transfer
  money to Eric.
- If `settlement_profit < 0`, there is no distributable profit. The loss does
  not automatically become Bruce's debt unless Eric and Bruce explicitly agree
  to carry it forward.

### Mode C: `no_distribution`

Use when Eric and Bruce want to observe the month but not distribute anything.

```text
distributable_amount = 0
transfer amount = 0
all revenue/cost/profit metrics remain visible
```

Current likely default:

```text
App Store proceeds received_by = Eric
Claude production usage = direct variable cost, deducted before split
Most fixed infrastructure expenses paid_by = Eric, visible but excluded at first
Domain or some future costs may be paid_by = Bruce, visible but excluded unless agreed
Early months use contribution_split or no_distribution
Later months may switch to net_profit_split after costs are agreed
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
- 本月記錄支出
- 本月列入扣除支出
- 本月營運損益
- 本月可分配金額
- 待協議支出
- Eric 本月已收 / 已付 / 應得
- Bruce 本月已收 / 已付 / 應得
- 本月應轉帳方向與金額
- 月結模式: 直接成本後對分 / 淨利對分 / 暫不分潤

Charts:

- revenue vs expense trend,
- profit trend,
- paid users and conversion rate,
- AI cost trend.

### Page 2: Ledger

Main table:

- month,
- date,
- paid date,
- type,
- title,
- billing cycle,
- amount,
- paid by / received by,
- settlement treatment,
- include-before-profit checkbox,
- receipt,
- notes.

Primary actions:

- Add revenue.
- Add expense.
- Mark as included / pending / not shared.
- Attach receipt.
- Set monthly/annual/one-time/usage/campaign cycle.
- Generate or edit amortization schedule.

Important UI behavior:

- `pending_agreement` rows should be visibly separate.
- Included rows should show how they affect settlement.
- Annual costs can show monthly amortization preview.
- Excluded early-burn rows should remain visible but clearly say they do not
  create partner debt.

### Page 3: Monthly Settlement

Draft state:

- choose settlement mode: contribution split / net profit split / no distribution,
- show included rows,
- show excluded early-burn rows for transparency,
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

### Page 4: Upcoming / Forecast

This page helps Eric and Bruce see the next month before it happens.

Sections:

- upcoming recurring monthly costs,
- annual costs still being amortized,
- next renewal dates,
- planned ad campaigns,
- pending cost decisions,
- estimated store payout if available,
- estimated Claude usage cost if available.

This view is informational. It should not lock a settlement.

### Page 5: History

Show monthly / quarterly / yearly perspective:

- total revenue,
- recorded costs,
- deducted costs,
- operating profit,
- distributable amount,
- transfers completed,
- Eric/Bruce cumulative paid costs,
- Eric/Bruce cumulative received transfers,
- early burn absorbed by each partner.

Useful filters:

- this month,
- last month,
- quarter,
- year-to-date,
- all-time.

### Page 6: Users / Subscriptions

Reuse existing admin data but clean copy and focus on operating metrics:

- new users,
- paid users,
- plan,
- active/cancelled/expired,
- test user flag,
- AI usage / cost estimate.

This page is not the official revenue settlement source.

### Page 7: RevenueCat / Store Reports

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
- Support manual entries, paid dates, billing cycles, treatment flags, receipts,
  include-before-profit checkbox, and amortization.
- Support monthly settlement mode selection: contribution split, net profit
  split, or no distribution.

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

### Phase 6: Forecast + Long-Term Views

- Add upcoming costs and renewal reminders.
- Add monthly/quarterly/yearly history.
- Add cumulative early-burn view for transparency.
- Add export for Eric/Bruce review and tax/accounting prep.

## Open Questions

- Should settlement currency be TWD by default, even if Apple proceeds arrive
  in THB?
- Which FX rate should be used: actual bank conversion, Apple report rate, or
  manually entered rate?
- Should Apple Developer annual fee and domain fee create monthly amortization
  schedules automatically, even when not included in settlement yet?
- Should the default month mode be `contribution_split` or `no_distribution`
  before meaningful user revenue exists?
- Which costs besides Claude should be treated as direct variable costs?
- When should Eric and Bruce switch from contribution split/no distribution to
  net profit split?
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
each expense records paid date, amount, cycle, and payer
each expense has a cost role and checkbox for whether it is deducted before profit split
each month chooses contribution split, net profit split, or no distribution
system calculates fair 50/50 settlement based on the selected mode
Eric manually transfers Bruce if needed
month gets locked and marked paid
```

That gives VibeSync a fair operating back office without pretending the bank
account, legal control, or cost payment pattern is more symmetrical than it
currently is. Early burn can stay transparent without automatically becoming a
partner debt.
