# AI Arbitration Queue

> Purpose: a shared handoff + review + debate queue for Eric, Claude, and
> Codex. Use this instead of free-form bot-to-bot chat.

## When To Use

Use this file when:

- Claude and Codex need a live handoff between work rounds
- Claude finished a DC / mobile-driven bugfix or partial feature and Codex may
  later review or continue it
- Codex finished a hardening / review pass and wants Claude to sanity-check
  product or UX impact
- Claude wants Codex to review a concrete bug, risk, or architecture tradeoff
- Codex wants Claude to sanity-check UI, product, or copy direction
- Eric wants one place to see the current disagreement, evidence, and next
  action

Do not use this file for:

- ordinary commit summaries
- bug history
- ADRs that are already settled
- every tiny commit as a separate entry

Those still belong in `git log`, `docs/bug-log.md`, or `docs/decisions.md`.

## Ground Rules

1. One queue item = one decision or one concrete blocker.
2. One task keeps one live item. Update the existing item instead of appending
   a new one for every small round.
3. Newest open item goes on top.
4. Each side gets at most 2 rounds before escalating to Eric.
5. Every claim about "safe", "faster", or "better" must cite evidence:
   - file path
   - commit hash
   - test result
   - benchmark
   - official doc
6. Product taste, UX preference, and business priority are Eric-final.
7. No free-form bot loop:
   - Claude writes one structured position
   - Codex replies with one structured position
   - if still split, mark `Status: WAITING_ON_DAISY`
8. If the work is only a handoff and not a disagreement, still record:
   - latest commit
   - changed files or scope
   - tests run
   - open risks
   - next ask for the other agent
9. Keep only open items plus a few recently closed items. Once the durable
   record exists elsewhere, prune old closed entries.

## Status Values

- `OPEN`
- `IN_REVIEW`
- `WAITING_ON_DAISY`
- `APPROVED`
- `CLOSED`

## Queue Template

Copy this block for each new item:

```md
## [YYYY-MM-DD] Short Title
Status: OPEN
Request-Type: handoff | review | arbitration
Raised-By: Claude | Codex | Eric
Owner: Claude | Codex | Eric
Scope: bug | review | architecture | product | copy | ops
Branch/Commit: `commit-hash` or `working-tree`

Question:
- What exact decision or blocker needs arbitration?

Context:
- Short factual setup only.

Changed:
- What changed in this round?

Evidence:
- [path-or-doc](../path.md) or `commit-hash`
- Test / runtime observation

Open-Risks:
- Pending

Claude-Position:
- Pending

Codex-Position:
- Pending

Verdict:
- Pending

Eric-Decision:
- Pending

Action-Items:
- Pending

Close-Condition:
- What must happen before this item becomes CLOSED?
```

## Working Norms

- Claude should lead UI / Flutter / copy / product framing items.
- Codex should lead bugs / performance / architecture / code review items.
- If Claude is operating through Discord / mobile-driven sessions, update this
  file at the end of each meaningful round that Codex may later need to
  continue or review.
- If Codex finishes a pass and wants Claude to sanity-check it later, update
  the same item instead of opening a parallel summary.
- If Eric asks for a recommendation, end with a single recommended path.
- If the issue becomes a lasting rule, move the final outcome into:
  - `docs/decisions.md` for ADR-level decisions
  - `docs/bug-log.md` for recurring bug traps
  - `AGENTS.md` only for short-lived operating rules
- This file is a live queue, not a changelog.

---

## Live Queue

## [2026-04-26] Partner Entity Refactor - A2 Implementation Plan Review
Status: OPEN
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: architecture
Branch/Commit: `main` (plan-only commit; impl branch `feature/partner-entity-A2` will be cut after Codex spec review pass)

Question:
- Does the A2 plan faithfully execute ADR-15 + design doc v2 §2/3/4/6? Any
  missing risk before Claude opens the implementation branch and runs through
  17 TDD tasks?

Context:
- A1 已 merge `919e034` + TF soak 雙綠燈通過 (Eric build 139 + Bruce
  「Structure hasn't been changed, please proceed」)
- ADR-15 翻 ✅ Accepted (2026-04-26)
- A2 範圍 = Partner UI / merge UI / AI prompt summary / copy sweep /
  routing — 7-8 dev days 上限保留
- A1 hot spots HS1 (Sentry SDK) / HS2 (redo-rebackup) 帶到 A2 plan
  Task 16 follow-up，不在 A2 主線執行

Changed:
- 新增 `docs/plans/2026-04-26-partner-entity-A2-impl.md`，17 個 TDD task
- 4 個 Daisy-Decision-Needed 標記（D1 截圖 flow 掛 Partner / D2 domain
  rename 範圍 / D3 conversation cell tap / D4 dedupe banner 顯示時機），
  皆有 plan-default
- Plan 末尾「Codex Review Hot Spots」5 項（HS-A2-1 ~ HS-A2-5）

Evidence:
- [A2 plan](../plans/2026-04-26-partner-entity-A2-impl.md)
- [ADR-15 Accepted](../decisions.md)
- A1 ship commit `919e034`
- `grep -rn 'typeId:' lib/`（pre-flight 必再跑）

Open-Risks:
1. Riverpod narrow invalidation contract 若實作層用 Hive box stream
   listener，可能仍 fan-out（HS-A2-1）
2. Partner summary truncate 邊界處理中文 surrogate 風險（HS-A2-2）
3. D1 fallback path 是否真能避免 Bruce 同人多卡痛點（HS-A2-3）
4. 7-8 dev day 工期估算（HS-A2-4）
5. Routing deep-link 入口 back stack 缺 partner parent（HS-A2-5）

Claude-Position:
- Plan 4 個 Daisy-Decision 都有 plan-default A，不阻塞執行
- HS-A2-1 ~ HS-A2-5 是 Codex 應在 spec review 階段給 verdict 的重點
- 17 task TDD granularity 對齊 A1 plan 的 13 task 風格 + spec §5 已寫死的測試列
- A2 期間禁區（不 reopen ADR-15、不動 A1 schema、不混 testing-context build）已寫死於
  memory `reference_partner_refactor_in_flight.md`

Codex-Position:
- Pending

Verdict:
- Pending

Eric-Decision:
- Pending（Daisy-Decision-Needed 4 項可在此或 PR description 覆蓋預設值）

Action-Items:
- [x] Claude 寫 A2 plan
- [x] Claude commit + push plan to `main`
- [x] Claude 開本 queue item
- [ ] Codex spec review（重點：HS-A2-1 ~ HS-A2-5 + Daisy-Decision-Needed 4 項是否合理）
- [ ] Eric 拍板 Daisy-Decision-Needed 4 項（或維持 plan-default）
- [ ] Codex verdict pass → Claude 切 `feature/partner-entity-A2` 開始執行
- [ ] A2 ship 後另開新 queue item 做 code review，不 reopen 本 item

Close-Condition:
- Codex spec review verdict = PASS（plan 可執行）→ Status flip APPROVED
- 或 verdict = 🔴 / 🟠 → 於 docs/reviews/ 開 review doc，本 item 留 IN_REVIEW
  直到 plan 修訂

## [2026-04-25] Partner Entity Refactor - A1 Implementation Code Review
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Claude
Scope: review
Branch/Commit: merged to `main` @ `919e034` (PR #1) — branch `feature/partner-entity-A1` retained per Eric for soak fallback

Question:
- Does the A1 implementation faithfully execute the approved v2 spec? Two
  spec-uncovered judgment calls (HS1 / HS2 below) need explicit Codex
  rulings before A1 lands on `main`.

Context:
- A1 phase = schema + migration only (no UI). A2 ships Partner UI / merge /
  AI prompt summary after A1's TF soak.
- Claude reports 12 commits on the branch, 20 new tests, and no regression vs
  the existing `main` test baseline.
- This queue item is restored on the branch so the code review outcome has a
  durable handoff target inside the PR branch itself.

Changed:
- New Partner entity / repository / migration service / deterministic id factory
- `Conversation.partnerId` field added
- `StorageService.initialize()` now opens the Partner box and runs migration
- 20 new unit / integration tests around migration
- Codex follow-up patch removes the direct `dart:io` import from the shared
  startup path by moving backup I/O behind a conditional import helper
- Codex follow-up patch changes migration completion semantics so partial-failure
  passes stay retryable on next boot instead of writing the done flag

Evidence:
- `53e7b85`
- [A1 implementation review doc](./2026-04-25_partner-entity-A1_codex-review.md)
- `lib/core/services/storage_service.dart`
- `lib/features/partner/data/services/partner_migration_service.dart`
- `test/unit/services/partner_migration_service_test.dart`
- `grep -rn 'typeId:' lib/`

Open-Risks:
1. Task 11 redo UI is still deferred to A2, so A1 cannot rely on manual redo as
   the only recovery path

Claude-Position:
- HS1: defer `sentry_flutter` until after TF soak; keep A1 on
  `dart:developer.log`
- HS2: keep redo-rebackup; user-triggered redo should treat current local state
  as ground truth
- Task 11 remains deferred to A2 per the blast-radius constraint

Codex-Position:
- `typeId = 8` remains valid; re-grep confirms `0..7` are occupied and `8` is
  free on this branch.
- HS1: approve defer. After the two implementation blockers below are fixed,
  A1 may keep `dart:developer.log(name: 'partner_migration')` for the TF soak
  instead of adding `sentry_flutter`.
- HS2: keep the current redo-rebackup policy.
- Codex directly patched the two original P1 findings:
  1. `StorageService` now calls a conditional-import backup helper instead of
     importing `dart:io` directly on the shared startup path.
  2. `PartnerMigrationService.runIfNeeded()` now keeps partial-failure passes
     retryable by skipping the done flag when any row failed.
- Claude then ran the clean-env follow-up verification and reported:
  - `test/unit/services/partner_migration_service_test.dart`: `6/6 PASS`
  - `test/integration/partner_migration_integration_test.dart`: `3/3 PASS`
  - `flutter analyze lib/core/services/ lib/features/partner/` + the two test
    files: `No issues found`
- With that validation in place, I am changing this item to PR-ready.

Verdict:
- APPROVED - branch may open PR and start TF soak after merge.

Eric-Decision:
- MERGED via PR #1 → `main` @ `919e034` (2026-04-25)

Action-Items:
- [x] Claude implemented A1 on `feature/partner-entity-A1`
- [x] Codex reviewed HS1 / HS2
- [x] Codex fixed the direct `dart:io` import in `StorageService`
- [x] Codex fixed migration completion semantics so partial-failure runs stay
      retryable
- [x] Claude / CC ran the targeted branch tests in a clean env
- [x] Codex confirmed the clean-env test result and gave PR go
- [x] PR #1 opened by Codex against `main`
- [x] Claude sanity-checked PR #1 diff against spec v2 / ADR-15 (no new blocker)
- [x] Eric merged PR #1 (2026-04-25)
- [x] TF soak started; ownership = Eric + testers (tracked outside this queue)

Close-Condition:
- PR is merged and A1 moves into TF soak tracking. ✅ Met 2026-04-25.

Follow-up:
- Soak surface: cold-boot crash, lost conversations, same-name partner data
  bleed, force-close + reopen stability, regression in list / chat / analyze.
- If a soak bug surfaces, open a NEW queue item (do not reopen this one); CC
  fixes by default, escalate to Codex only for review / hardening.
- ADR-15 stays 🟡 Proposed until soak passes; flip to Accepted then.
- Branch `feature/partner-entity-A1` retained until soak verdict.
- A2 (UI / merge / prompt summary) is paused during soak.

## [2026-04-25] Partner Entity Refactor - Design Spec Review
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: architecture
Branch/Commit: `5e10b86` → A1 plan on `feature/partner-entity-A1`

Question:
- Does spec v2 fully close the v1 P1 / P2 findings, or does any blocker remain
  before A1 implementation planning?

Context:
- v1 review verdict was `Critical flaw`; see
  `docs/reviews/2026-04-25_partner-entity-design_codex-review.md`.
- Eric authorized Claude to revise the spec without reopening the locked
  brainstorm decisions.
- Codex re-reviewed spec v2 against the original blockers plus the new v2
  open-risk list.

Changed:
- Spec v2 moved `Partner` from `typeId=5` to `typeId=8`.
- Migration was rewritten around deterministic UUID v5 +
  `conversation.partnerId` as the idempotency marker.
- Partner summary got a hard size cap and ranking rules.
- Provider invalidation was narrowed from "any conversation change" to
  partner-scoped invalidation.
- A1 estimate was demoted from `1.5 day` to `TBD pending Codex re-review`.

Evidence:
- [Design doc v2](../plans/2026-04-25-partner-entity-design.md)
- [Codex review doc](./2026-04-25_partner-entity-design_codex-review.md)
- `grep -rn 'typeId:' lib/`
- `lib/features/conversation/domain/entities/conversation.dart`
- `supabase/functions/analyze-chat/index.ts`

Open-Risks:
1. `conversationsByPartnerProvider(partnerId)` must stay truly partner-scoped
   and not reintroduce global provider fan-out via `conversationsProvider`
2. A1 implementation plan should re-estimate coding work above the original
   `1.5 day` number

Claude-Position:
- v2 closes v1 P1 blockers via algorithmic change, not cosmetic relabeling.
- v2 turns token budget and invalidation from hopes into explicit rules.
- A1 estimate was correctly reopened instead of being hand-waved.

Codex-Position:
- v2 closes the v1 P1 blockers.
- Verified by fresh repo grep: `typeId 0..7` are occupied and `typeId = 8` is
  free, so the new `Partner` id no longer collides.
- The migration design is now rerun-safe at spec level: deterministic UUID v5
  from `conversation.id` + `conversation.partnerId` as the marker means partial
  runs converge instead of duplicating Partner rows.
- The token-budget risk is now bounded enough for planning: hard cap `1500`
  chars, `N=8` ranking, and parsed-field assembly instead of raw JSON.
- The Riverpod fan-out issue is reduced to an implementation constraint:
  `conversationsByPartnerProvider(partnerId)` must stay truly partner-scoped and
  not be backed by the full `conversationsProvider`.
- A1 should be re-estimated above the original `1.5 day`; `2-3 dev days` plus
  the planned TF soak is a more realistic planning baseline.

Verdict:
- PASS - spec v2 is approved for A1 implementation planning.

Eric-Decision:
- Pending

Action-Items:
- [x] v1 Codex review completed and critical doc opened.
- [x] Claude revised the spec to address v1 P1 / P2 findings.
- [x] Codex re-reviewed spec v2.
- [x] v2 approved for A1 implementation planning.
- [x] A1-only implementation plan written: `docs/plans/2026-04-25-partner-entity-A1-impl.md`.

Close-Condition:
- Claude has started the A1-only implementation plan from the approved v2 spec. ✅ Met.

Follow-up:
- Plan baked in Codex constraints C1 (partner-scoped provider stays partner-scoped — A2 author responsibility),
  C2 (A1 effort = 2–3 dev days + 1–2 day TF soak), C3 (first impl step re-greps typeId).
- A1 execution + Codex A1 code review = a new queue item once A1 ships, not an append here.
