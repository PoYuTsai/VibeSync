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
Status: APPROVED
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

## [2026-04-28] AddPartner UI Redesign — Code Review (post-A2 follow-up)
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Eric
Scope: review
Branch/Commit: `feature/add-partner-ui-redesign` @ `0d4c930` (final HEAD) → squash-merged to main `f831d33` 2026-04-28 ~14:xx GMT+8 (PR #9)

Question:
- Code review the AddPartner visual / hint redesign diff (1 production file + 1 test file). Verdict options: APPROVED / REVISED_AND_APPROVED (Codex pushes patch directly to branch) / REVISE.

Context:
- Spec source: Bruce Discord channel `1488034916481368147` msg `1498169446240616539` (2026-04-27 11:50) → final lock `1498172229853384856` (2026-04-27 12:01, A1 single free-text).
- Eric 2026-04-28 三軌拍板：
  · Q1b — 紫橘 brand 2-3 顆**靜態** bubble（不抄 IMG_1338 紅綠藍鮮豔）
  · Q2b — 橘色 GradientButton CTA（跟 partner-list FAB 同 token / 動作色）
  · Q3a — hint「例：Alice 🧚🏻‍♀️ / 咖啡廳的捲髮女孩 ☕」保留 emoji
- Architecture invariants 不動：`PartnerRepository.upsertIfAbsent` (A2 唯一 public write) / auth-gate (Codex r1 P2/P1.4) / `pushReplacement` (Codex r1 P1.2) / owner-scoped `partnerListProvider.invalidate` / `_busy` 防 double-submit。

Changed:
- `lib/features/partner/presentation/screens/add_partner_screen.dart` (visual + hint, +146 / -32)
- `test/widget/features/partner/add_partner_screen_test.dart` (finder upgrade + 1 NEW hint test, +21 / -13)

Evidence:
- PR: https://github.com/PoYuTsai/VibeSync/pull/9
- `flutter test add_partner_screen_test.dart` → 5/5 pass + 1 skipped (pre-existing kernel cache hang on `pushReplacement`，not introduced by this PR)
- `flutter test partner subset` (widget + unit + repositories) → 80/80 pass + 1 skip / 0 fail
- `flutter analyze --no-fatal-infos lib test` → 0 issues
- Codex patch verification: `add_partner_screen_test.dart` → 6 pass + 1 skip; partner subset → 81 pass + 1 skip; full `flutter analyze --no-fatal-infos lib test` → 0 issues.
- Claude post-Codex-patch local re-verify (WSL, post `842a552`, 2026-04-28 ~13:xx GMT+8):
  · `flutter test add_partner_screen_test.dart` → 6/6 pass + 1 skip (Codex 新加 "input clears transparent AppBar toolbar" test 過)
  · `flutter analyze --no-fatal-infos lib test` → 0 issues
  · 雙環境（Codex + WSL）一致 — patch 無 platform-dependent 副作用

Open-Risks (Code Review Hot Spots):
- HS-AP-1 — `_name.addListener` lifecycle correctness: GlassmorphicTextField has no `onChanged` callback so CTA enable state listens on the controller. `initState` adds, `dispose` removes-then-disposes. Claude position: order is correct (remove BEFORE dispose), but Codex should confirm no edge case where listener fires after `mounted == false` despite the guard.
- HS-AP-2 — Static bubble visual ≠ `GradientBackground`: 3 `Container + boxShadow` bubbles inside `IgnorePointer` instead of `GradientBackground`'s 3 `AnimationController`-driven `_AnimatedBokehOrb`. Reason: avoid `pumpAndSettle` hang in widget tests (memory id 703). Trade-off: no breathing/floating animation. Claude position: tradeoff documented inline; if Codex thinks animation is essential, must also rewrite all 4 active tests' pump strategy.
- HS-AP-3 — `extendBodyBehindAppBar: true` + transparent AppBar: lets the gradient bg paint underneath the AppBar. Claude position: AppBar text + back arrow explicitly set to `onBackgroundPrimary` so they remain readable; no theme override leaks elsewhere.
- HS-AP-4 — Hint emoji ZWJ chain (`🧚🏻‍♀️` = base + skin tone + ZWJ + female ♀️): test asserts via `find.text(...)` exact match. Claude position: literal copy from Bruce's message preserves codepoint sequence; cross-platform render parity is iOS/Android system font concern (out of scope for this PR).
- HS-AP-5 — `GradientButton.isLoading: _busy` semantic: existing `_busy` mutex prevents double-submit; passing it to `isLoading` shows the spinner during async submit. Claude position: matches GradientButton's documented disable-when-loading contract; no behavioral change to submit chain.

Claude-Position:
- Self-review: 1 production file + 1 test file change / 0 architecture mod / existing brand widgets reused (GlassmorphicTextField + GradientButton + AppColors tokens) / static bubble pattern picks brand colors over IMG_1338 rainbow.
- Patches I want Codex to specifically scrutinize:
  · `_name.addListener` / `removeListener` lifecycle vs `setState` mounted guard
  · Bubble Stack z-order (bubbles behind input via Stack children order + IgnorePointer)
  · Test finder migration `FilledButton` → `GradientButton` and `TextFormField` → `TextField` (latter because GlassmorphicTextField uses TextField internally)
- Deferred: TF visual smoke (Eric + Bruce on TF build from this branch — see Action-Items).

Codex-Position:
- REVISED_AND_APPROVED. No remaining P1/P2 blockers. I patched the transparent-AppBar layout trap: `extendBodyBehindAppBar` now keeps the gradient under the AppBar while the form content clears `kToolbarHeight`; added a widget regression test for the input/AppBar spacing. Listener lifecycle, static bubbles, emoji hint, and `GradientButton.isLoading` all look acceptable for this visual-only follow-up.
- Review doc: `docs/reviews/2026-04-28_addpartner-ui-redesign-code_codex-review.md`

Verdict:
- REVISED_AND_APPROVED

Eric-Decision:
- APPROVED + merged. TF visual smoke 4/4 pass（hint emoji ✅ / bubble placement ✅ / 紫底橘 CTA 對比 ✅ / spinner 顯示 ✅）。Squash-merged `f831d33` 2026-04-28 ~14:xx GMT+8.

Action-Items:
- [x] Codex code reviews PR #9 diff
- [x] If REVISED_AND_APPROVED: Codex pushes patch commit directly to branch (`842a552`)
- [x] Eric / Bruce visually confirm on TF build (4/4 pass)
- [x] Merge to main once both gates pass (squash `f831d33`)

Close-Condition:
- PR #9 merged to main with Codex APPROVED/REVISED_AND_APPROVED + Eric/Bruce visual smoke pass.

Closing Notes (Claude, 2026-04-28 ~14:xx GMT+8):
- Post-A2 first follow-up shipped — testing queue Item #3 (Bruce 4/27 AddPartner UI A1 spec) 落地。
- 4 source/doc commits squashed → main `f831d33`（327 insertions / 38 deletions across 4 files）。
- Codex `842a552` patch caught HS-AP-3 layout trap I missed（input 在 transparent AppBar 下方但沒留 toolbar height padding）；新 test "input clears transparent AppBar toolbar" 入庫防回歸。
- 0 architecture mod — 既有 brand widgets (GlassmorphicTextField + GradientButton + AppColors tokens) 全部復用。
- Next: TF soak 與 A2 baseline 平行進行；testing queue Item #1 (編輯文字 action) + Item #2 (改為新對話) 累積中。

---

## [2026-04-28] Partner Entity Refactor - A2 Phase 4 Code Review (Polish + Ship)
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Eric
Scope: review
Branch/Commit: `feature/partner-entity-A2-polish` @ `8fb3e2f` (final HEAD) → squash-merged to main `f1b936e` 2026-04-28T03:54:56Z (PR #8)

Question:
- Code review the Phase 4 production diff (9 commits, Tasks 1-8 mapped from
  design Tasks 18a/18b/14a/14b/15/16a/16b). Verdict options:
  APPROVED / REVISED_AND_APPROVED (Codex pushes patch commit directly to
  branch) / REVISE.

Context:
- 5 Daisy-Decisions D-P4-1 ~ D-P4-5 全 locked（design doc §4，cascade =
  block / banner pre-fill = older→target / preview = interleave then cap 3 /
  heat fallback `🌡️ 待分析` / banner flag per-uid SP key）
- 9 patches 已驗證落地（5 spec + 4 plan）；Phase 4 incremental subset 109
  pass / 1 skip / 0 fail
- 8 commits 都是 atomic per task / push after each：`28d0746` (Task 1 repo
  delete + cascade guard), `7585497` (Task 2 5-piece visual + delete dialog),
  `6f73208` (Task 3 PartnerBannerService), `e9a7fcd` (Task 4 banner widget +
  merge picker preselect), `e4bbc4f` (Task 4 polish dispose race guard),
  `782d73a` (Task 5 copy sweep), `30a529d` (Task 6 砍 @Deprecated
  HomeContent), `b5a1425` (Task 7 doc closeout)
- Architectural invariants: card stays pure render / lifted-aggregate API /
  try/finally invalidation pattern continues / `delete()` does NOT
  invalidate global `conversationsProvider` (HP-P4-1) / owner-scoped merge
  picker validation

Changed:
- `lib/features/partner/data/repositories/partner_repository.dart` (Task 1 delete + exception)
- `lib/features/partner/data/providers/partner_write_controller.dart` (Task 1 invalidation)
- `lib/features/partner/presentation/widgets/partner_list_card.dart` (Task 2 NEW)
- `lib/features/partner/presentation/screens/partner_list_screen.dart` (Task 2 delete dialog two-mode)
- `lib/features/partner/data/services/partner_banner_service.dart` (Task 3 NEW)
- `lib/features/partner/data/providers/partner_banner_providers.dart` (Task 3 NEW)
- `lib/features/partner/presentation/widgets/same_name_dedupe_banner.dart` (Task 4 NEW)
- `lib/features/partner/presentation/screens/partner_merge_picker_screen.dart` (Task 4 preselect)
- `lib/app/main_shell.dart` (Task 5 FAB tooltip)
- `lib/features/conversation/presentation/screens/home_screen.dart` (Task 6 砍 HomeContent)
- `docs/testflight-regression-checklist.md` (Task 7 J section)
- `docs/decisions.md` (Task 7 ADR-15 v2 ship section)
- `docs/snapshot.md` (Task 7 refresh)
- `CLAUDE.md` / `AGENTS.md` (Task 7 1 Pitfall + sync)

Evidence:
- PR: https://github.com/PoYuTsai/VibeSync/pull/8
- Branch HEAD reviewed: `f991359`
- Spec review: [`docs/reviews/2026-04-28_partner-entity-A2-phase4-spec_codex-review.md`](2026-04-28_partner-entity-A2-phase4-spec_codex-review.md)
- Plan review: [`docs/reviews/2026-04-28_partner-entity-A2-phase4-impl_codex-review.md`](2026-04-28_partner-entity-A2-phase4-impl_codex-review.md)
- Phase 4 incremental tests: 109 pass / 1 skip / 0 fail
- Codex patch verification: targeted WSL `flutter analyze` on 3 touched Dart files
  passed; hot spot widget tests (`partner_list_screen_test.dart`,
  `partner_merge_picker_screen_test.dart`, `same_name_banner_test.dart`) passed
  25/25.
- Lint: `flutter analyze --no-fatal-infos lib test` → 0 issues
- Claude post-Codex-patch local re-verify (WSL, post `77f93d4`, 2026-04-28 04:00ish GMT+8):
  · `flutter analyze --no-fatal-infos lib test` → 0 issues
  · partner widget subset 25/25 pass (`partner_list_screen_test.dart` + `partner_merge_picker_screen_test.dart` + `same_name_banner_test.dart`)
  · Codex `debugPrint` breadcrumb visible in "merge failure shows snackbar" test stdout
    (firing as designed, not a regression — TF console will now surface root cause instead of empty SnackBar)

Open-Risks (Code Review Hot Spots):
- HS-Code-1 — `PartnerListCard._previewTags` interleave correctness on
  edge inputs (interests=5 traits=0) / (interests=0 traits=5). Claude
  position: max-len loop covers both ends, fallback takes remaining n side.
- HS-Code-2 — Delete dialog two-mode race during dialog open: a
  conversation gets created between `convCount` read and `delete()` call.
  Claude position: defensive `try/catch PartnerHasConversationsException`
  on the destructive path catches the race.
- HS-Code-3 — Banner FutureProvider invalidate → re-render guarantee:
  after dismiss, `ref.invalidate(partnerDedupeBannerDismissedProvider(uid))`
  must trigger banner widget rebuild and hide. Claude position: PR-B
  precedent `0187685` confirms invalidate triggers rebuild.
- HS-Code-4 — Merge picker preselect tap-other-row no auto-open: tapping
  a non-preselected row must NOT auto-open the destructive dialog. Claude
  position: preselect only seeds bottom CTA state, dialog requires explicit
  CTA tap.
- HS-Code-5 — Copy sweep coverage gaps: any popup or dialog string still
  mixing 對象/對話 vocabulary? Snapshot tests cover home FAB tooltip +
  partner list empty + partner detail "+ 新增對話" but may miss dialogs.

Claude-Position:
- Self-review: 8 commits atomic / each push triggers CI / Phase 4
  incremental test subset all green / 4 new file lint clean / 9
  spec+plan patches verified shipped / no late drift
- Patches I want Codex to specifically scrutinize:
  · `delete()` invalidation surface (intentionally narrower than merge per HP-P4-1)
  · Owner-scoped `partnerListProvider` validation in merge picker
  · `convCount` source = `conversationsByPartnerProvider(p.id).length`
    (NOT `aggregate.totalRounds`)
- Deferred: 5-path manual smoke (Eric on TF build per plan §10.2)

Codex-Position:
- REVISED_AND_APPROVED. No remaining P1/P2 blockers. I patched the only actionable review concern: new Phase 4 generic catch paths now emit `debugPrint` breadcrumbs for banner dismiss invalidation, partner delete fallback, and merge fallback. Hot spots checked: `_previewTags` edge behavior OK, delete race handled by `PartnerHasConversationsException`, banner dismiss provider invalidation has widget coverage, merge preselect does not auto-open destructive flow, copy sweep stays inside ADR-15 vocabulary boundary.
- Review doc: `docs/reviews/2026-04-28_partner-entity-A2-phase4-code_codex-review.md`

Verdict:
- REVISED_AND_APPROVED

Eric-Decision:
- APPROVED + merged. TF smoke 13/13 pass (J1 delete cascade ✅ / J2 banner functional ✅ / J3 preselect ✅ — Eric clarified "not a bug, just UX exploration" / J4 visual ✅ / J5 copy ✅). Squash-merged `f1b936e` 2026-04-28T03:54:56Z.

Action-Items:
- [x] Codex code reviews PR #8 diff
- [x] If REVISED_AND_APPROVED: Codex pushes patch commit directly to branch (`77f93d4`)
- [x] Eric runs 5-path manual smoke on TF build (13/13 pass, J3 not-a-bug clarified)
- [x] Merge to main once both gates pass (squash `f1b936e`)

Close-Condition:
- PR #8 merged to main with Codex APPROVED/REVISED_AND_APPROVED + Eric manual smoke pass.

Closing Notes (Claude, 2026-04-28 ~12:00 GMT+8):
- A2 Partner Refactor 全 ship — Phase 1-4 完整收尾，ADR-15 v2 ship 段落生效。
- 9 source commits + 3 doc commits squashed into single ship commit `f1b936e`
  (3241 insertions / 463 deletions across 31 files).
- 5 Daisy-Decisions D-P4-1 ~ D-P4-5 全 untouched 落地。
- Codex `77f93d4` patch（debugPrint × 3 + const TextStyle）兩環境 25/25。
- Post-A2 testing queue items（**不歸 A2 phase**）:
  · 新增對象 UI redesign（Bruce spec，待 Discord channel/時間從 Eric 提供）
  · J2 product nudge — 合併成功 SnackBar 加引導到「我的報告」tab
  · J3 anti-pattern observation — 連續 merge（合併後再從目標 detail 進第二輪 merge picker）
    用戶實際是否會這樣使用，soak 期觀察
- Next: TF soak ~2 週 → 送審。

---

## [2026-04-28] Partner Entity Refactor - A2 Phase 4 Implementation Plan Review
Status: APPROVED
Request-Type: review
Raised-By: Claude
Owner: Claude
Scope: review
Branch/Commit: `feature/partner-entity-A2-polish` @ `825a5d2` + Codex plan patch (impl plan only; production code not yet started)

Question:
- Spec review the Phase 4 implementation plan covering Tasks 1-8 (mapped from
  design doc Tasks 18a/18b/14a/14b/15/16a/16b/17). Verdict: APPROVED /
  REVISED_AND_APPROVED (with patches) / REVISE.

Context:
- Design doc 已 REVISED_AND_APPROVED (Codex r1, `1c74722`)，5 patches 已落
- Implementation plan 嚴格對齊 patched design contract：
  · Task 1 repo guard 用 `_conversationBox.values`（無 listByPartner）
  · Task 1 controller invalidate `partnerListProvider`（非 family）+
    `partnerByIdProvider(id)` + `partnerAggregateProvider(id)` +
    `conversationsByPartnerProvider(id)`
  · Task 2 conversationCount from `conversationsByPartnerProvider(p.id).length`
    （不是 aggregate.totalRounds）
  · Task 3 `FutureProvider.family<bool, String>` for banner async state
  · Task 4 merge picker `initialTargetId` 4-case contract（null / valid /
    self / unknown）
  · Task 2 `_previewTags` interleave interests/traits 再 cap 3
- 預期 7 production commits + 1 queue update（不含 Codex code review patch）
- Branch: `feature/partner-entity-A2-polish` 已切，從 main `1c74722`

Changed:
- `docs/plans/2026-04-28-partner-entity-A2-phase4-impl.md` (new, 926 lines, on branch only)
- `docs/reviews/2026-04-28_partner-entity-A2-phase4-impl_codex-review.md` (Codex r1 verdict)

Evidence:
- Plan: [`docs/plans/2026-04-28-partner-entity-A2-phase4-impl.md`](../plans/2026-04-28-partner-entity-A2-phase4-impl.md) (read on branch `feature/partner-entity-A2-polish`)
- Patched design doc: [`docs/plans/2026-04-28-partner-entity-A2-phase4-design.md`](../plans/2026-04-28-partner-entity-A2-phase4-design.md)
- Codex spec review r1: [`docs/reviews/2026-04-28_partner-entity-A2-phase4-spec_codex-review.md`](2026-04-28_partner-entity-A2-phase4-spec_codex-review.md)
- Codex impl plan review r1: [`docs/reviews/2026-04-28_partner-entity-A2-phase4-impl_codex-review.md`](2026-04-28_partner-entity-A2-phase4-impl_codex-review.md)

Open-Risks (Codex Plan Review Hot Spots):
- HP-P4-1 — Task 1 controller `delete()` 是否該也 invalidate `conversationsProvider`？
  (Claude position: yes — 對齊 merge `_invalidateMergeScopes` line 54 既有
  pattern，A2 transition 期間 reportDataProvider 還在讀 global feed)
- HP-P4-2 — Task 2 `_previewTags` interleave 邊界 (interests=0 traits=5)
  / (interests=5 traits=0) 是否都正確？
  (Claude position: 已寫 max-len loop，0/n 兩端會 fallback 取 n side)
- HP-P4-3 — Task 4 preselect mode 是否破壞 PR-B Task 12 既有 widget tests？
  (Claude position: PR-B tests 都假設無 query param，preselect=null path 維持
  原行為，向後相容)
- HP-P4-4 — Task 6 砍 HomeContent 後，是否有 route fallback 回 `/home` 還活著？
  (Claude position: pre-flight grep step 6.1 + verification step 6.3 雙 gate)
- HP-P4-5 — Task 5 copy sweep 是否漏掉 banner 文案 / preselect CTA 文案？
  (Claude position: Task 5 排在 banner + visual 之後，掃時應該都已 ship)

Claude-Position:
- Plan 對齊 Codex spec review 5 patches，TDD 紀律 RED → GREEN per task
- 7 commits / atomic per task / push after each
- Hot spots HP-P4-1 ~ HP-P4-5 已標出來，請 Codex 重點看 invalidation
  surface、interleave 邊界、PR-B 相容性
- 執行階段預期 1-2 dev days，code review 1-2 輪

Codex-Position:
- REVISED_AND_APPROVED. Plan sequencing and task split are good, but I patched four execution traps before implementation:
  1. Task 1 repo delete test now lives with existing repository tests under `test/unit/repositories/` and uses the real `partner_repository_merge_test.dart` Hive setup pattern. The previous snippet missed `Conversation.messages/createdAt` and referenced a non-local helper.
  2. Task 1 `PartnerWriteController.delete()` must not invalidate `conversationsProvider`. Unlike merge/reassign, delete only succeeds when linked conversation count is zero, so the global conversation feed never changes.
  3. Task 2 explicitly adds required imports for `DateFormat`, `GlassmorphicContainer`, and `EnthusiasmLevel`, and tells Claude to update old PartnerListScreen tests that still assert `N 段對話`.
  4. Task 4 preselect validation now uses owner-scoped `partnerListProvider` candidates, not raw `partnerByIdProvider`, so `?target=` cannot select a partner outside the current account/candidate list.
- HP-P4-2: interleave loop is acceptable after edge tests for interests-only and traits-only.
- HP-P4-3: preselect=null path remains compatible with PR-B tests if the screen is converted to `ConsumerStatefulWidget` only for selected-target state.
- HP-P4-4/5: HomeContent grep gate and copy sweep ordering are acceptable.

Verdict:
- REVISED_AND_APPROVED

Action Items (post-verdict):
- [x] Codex merged main queue item into `feature/partner-entity-A2-polish`.
- [x] Codex patched implementation plan and wrote r1 review doc.
- [x] Claude executes Tasks 1-8 on branch from the patched plan, with flutter test + analyze gates per task. (8 commits `28d0746` → `b5a1425`, push after each; Phase 4 incremental subset 109 pass / 1 skip / 0 fail; `flutter analyze --no-fatal-infos lib test` → 0 issues)
- [ ] If Claude disagrees with the `conversationsProvider` narrowing, update this same item instead of opening a parallel thread. (No disagreement — Claude shipped the narrower invalidation surface per Codex r1 patch HP-P4-1.)

Close-Condition:
- Claude acknowledges patched plan or starts execution.
- 之後再開 code review item（Task 8 step 8.4）

---

## [2026-04-28] Partner Entity Refactor - A2 Phase 4 (Polish + Ship) Spec Review
Status: APPROVED
Request-Type: review
Raised-By: Claude
Owner: Claude
Scope: review
Branch/Commit: `main` @ `cd7470e` + Codex spec patch (design doc + review doc; impl branch not yet cut)

Question:
- Spec review the Phase 4 design doc covering Tasks 14-18 + hidden Partner
  delete API. Verdict: APPROVED / REVISED_AND_APPROVED (with patches) /
  REVISE.

Context:
- A2 Phase 1-3 全 ship 在 main `1794371`，Phase 4 是 A2 收場（polish + ship）
- 5 Daisy-Decision 已 locked 在 brainstorm（D-P4-1 ~ D-P4-5），design doc §4
- Brainstorm 過 6 sections，Eric 全程 confirm，每段 OK
- Tasks 14-18 sequencing：18 → 14 → 15 → 16 → 17（理由 design doc §5）
- Hidden scope：Task 18 內含 Partner delete API（PR-B handoff "delete handler"
  收下來，與視覺還原同 Task 拆 18a/18b）
- 預估 7 commits、0 hotfix、CI partner-subset 自動跑（Phase 3 PR-B Task 8 已 ship）

Changed:
- `docs/plans/2026-04-28-partner-entity-A2-phase4-design.md` (new, 500 lines)
- `docs/reviews/2026-04-28_partner-entity-A2-phase4-spec_codex-review.md` (Codex r1 verdict)

Evidence:
- Design doc: [`docs/plans/2026-04-28-partner-entity-A2-phase4-design.md`](../plans/2026-04-28-partner-entity-A2-phase4-design.md)
- Master plan reference: [`docs/plans/2026-04-26-partner-entity-A2-impl.md`](../plans/2026-04-26-partner-entity-A2-impl.md) Tasks 14-17
- ADR-15: [`docs/decisions.md`](../decisions.md)
- Predecessor reviews: PR-A `5cf7cc5` queue close / PR-B `1794371` queue close

Open-Risks (Codex Spec Review Hot Spots):
- HS-P4-1 — `PartnerHasConversationsException` 是否需要 enum 而非單 exception？
  (Claude 評估：YAGNI，Phase 4 只一種 failure reason)
- HS-P4-2 — `try/finally` invalidation 在 delete 是否 over-applied？
  (Claude 評估：保險，對齊 PR-B Codex r1 patch pattern)
- HS-P4-3 — Banner detection 在 presentation 層 derive 是否該抽 domain extension？
  (Claude 評估：純 presentation only，不污染 domain — 但值得 Codex 提意見)
- HS-P4-4 — Merge picker route 加 `?target=` query param 是否破壞 Phase 3 PR-B 既有行為？
  (Claude 評估：optional param，向後相容；但要 Codex 驗 init flow)
- HS-P4-5 — Tag preview「興趣+特質前 3」順序 take vs interleave？
  (Claude 評估：值得 Codex 提意見 — 用戶可能更想要至少 1 個 trait)

Claude-Position:
- Design 經 6 sections brainstorm + Eric 全段 confirm，5 Daisy-Decision 全 locked
- Hidden scope (Partner delete API) 揭露在 §2，拆 18a/18b 因 cascade guard 是
  獨立可測單元
- 7 commits 預估 + Codex code review (post-execute) 預期 1-2 輪
- Sequencing 18 → 14 → 15 → 16 → 17 因 (a) Bruce 視覺反饋優先 (b) Task 18
  visual donor `@Deprecated HomeContent` 必須 Task 16 砍前還活著 (c) 文案掃在
  banner + visual 後做避免重掃

Codex-Position:
- REVISED_AND_APPROVED. Phase 4 sequencing is sound, but I patched four contract gaps before implementation:
  1. Partner delete API now matches shipped code: `PartnerRepository.delete()` scans `_conversationBox.values`; `PartnerWriteController.delete()` invalidates non-family `partnerListProvider` plus partner/id aggregate scopes.
  2. Delete UI guard now uses `conversationCount` from `conversationsByPartnerProvider(partner.id).length`, not `aggregate.totalRounds`; zero-round conversations still block delete.
  3. Same-name banner dismissed state now has a `FutureProvider.family<bool, uid>` contract, avoiding build-time await and SharedPreferences flicker.
  4. Merge picker `?target=` semantics are locked: no query preserves PR-B behavior, valid target preselects without auto-opening a destructive dialog, self/unknown target ignored.
- HS-P4-5 patched to interleave interests/traits before cap 3 so traits are not starved.
- HS-P4-1 enum is YAGNI; HS-P4-2 try/finally invalidation acceptable after API correction; HS-P4-3 presentation duplicate detection acceptable.

Verdict:
- REVISED_AND_APPROVED

Action Items (post-verdict):
- [x] Codex patched design doc and wrote review doc.
- [ ] Claude reads patched design doc, cuts `feature/partner-entity-A2-polish`, writes implementation plan, and opens a new queue item「A2 Phase 4 Implementation Plan Review」if needed.
- [ ] If Claude disagrees with a patch, update this same item instead of opening a parallel thread.

Close-Condition:
- Claude acknowledges the patched spec or starts the Phase 4 implementation plan.

---

## [2026-04-27] Partner Entity Refactor - A2 Phase 3 PR-B Code Review (Merge Picker + Reassign ⋮ Menu)
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Claude
Scope: review
Branch/Commit: `feature/partner-entity-A2-flows-pickers` @ `a7aa667` + Codex follow-up patch

Question:
- Code review the 8-commit PR-B implementation (`0d5dcb5..a7aa667`) against
  the REVISED_AND_APPROVED plan (`843d98f`) + Phase 3 design doc. Verdict:
  APPROVED / REVISED_AND_APPROVED (with concrete patches) / REVISE.

Context:
- Plan executed task-by-task with TDD per Codex r2-approved steps.
- 8 commits, all atomic per task, all pushed:
  - `0ce4d12` Task 1 — PartnerWriteController + 4 unit tests
  - `bc94eff` Task 2 — PartnerPickerSheet + 4 widget tests
  - `0d5dcb5` Task 3 — PartnerMergeConfirmDialog + 4 widget tests
  - `3da04d6` Task 4 — ⋮ merge enable + PartnerMergePickerScreen + GoRoute
    + 7 widget tests (5 picker + 2 detail flow)
  - `bb3c756` Task 5 — PartnerConversationTile chevron→⋮ + 5 widget tests
  - `3affa8e` Task 6 — ConversationReassignPicker modal + 4 widget tests
  - `3227d2c` Task 7 — wire onReassign from PartnerDetail + 1 widget test
  - `a7aa667` Task 8 — flutter-ci.yml subset expand (partner unit +
    conversation widget)
- Verification gate at HEAD `a7aa667`:
  - `flutter test test/widget/features/partner/`        → 42/0/1 (pass/fail/skip)
  - `flutter test test/widget/features/conversation/`   → 6/0/0
  - `flutter test test/unit/features/partner/`          → 4/0/0
  - **Total CI subset: 52 pass / 1 skip / 0 fail**
  - `flutter analyze --no-fatal-infos lib test`         → 1 info (pre-existing
    library_private_types_in_public_api in `partner_write_controller_test.dart:45`,
    Task 1 from parallel session)
- Phase 4 territory NOT touched (delete handler, same-name banner, copy
  sweep, PartnerListCard visual restoration).

Changed Files (vs `0d5dcb5` baseline):
- Production:
  - new `lib/features/partner/presentation/screens/partner_merge_picker_screen.dart`
  - new `lib/features/conversation/presentation/dialogs/conversation_reassign_picker.dart`
  - mod `lib/features/partner/presentation/screens/partner_detail_screen.dart` (⋮ enable + onReassign wire)
  - mod `lib/features/partner/presentation/widgets/partner_conversation_tile.dart` (trailing → ⋮ + onReassign prop)
  - mod `lib/app/routes.dart` (+1 GoRoute for `/partner/:partnerId/merge`)
- Tests:
  - new `test/widget/features/partner/_fakes/recording_partner_write_controller.dart`
  - new `test/widget/features/partner/_fakes/recording_conversation_write_controller.dart`
    (parallel to PR-A's; Phase 4 cleanup unifies — annotated)
  - new `test/widget/features/partner/partner_merge_picker_screen_test.dart`
  - new `test/widget/features/partner/conversation_reassign_picker_test.dart`
  - new `test/widget/features/partner/partner_conversation_tile_test.dart`
  - mod `test/widget/features/partner/partner_detail_screen_test.dart` (merge enable + tile reassign + nav)
- CI: `.github/workflows/flutter-ci.yml` (subset list updated)

Reviewer-Hint:
- (R1) Modal sheet test trap: `showModalBottomSheet`'s 250ms slide animation
  required `pumpAndSettle()` instead of PR-A's `_settle()` helper. PartnerDetail
  / PartnerMergePickerScreen don't wrap GradientBackground so pumpAndSettle is
  safe in this scope. Documented in commit `3affa8e` body.
- (R2) Reassign picker uses optimistic `conversation.partnerId` mutation with
  rollback on save throw. The test
  `save failure rolls back conversation.partnerId + shows SnackBar` proves
  rollback; SnackBar parented to `sheetCtx`'s ScaffoldMessenger so it surfaces
  even with sheet still open.
- (R3) `PartnerConversationTile.onReassign` is optional. Null = ⋮ "改派" still
  visible but disabled (matches "刪除（即將推出）" pattern). Test verifies
  enabled flag via PopupMenuItem widget instance lookup.
- (R4) Two `RecordingConversationWriteController` files exist in two test
  locations (PR-A scope captures only `create`; PR-B scope captures `save`
  + previousPartnerId snapshot + throwOnSave). Phase 4 cleanup tagged in both
  files' headers.
- (R5) Merge picker confirm dialog reads `fromAgg.unionTraits.length` per
  Codex r1 patch (not the nonexistent `traits` / `count` fields).
- (R6) ⋮ menu auto-disables (label + state) when `partnerListProvider` has
  only self — covers "first-time user with one partner can't accidentally
  open empty merge picker" case.

Open-Risks:
- (Q1) Should the SnackBar in reassign-picker failure path also auto-pop the
  modal sheet, or stay open as currently coded? UX trade-off: stay open
  lets user retry; pop closes context but loses their place. Plan said stay
  open; impl follows plan. Codex feel free to challenge.
- (Q2) `PartnerWriteController.merge` invalidates `conversationsProvider`
  (legacy global feed) per A2 transition contract (line 36 of controller).
  Tagged for retirement in post-A2 cleanup PR. Acceptable as transition wart?
- (Q3) Pre-existing info-level lint
  (library_private_types_in_public_api in `partner_write_controller_test.dart:45`)
  inherited from Task 1 parallel session. Not produced by this batch. Leave
  for separate cleanup, or fix here?

Evidence:
- Branch tip: `a7aa667`
- Plan: [docs/plans/2026-04-27-partner-entity-A2-phase3-pr-b-impl.md](../plans/2026-04-27-partner-entity-A2-phase3-pr-b-impl.md)
- Spec review (closed): item below

Codex-Position:
- (r1 2026-04-27) `REVISED_AND_APPROVED`.
- Patched one P2 failure-path cache risk: `PartnerWriteController.merge()` now
  invalidates both partner/conversation scopes in `finally`, so partial Hive
  writes are surfaced even when `PartnerRepository.merge()` throws.
- Added unit coverage for partial merge failure and cleaned the info-level
  `library_private_types_in_public_api` lint in
  `partner_write_controller_test.dart`.
- Q1: accept current reassign failure UX. Keep sheet open so the user can retry;
  rollback test covers `conversation.partnerId`.
- Q2: accept `conversationsProvider` invalidation as A2 transition wart, tagged
  for post-A2 cleanup.
- Q3: fixed here, no separate cleanup item.
- Local Codex verification caveat: Windows Flutter runner timed out and WSL hit
  the Windows Flutter CRLF shim. Claude/WSL should rerun:
  `flutter test test/unit/features/partner/partner_write_controller_test.dart`.

Verdict:
- REVISED_AND_APPROVED

Claude-Position:
- (verify 2026-04-27) WSL Linux Flutter 3.41.2 runner — both gates pass at
  `0187685`:
  - `flutter test test/unit/features/partner/partner_write_controller_test.dart`
    → 5 pass / 0 fail（含 Codex 新增的 `merge failure still invalidates
    scopes after partial repo write`）
  - `flutter analyze lib/features/partner/data/providers/partner_write_controller.dart
    test/unit/features/partner/partner_write_controller_test.dart`
    → No issues found（Q3 pre-existing info-lint 已被 Codex 在這 commit 清掉）
- Q1/Q2/Q3 三個 Open-Risks 接受 Codex verdict，無 Round 2。
- PR-B 解鎖：next step `gh pr create`，Eric merge。

Action Items:
- [x] Codex code reviews PR-B implementation diff
- [x] Codex verdict: REVISED_AND_APPROVED
- [x] If REVISED_AND_APPROVED: Codex patches in-place per
  `docs/shared-agent-rules.md` close-out matrix
- [x] Claude reruns touched unit test in WSL after Codex patch
- [x] Eric merges PR — squash-merged via PR #7 → `a38d46e` on main
  （flutter-ci.yml partner subset passed 2m4s before merge）

Close-Condition:
- Codex APPROVED + Eric merges → Status CLOSED, item kept ~1 week
  for traceability then pruned

---

## [2026-04-27] Partner Entity Refactor - A2 Phase 3 PR-B (Merge Picker + Reassign ⋮ Menu) Spec Review
Status: CLOSED
Request-Type: spec-review
Raised-By: Claude
Owner: Claude
Scope: review
Branch/Commit: `feature/partner-entity-A2-flows-pickers` @ `f3eba44`

Question:
- Does the PR-B impl plan correctly cover Tasks 12+13 (merge picker + reassign
  ⋮ menu) without leaking Phase 4 scope (delete handler / same-name banner /
  copy sweep), AND are the design-doc deviations called out below acceptable?

Context:
- Phase 3 design doc: `docs/plans/2026-04-27-partner-entity-A2-phase3-design.md`
- Master plan Tasks 12-13: `docs/plans/2026-04-26-partner-entity-A2-impl.md`
  lines 970-1028
- PR-A (Tasks 10+11 — partnerId chain validation tests) is merged to `main`
  via PR #5. PR-B branch has merged latest `main` and is no longer reviewing
  against stale queue state.
- Plan path: `docs/plans/2026-04-27-partner-entity-A2-phase3-pr-b-impl.md`
- Branch originally cut from main `f2e791d`; Codex merged latest `main` and
  patched the plan at `843d98f`.

Changed:
- Cut new branch `feature/partner-entity-A2-flows-pickers` from main (`f2e791d`).
- Wrote PR-B impl plan with bite-sized TDD steps for 8 tasks (~15-20 widget
  tests + 3 unit tests + 5 new prod files + 3 modify points).
- Codex merged latest `main` into the branch and patched the plan to r2:
  auth override shape, aggregate field names, async merge confirmation,
  reassign rollback, and partner unit CI gate.
- Verified ground truth before drafting: PartnerRepository.merge surface, no
  PartnerWriteController exists, ConversationWriteController.save signature
  takes previousPartnerId, PartnerConversationTile is StatelessWidget,
  PartnerDetail uses plain Scaffold (no GradientBackground — pumpAndSettle OK
  here).

Evidence:
- Plan: [docs/plans/2026-04-27-partner-entity-A2-phase3-pr-b-impl.md](../plans/2026-04-27-partner-entity-A2-phase3-pr-b-impl.md)
- Design doc reference: §3 / §5 / §7

Open-Risks:
- (R1) **Design doc §5 deviation — PartnerWriteController introduced.**
  Design doc claimed "Riverpod aggregate invalidation 由 repo 觸發（A1 已
  tested）". This is wrong: PartnerRepository has no Ref. Plan adds a new
  PartnerWriteController (Notifier) mirroring Phase 1 ConversationWriteController
  to own merge-side invalidation. **Needs explicit Codex acknowledge**.
- (R2) **`showCreateNewAction: true` deferred.** Design doc §5 listed
  `showCreateNewAction: true` for reassign picker. Plan ships without it
  (push-and-return reassign flow non-trivial); empty state shows hint
  pointing to home. Acceptable as Phase 3 scope, or push back?
- (R3) **`PartnerRepository.merge` bypasses `ConversationWriteController`.**
  Direct Hive write of `c.partnerId = toId` violates Phase 1 narrow-write
  contract. PR-B does NOT rewrite merge to use the controller (would break
  transaction boundary); instead PartnerWriteController post-hoc invalidates
  both `conversationsByPartnerProvider(from)` + `conversationsByPartnerProvider(to)`
  for equivalence. Codex must acknowledge.
- (R4) **Tile trailing chevron → ⋮.** Design doc §3 already locked B-variant
  trigger. Plan inherits. master plan line 1012 long-press test stays NOT
  implemented (master plan was pre-Phase 1).
- (R5) **Resolved by Codex r1.** `PartnerAggregateView` exposes
  `unionTraits`; plan now uses `fromAgg.unionTraits.length`.
- (R6) **Fake notifier choice.** PR-A is merged, so the conversation fake is
  not off-limits. Existing fake only captures `create()`, so PR-B may either
  extend it or add a reassign-specific partner fake and consolidate in Phase 4.

Claude-Position:
- (r1) Plan as-is is the right entry. PartnerWriteController is the correct
  response to the design-doc gap (consistency with Phase 1 architecture, also
  amortizes future delete handler in Phase 4). showCreateNewAction deferral
  is pragmatic; functionality survives without it.

Codex-Position:
- (r1 2026-04-27) `REVISED_AND_APPROVED`.
- Direction is approved after direct plan fixes in `843d98f`.
- Fixed blockers: async merge hidden behind `VoidCallback`, nonexistent
  `_StubAuthScope` / `count` / `traits` symbols, reassign failure rollback,
  and missing partner unit CI gate.
- Review doc:
  [docs/reviews/2026-04-27_partner-entity-A2-phase3-pr-b-plan_codex-review.md](./2026-04-27_partner-entity-A2-phase3-pr-b-plan_codex-review.md)

Verdict:
- REVISED_AND_APPROVED

Action Items:
- [x] Codex spec review verdict: REVISED_AND_APPROVED
- [x] Codex patched plan r2 at `843d98f`
- [x] Claude executed plan Tasks 1-8 (`0ce4d12..a7aa667`)
- [x] Code review handed off via new top-of-queue item

Close-Condition:
- Plan execution started + completed → CLOSED. See top-of-queue item for
  code review round.

---

## [2026-04-27] Partner Entity Refactor - A2 Phase 3 PR-A Spec Review (partnerId Chain Validation)
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Eric
Scope: review
Branch/Commit: `main` @ `f2ab222` (merged PR #5; review fix `d6cb659`)

Question:
- Does the PR-A impl plan(`docs/plans/2026-04-27-partner-entity-A2-phase3-pr-a-impl.md`)
  correctly scope to「驗 Phase 2 已接通的 partnerId chain」without smuggling
  in production code that should belong to Phase 4? Specifically: is the
  Reality Check section's choice to NOT test auto-derive-on-create + default
  name behavior correct, given that those don't exist in current code and
  master plan Task 11 wrote them as aspirational?

Context:
- Phase 3 design doc (commit `bc1017d` on `main`) split Phase 3 into two
  sub-PRs: PR-A (Tasks 10+11 — partnerId chain validation) → PR-B
  (Tasks 12+13 — picker handlers).
- PR-A scope per design: pure validation work, ideally 0 production code,
  unless tests reveal a real chain regression.
- Reality check during plan-write found two master-plan assumptions that
  contradict current code:
  1. master plan Task 11 step 3 says「null fallback 走 PartnerIdFactory
     自動建（A1 已存在）」— but `ConversationRepository.createConversation`
     line 68-92 stores `partnerId: null` directly, no auto-derive.
     `PartnerIdFactory.deriveFromConversationId` is only called by the A1
     migration service on app start.
  2. master plan Task 10 step 1 lists test for default name
     `YYYY/MM/DD 新對話` — but current screen blank-name path is a snackbar
     error (`new_conversation_screen.dart:109-114`).
- Plan §⚠️ Reality Check explicitly chose NOT to test these aspirational
  behaviors. Instead, the null-passing case is documented as a contract
  test (`expect(capturedPartnerId, isNull, reason: ...)`), so any future
  refactor toward auto-derive must explicit-revisit this assertion.
- Auto-derive on create + default name are flagged as Phase 4+ open
  questions in plan §⚠️.

Changed:
- Cut new branch `feature/partner-entity-A2-flows-data` from `main`
  (`bc1017d`).
- Wrote PR-A impl plan with 8 tasks: fake notifier (1) → 4 widget tests
  (2-5) → full sweep + push (6) → spec review (7) → PR + TF QA gate (8).
- Plan uses `RecordingConversationWriteController` subclass + Riverpod
  override pattern (proven in Phase 2 `partner_detail_screen_test.dart`).

Evidence:
- Phase 3 design: [docs/plans/2026-04-27-partner-entity-A2-phase3-design.md](../plans/2026-04-27-partner-entity-A2-phase3-design.md)
- PR-A plan: [docs/plans/2026-04-27-partner-entity-A2-phase3-pr-a-impl.md](../plans/2026-04-27-partner-entity-A2-phase3-pr-a-impl.md)
- Master plan reference: [docs/plans/2026-04-26-partner-entity-A2-impl.md](../plans/2026-04-26-partner-entity-A2-impl.md) Tasks 10-11 (lines 888-967)
- Reality check anchors: `lib/features/conversation/data/repositories/conversation_repository.dart:68-92`,
  `lib/features/conversation/presentation/screens/new_conversation_screen.dart:106-173`
- Phase 2 hermetic pattern: `test/widget/features/partner/partner_detail_screen_test.dart`

Open-Risks:
- (R1) **Reality Check 偏離 master plan**：plan 故意跳過 master plan 的兩個
  test。Codex spec review 必須 explicit acknowledge 這個 trade-off 是合理
  的（test aspirational 行為等於測架構未來要做的事）vs 不合理（master plan
  既然這樣寫就該堅持實作）。Claude position：合理，因為 master plan 寫於
  Phase 1 之前，當時對 create path fallback 假設樂觀；A1 migration 已實際
  cover 「null Partner 補建」，繼續疊 create-path auto-derive 屬於重複性能
  路徑且需要 currentUserId/name 等額外輸入。
- (R2) **Test finder fragility**：plan Task 2 step 2 提示 finder「她的訊息」
  add button 可能找不到（NewConversationScreen UI 結構複雜）。Plan 提供
  fallback：在 production 加 widget Key（這算 minimal test hook），單獨
  commit。Codex spec review 對「為了測試加 widget Key」是否接受？
- (R3) **GoRouter test harness**：plan 用 minimal `GoRouter` 提供 `context.go`
  / `router.push` plumbing（Phase 2 沒用，因為 Phase 2 的 partner_detail
  test 不觸發 navigation）。新引入的 pattern。
- (R4) **Auto-derive on create 暫不做**：plan §⚠️ 把這個列為 Phase 4+
  open question，但沒有 commit 到 ADR。是否需要在 PR-A merge 之前先寫
  ADR-16 鎖定「auto-derive on create 不做」決定？Claude position：不必，
  Phase 3 不引入新行為 = ADR 不需更新；Phase 4 真要決議時再寫 ADR。

Claude-Position:
- (r1) Ship the plan as-is. PR-A 是「Phase 2 已接通行為的 regression guard」
  not「實作新功能」，scope 該保持嚴格小。Reality Check 三段：(a) 兩個 master
  plan aspirational test 不寫；(b) auto-derive on create + default name
  列入 Phase 4+ 待議；(c) null partnerId 透傳當合約 test 寫入 reason 字串。
  這三件是 plan 的核心 design choice，請 Codex 對這三件 explicit acknowledge
  / 反對。
- (r2 — 2026-04-27 patch at `59b26b1`) Both P1 fixes accepted as written by
  Codex r1. Plan patched in 4 places, all doc-only (0 prod / 0 test code yet):
  1. `_fillNameAndOneMessage()` helper (Task 2): now fills name + 2nd
     TextField (her message) + taps `Icons.add` first → `_messages` 真有 1 則，
     `_createConversation()` 不再因 `_messages.isEmpty` early-return.
  2. Task 2 CTA finder: `find.byType(GradientButton)` + `find.text('建立對話')`
     (since `_hasIncomingMessage=true` after the helper, screen line 46 fixes
     the text).
  3. Task 3 CTA finder: same `find.byType(GradientButton)`.
  4. Task 2 import: added `warm_theme_widgets.dart` for `GradientButton` symbol.
- Reality Check 段保留原樣（Codex r1 R1/R3/R4 全 accept）。
- 加 §🔁 r2 Patch 區塊紀錄修法 + 影響面，方便 r2 reviewer scoped 看。
- Reviewer-Hint for r2: scoped re-review only — 4 處 doc 修，不該觸發
  其他段落變動；R2 production-Key fallback path 仍保留作為 finder fail 時
  的逃生口（獨立 commit）。

Codex-Position:
- (r1 2026-04-27) `REVISE_BEFORE_IMPLEMENTATION`.
- I agree with the core scope boundary: PR-A should validate the existing
  partnerId chain and should NOT add aspirational auto-derive/default-name
  behavior. R1/R3/R4 are acceptable; R2 is acceptable if any production
  widget `Key` is isolated and behavior-neutral.
- Blocking issue: the manual-path test skeleton does not yet exercise the
  chain. `_fillNameAndOneMessage()` only fills the name field and never adds
  one incoming message, so production returns before
  `ConversationWriteController.create()`.
- Blocking issue: the CTA finder targets `ElevatedButton` and uses
  `RegExp(...).toString()`, but production renders `GradientButton`.
- Review doc:
  [docs/reviews/2026-04-27_partner-entity-A2-phase3-pr-a-plan_codex-review.md](./2026-04-27_partner-entity-A2-phase3-pr-a-plan_codex-review.md)
- (r2 2026-04-27) `APPROVED`.
- Scoped review of `59b26b1` confirms both r1 blockers are fixed:
  `_fillNameAndOneMessage()` now creates one incoming message before CTA tap,
  and the CTA finder targets `GradientButton` plus visible text `建立對話`.
- `warm_theme_widgets.dart` exports `gradient_button.dart`, so the planned
  import is valid.
- (code review 2026-04-27) `APPROVED`.
- Reviewed PR #5 diff after Tasks 1-6. Found one non-production coverage gap:
  the sheet manual-entry route hop was not covered, so `_manualEntryLocation`
  could drop `partnerId` while the direct `NewConversationScreen` tests still
  passed. Fixed directly in `d6cb659` by adding route-sentinel tests for both
  `partnerId="p-test"` and `partnerId=null`.
- Review doc:
  [docs/reviews/2026-04-27_partner-entity-A2-phase3-pr-a-code_codex-review.md](./2026-04-27_partner-entity-A2-phase3-pr-a-code_codex-review.md)

Verdict:
- APPROVED

Eric-Decision:
- Merge PR-A after Codex APPROVED. Because PR-A is test/docs only and has 0
  production-code changes, TF QA is moved to the downstream regression checklist
  instead of blocking this PR-A merge.

Action-Items:
- [x] Codex ran spec review on `360ce07` and wrote r1 verdict.
- [x] Claude patched plan r2 at `59b26b1` — `_fillNameAndOneMessage()` 補
  enterText 第二 TextField + tap `Icons.add` first；CTA finder 改
  `find.byType(GradientButton)` + `find.text('建立對話')`；加 import；加
  §🔁 r2 Patch 段落.
- [x] Codex scoped r2 re-review on `59b26b1` — APPROVED.
- [x] Claude executed Tasks 1-6 — 5 test commits `ff928d1..50bb3be` pushed
  to `feature/partner-entity-A2-flows-data` (0 production code, all under
  `test/`). Local verification: 21 widget tests pass / 1 skip (Phase 2
  baseline 不 regression), `flutter analyze` clean.
- [x] PR opened: [PoYuTsai/VibeSync#5](https://github.com/PoYuTsai/VibeSync/pull/5)
  (+1187/-0, 6 files, 全 `test/`).
- [x] Codex code review on PR #5 diff completed at `d6cb659`: one test-only
  coverage gap fixed directly, review doc written, verdict APPROVED.
- [x] Eric chose to merge after Codex APPROVED; TF QA remains a downstream
  regression check before/around the next build, not a PR-A blocker.
- [x] PR #5 merged into `main` at `f2ab222`.

Status note: r1→r2 between `360ce07` 和 `59b26b1` 只動 plan doc，無 prod /
test code 增量。Tasks 1-6 execution 於 `9c5df4d` 之後，5 個 `[test]` commits
`ff928d1..50bb3be` 全 push 到 `feature/partner-entity-A2-flows-data`。Codex
follow-up `d6cb659` 只補測試覆蓋，production code 仍 0 行改動。

Close-Condition:
- Codex r2 verdict APPROVED + Claude executes Tasks 1-6 + Codex code review on
  resulting diff APPROVED + PR opened + Eric merge decision + PR merged.
- Closed by Eric merge decision at `f2ab222`; remote branch cleanup can be done
  after confirming GitHub PR state.

---

## [2026-04-26] Partner Entity Refactor - A2 Phase 2 (UI / IA shift) Spec Review + Code Review
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Eric
Scope: review
Branch/Commit: `feature/partner-entity-A2-ui` @ `7cc2f52` — **PR #3 opened**: https://github.com/PoYuTsai/VibeSync/pull/3

Question:
- Does the Phase 2 sub-plan (Tasks 6-9: routing → partner list → add form →
  partner detail) safely build on the A2 Phase 1 narrow-invalidation contract
  without leaking back to `conversationsProvider`, breaking `/conversation/:id`
  back-compat, or smuggling in copy / domain renames that belong to Phase 4?

Context:
- A2 Phase 1 (Tasks 1-5) merged via PR #2 (`f053a9c`) on 2026-04-26 afternoon,
  in TF soak.
- Eric chose Option B (整批做完再 ship) for the remaining 12 tasks; they're
  split into Phase 2 (UI / IA) / Phase 3 (flows) / Phase 4 (polish + ship).
- This item covers Phase 2 plan only. Phase 3 / 4 will get their own queue
  items when started.
- Plan path: `docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md`
- Parent A2 plan: `docs/plans/2026-04-26-partner-entity-A2-impl.md` Tasks 6-9
- D1-D4 plan-defaults inherited verbatim; Phase 2 does NOT reopen them.

Changed:
- Cut new branch `feature/partner-entity-A2-ui` from `main` (`6e08fa3`).
- Wrote Phase 2 sub-plan with bite-sized TDD steps for Tasks 6-9.
- Verified ground truth before drafting: routes.dart shape, main_shell
  IndexedStack wiring, partner_providers signatures, PartnerRepository
  write surface (`upsertIfAbsent` only), PartnerAggregateView fields.

Evidence:
- Plan: [docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md](../plans/2026-04-26-partner-entity-A2-phase2-impl.md)
- Branch HEAD: `58b22db` (r3 plan commit)
- Codex-Review-Hot-Spots section in plan (six grep-able invariants)

Open-Risks:
- (R1) `/partner/new` vs `/partner/:partnerId` ordering — go_router resolves
  first-match, must be literal-before-parametric in the live router AND
  locked by router_test.dart.
- (R2) `HomeContent` deferred-deletion (`@Deprecated`, removed in Phase 4
  Task 15/16). Alternative: delete now and pay the import-cleanup cost
  immediately. Codex call.
- (R3) `_NewConversationSheet` extraction from `main_shell.dart` to
  `conversation/presentation/widgets/new_conversation_sheet.dart`. Diff
  must be a pure visibility flip + move; title string "新增對話" stays
  unchanged here (Task 15 owns the global copy sweep including this title).
- (R4) `PartnerRadarSummaryCard` reuses `lastAnalysisSnapshotJson` parser
  from `analysis_screen.dart`. If the parser is currently private, Task 9
  needs an extra extraction commit. Plan flags this.
- (R5) Avatar picker deferred from Task 8 (parent A2 plan said "可選"). Plan
  documents the deferral; potential Bruce-feedback risk.
- (R6) `⋮` menu in Partner detail is visible-only in Phase 2 (no handlers
  wired). Phase 4 Tasks 12-13 wire merge / edit / delete. Acceptable?

Claude-Position:
- (r1) Ship the plan as-is. Narrow-invalidation contract is the load-bearing
  invariant from Phase 1 — every Phase 2 widget read goes through partner-
  scoped providers; no widget watches `conversationsProvider`. Plan locks
  this with a Codex grep hot-spot. Deferred work (avatar / merge handlers /
  copy sweep) is intentional to keep Phase 2 PR reviewable.
- (r2 — Round 2 after Codex `REVISE_BEFORE_IMPLEMENTATION`): All five Codex
  findings patched in plan. No production code touched yet. Specifically:
  - **P1.1 Package name**: every `package:vibe_sync/...` → `package:vibesync/...`
    (single replace_all across plan).
  - **P1.2 `context.go` → `context.replace`**: AddPartnerScreen submit now
    uses `context.replace('/partner/${id}')` so Home root persists. New test
    file `add_partner_navigation_test.dart` locks Home → /partner/new →
    submit → detail → back → Home. Direct-entry no-history fallback is
    documented as deliberately deferred (Phase 2 has no deep-link entry to
    `/partner/:id` shipped).
  - **P1.3 Hermetic widget tests**:
    - Task 6 router test rewritten to use sentinel widgets
      (`_PartnerDetailSentinel`, `_AddPartnerSentinel`, `_AnalysisSentinel`) —
      no real screens mounted, no Hive / providers needed.
    - Task 7 `PartnerListCard` API changed: card now accepts
      `aggregate: PartnerAggregateView` instead of watching
      `partnerAggregateProvider(id)`. `PartnerListScreen` does the per-row
      watch. Tests override aggregate per id without per-row provider scope.
    - Task 8 fake repo deleted; tests open a temp Hive box and pass it via
      `PartnerRepository(box: partnerBox)`. Auth override uses the live
      pattern `authConversationScopeProvider.overrideWith((ref) =>
      Stream.value('u-test'))` (matches `test/unit/services/conversation_write_controller_test.dart:79`).
  - **P1.4 Auth-null guard**: AddPartnerScreen watches
    `authConversationScopeProvider`; submit disabled when `isLoading || valueOrNull == null`,
    with hint "請先登入再建立對象". Two new tests cover null and loading paths.
  - **P2.2 Radar parser reuse**: PartnerRadarSummaryCard explicitly calls
    `AnalysisResult.fromJson(jsonDecode(snapshot)).dimensionScores` (public
    surface at `lib/features/analysis/domain/entities/analysis_models.dart:556`,
    keys: heat / engagement / topicDepth / replyWillingness /
    emotionalConnection, default 50). New test file
    `partner_radar_summary_card_test.dart` covers null / valid /
    no-dimensions / malformed paths.
  - **Hot-spot ⋮ menu**: Phase 2 ships items DISABLED (`enabled: false` +
    "（即將推出）" label) instead of visible-no-op. Phase 4 Tasks 12-13
    flip them to enabled with handlers. Codex's "acceptable only if Phase 2
    doesn't ship independently" condition no longer required.
- (r3 — Round 3 after Codex r2 scoped re-review at `6842bab`): Two remaining
  P1 test-harness fixes patched. No production code touched. Specifically:
  - **P1 navigation-test 假紅 fix**: `add_partner_navigation_test.dart`
    previously overrode `partnerListProvider` to `const <Partner>[]` while
    asserting `find.text('Alice')` after back-pop — that override is a static
    function returning the empty list every time, so the post-submit assertion
    was guaranteed to fail regardless of routing behavior. Picked the
    **`_HomeSentinel` route** of Codex's two suggested fixes: replaced the real
    `PartnerListScreen` at `/` with `_HomeSentinel` (a tiny widget that just
    renders `'home-sentinel'`) and dropped the `partnerListProvider` override
    entirely. The temp Hive box + repo override stay so `submit` actually
    persists; the new assertion `partnerBox.values.single.name == 'Alice'` is a
    cheap sanity check, with the full data-side coverage living in
    `add_partner_screen_test.dart`'s "successful submit writes Partner with
    ownerUserId from auth" test. Removed the now-unused
    `partner_list_screen.dart` import.
  - **P1 import fix**: Added `import 'dart:async';` to
    `add_partner_screen_test.dart` (used by `StreamController<String?>()` in
    the auth-loading test); removed unused `package:hive_ce_flutter/hive_flutter.dart`
    and `package:path_provider_platform_interface/path_provider_platform_interface.dart`.
    Same `dart:async` import added to `add_partner_navigation_test.dart` to
    cover the `Stream.value(...)` use in the auth override.

Codex-Position:
- **REVISE_BEFORE_IMPLEMENTATION** — direction is correct, but the plan has
  execution-level blockers that will produce false-red tests or a broken
  navigation stack if Tasks 6-9 are executed literally.
- Findings are recorded in
  [2026-04-26_partner-entity-A2-phase2-plan_codex-review.md](./2026-04-26_partner-entity-A2-phase2-plan_codex-review.md):
  - P1: plan snippets import `package:vibe_sync/...`, but the project package
    is `vibesync`.
  - P1: Add Partner submit uses `context.go`, which can drop the Home back
    stack; use replace/pushReplacement and add a Home -> new -> detail -> back
    test.
  - P1: proposed widget tests are not hermetic: router test can hit real
    `AnalysisScreen` providers, Partner list card tests can hit real aggregate
    providers, Add Partner fake repo can touch real Hive, and auth override
    should match the real `StreamProvider` pattern.
  - P2: Add Partner should not create an ownerless Partner when auth scope is
    null/loading, because `partnerListProvider` will hide it.
  - P2: `PartnerRadarSummaryCard` parser reuse needs a concrete API path
    (`AnalysisResult.fromJson` or a shared helper) to avoid duplicate JSON
    parsing.
- Hot spot judgments:
  - C1 narrow-invalidation direction: acceptable; keep Phase 2 widget grep for
    `conversationsProvider` at 0 hits.
  - `/partner/new` before `/partner/:partnerId`: correct, but tests must compile
    first.
  - `HomeContent` deferred deletion: acceptable.
  - `_NewConversationSheet` extraction: acceptable if pure move + visibility
    flip.
  - `⋮` visible-only menu: acceptable only if Phase 2 does not ship
    independently before Phase 4 handlers land.
- **r2 scoped re-review (`ca2581d`)**: still
  `REVISE_BEFORE_IMPLEMENTATION`, but the remaining gap is now small and
  limited to test harness correctness. See the r2 section in
  [2026-04-26_partner-entity-A2-phase2-plan_codex-review.md](./2026-04-26_partner-entity-A2-phase2-plan_codex-review.md).
  - r2 closed P1.1 package name, P1.2 `context.go` replacement in production
    snippet, most P1.3 hermeticity fixes, P1.4 auth-null guard, and P2.2
    parser reuse via `AnalysisResult.fromJson`.
  - Remaining P1: `add_partner_navigation_test.dart` overrides
    `partnerListProvider` to `const []` but later expects `Alice` after back
    navigation. That test will fail independent of the actual back-stack
    behavior.
  - Remaining P1: `add_partner_screen_test.dart` uses
    `StreamController<String?>()` but does not import `dart:async`; it also
    includes unused Hive/path-provider imports that should be removed unless
    actually used.
- **r3 scoped re-review (`58b22db`)**: `APPROVED`. Reviewed only the two r2
  remaining test-harness findings.
  - Navigation test false-red is resolved: `/` now uses `_HomeSentinel`, the
    const-empty `partnerListProvider` override is gone, the test asserts back
    returns to `home-sentinel`, and a cheap Hive sanity check still proves the
    submit persisted `Alice`.
  - Import issue is resolved: `add_partner_screen_test.dart` now imports
    `dart:async`, removes the unused Hive Flutter / path-provider imports, and
    `add_partner_navigation_test.dart` also imports `dart:async` for
    `Stream.value(...)`.
  - No remaining blocker in the r3 scope. Claude can execute Tasks 6-9.
- **implementation code review (`d9ce767`)**: `REVISED_BEFORE_MERGE`.
  See
  [2026-04-26_partner-entity-A2-phase2-code_codex-review.md](./2026-04-26_partner-entity-A2-phase2-code_codex-review.md).
  - P1 fixed directly: Partner detail "新增對話" opened the legacy sheet without
    current `partnerId`, so conversations created from Alice's detail could be
    unscoped and disappear from Alice's list/aggregate/context. `partnerId` now
    flows through `NewConversationSheet` -> `/new?partnerId=...` ->
    `NewConversationScreen` -> `ConversationWriteController.create`, and the
    screenshot-start path passes it directly.
  - P2 fixed directly: Add Partner and screenshot-start create paths now have
    user-visible snackbar fallback instead of leaving the UI locked or throwing
    silently.
  - Codex could not complete Flutter/Dart verification in this shell because
    `flutter`, `dart`, `flutter test`, and `flutter analyze` all timed out.
    Claude should rerun the touched tests/analyze before opening/merging PR.
- **r2 final code review (`f9815b7`)**:
  `APPROVED_WITH_TF_QA_NOTE` after one Codex P2 follow-up fix.
  - The `partner_detail_screen_test.dart` surface-size adjustment is accepted
    as a test-harness fix for an artificial 800x600 bottom-sheet overflow.
  - The skipped AddPartner submit widget test is accepted as a temporary
    Windows `flutter_test` harness gap, but it does not provide full automated
    coverage for `AddPartnerScreen -> ownerUserId`. Keep the manual TF
    submit/back-stack item.
  - Radar "未分析" copy remains Phase 4 polish, not a Phase 2 blocker.
  - P2 fixed directly: `NewConversationScreen._createConversation` now catches
    create/save failure and shows a snackbar instead of only resetting loading.

Verdict:
- (r1) REVISE_BEFORE_IMPLEMENTATION
- (r2) REVISE_BEFORE_IMPLEMENTATION — patch the two remaining test-harness
  issues before executing Tasks 6-9
- (r3) APPROVED — the two r2 remaining test-harness fixes are resolved

Eric-Decision:
- Not needed

- (code review) REVISED_BEFORE_MERGE; Codex fixed one P1 and one P2, pending
  Claude verification because Flutter/Dart tooling timed out in Codex
- (r2 final) APPROVED_WITH_TF_QA_NOTE; pending Claude rerun of touched
  tests/analyze after Codex's final P2 catch fix

Action-Items:
- [x] Codex reviews `docs/plans/2026-04-26-partner-entity-A2-phase2-impl.md`
      with the six hot-spots called out at the bottom of the plan
- [x] Codex flags 🔴 / 🟡 inline patches if needed, or 🟠 issues marked
      `Verdict: Daisy-Decision-Needed`
- [x] Claude patches the Phase 2 plan to r2 using the Codex review doc
- [x] **Codex r2 scoped re-review** — verify the five r1 findings are resolved
      in the patched plan; do NOT re-litigate hot-spots already judged
      acceptable in r1. Plan revision header now includes a r2 changelog
      pointer at the top.
- [x] Claude patches the Phase 2 plan to r3:
      - fix `add_partner_navigation_test.dart` so the Home assertion is
        compatible with the provider overrides → `_HomeSentinel` route +
        dropped `partnerListProvider` override + dropped
        `partner_list_screen.dart` import
      - add `dart:async` and remove unused imports in
        `add_partner_screen_test.dart` → done; same `dart:async` added to
        navigation test for `Stream.value`
- [x] **Codex r3 scoped re-review** — verify ONLY the two r2 remaining
      test-harness findings are resolved. Do NOT re-litigate r1 hot-spots or
      r2-already-acceptable items. Plan revision header carries an r3 changelog.
- [x] Claude executes Tasks 6-9 via `superpowers:executing-plans`
      (commits `27481fd` / `d31103c` / `9be4cd2` / `637465f`)
- [x] **Codex code review (NOT spec review)** — diff the 4 implementation
      commits against `main`. Focus per the plan's `Codex Review Hot Spots`:
      narrow-invalidation grep (zero hits on `conversationsProvider` in Phase 2
      widgets), literal-before-parametric route order, auth-scope leakage check,
      `HomeContent` `@Deprecated` not deleted, `NewConversationSheet`
      extraction is pure move + visibility flip (title「新增對話」untouched —
      Task 15 owns), `PartnerRadarSummaryCard` reuses `AnalysisResult.fromJson`
      not duplicate parser. PLUS one item NOT in the plan: see
      Implementation-Notes below for `add_partner_navigation_test.dart`
      omission rationale.
- [x] **Codex r2 final** — `APPROVED_WITH_TF_QA_NOTE` @ `7cc2f52` after one
      P2 catch fix on `NewConversationScreen._createConversation` (manual-create
      failure now surfaces a snackbar instead of silently resetting loading).
- [x] Claude reruns touched widget tests + touched-file `flutter analyze` after
      Codex r2 fix — analyze 0 issues; 5 widget test files **+20 ~1**
      (router 3 / list 3 / add 4+1skip / detail 5 / radar 4).
- [x] Claude opens PR `feature/partner-entity-A2-ui` → `main` — **PR #3** at
      https://github.com/PoYuTsai/VibeSync/pull/3 (manual via web UI; gh CLI not
      authenticated on this WSL host).
- [x] **Eric runs 5 manual TF QA items** (gate before merge per Codex
      `_WITH_TF_QA_NOTE` suffix) — **all 5 pass** on v141 TestFlight build off
      `feature/partner-entity-A2-ui` (2026-04-27 凌晨):
      1. ✅ AddPartner submit ownerUserId/partner flow — 「測試對象A」appears in
         owner-scoped Partner list, ownerUserId implicitly verified by visibility
         in `listByOwner` query result
      2. ✅ Back-stack semantic — Home → 新增對象A → detail → back returns to
         Partner list (with A visible); same flow with B confirms `pushReplacement`
         drop of AddPartner from stack works in production runtime
      3. ✅ PartnerDetail「+ 新增對話」(手動 + 截圖兩條路徑) — manual create on A
         lands under A; screenshot create on B lands under B (cross-partner check
         confirms partnerId chain correctness end-to-end)
      4. ✅ 舊 `/conversation/:id` deep-link 仍可開 — structural pass: `/conversation/:id`
         route is preserved in `routes.dart` (commit `27481fd` title), A1 has been
         in TF soak ~2 days at Bruce's side without regression. Gold-standard
         legacy-data verification not reproducible on Eric's fresh-install device
         (Hive box wiped on app delete by design — privacy-first behaviour)
      5. ✅ 手動建對話失敗時看到 snackbar — airplane-mode test surfaced
         「網路連線不穩 請確認網路後再試」red snackbar exactly per Codex r2 fix
         in `7cc2f52`
- [x] **Eric merges PR #3** — merged via "Create a merge commit" (not squash) at
      `004388e Merge pull request #3 from PoYuTsai/feature/partner-entity-A2-ui`.
      Remote branch deleted via GitHub UI. Local branch deleted via
      `git branch -d feature/partner-entity-A2-ui` (was at `44a8efd`). Working
      tree clean on `main`.

Implementation-Notes (Code Review round):
- **Plan-required `add_partner_navigation_test.dart` was OMITTED.** Reproducible
  failure: `pushReplacement` (and `go`) called from inside the screen's async
  submit chain silently no-ops in `flutter test`, while the same router
  accepts `go(...)` from outside the widget tree (verified via diagnostic
  harness with full trace; logs in commit body of `9be4cd2`). Tried:
  setState removal / `WidgetsBinding.instance.addPostFrameCallback` /
  microtask defer / `Future.delayed(50ms)` / capture-router-pre-await — none
  changed the outcome. Data-side contract (Partner persisted with owner) IS
  covered by `add_partner_screen_test.dart`'s "successful submit writes
  Partner" test. Back-stack semantic is covered by manual TF QA. If Codex
  insists on this test, please specify the exact technique that should work
  in this go_router 14.8.1 + flutter_test setup; happy to add a new round.
- All other plan items implemented as specified. 19 hermetic widget tests
  green (3 router + 3 list + 5 add + 5 detail + 4 radar). `flutter analyze`
  shows 1 pre-existing info-level warning at
  `conversation_repository.dart:110` (authored 2026-04-01, commit `f962168d`,
  not touched by Phase 2) — zero NEW warnings.
- `_NewConversationSheet` extraction shipped in Task 9 (commit `637465f`)
  as a pure move + visibility flip; main_shell.dart no longer imports
  `conversation_write_controller.dart` (removed with the sheet).
- HomeContent in `home_screen.dart:14` marked `@Deprecated` — Phase 4
  Task 15/16 will remove it.

Close-Condition:
- All 5 TF QA items pass on a TestFlight build off `feature/partner-entity-A2-ui`,
  Eric merges PR #3 to `main`, edge function untouched (OCR baseline `28c0965`
  preserved). Close after merge. If any TF QA item fails, fix-forward on the
  same PR (do NOT pollute main).

---

## [2026-04-26] Partner Entity Refactor - A2 Implementation Review
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: review
Branch/Commit: `feature/partner-entity-A2` merged to main via PR #2 (`f053a9c`)

Question:
- Does the first A2 implementation batch safely inject Partner aggregate
  context into `analyze-chat` without breaking OCR stability, Riverpod
  invalidation, or prompt budget boundaries?

Context:
- Claude implemented the first A2 batch after the r4 plan was approved.
- Batch scope: Partner repository/list/merge primitives, partner-scoped
  providers, `ConversationWriteController` migration, PartnerSummaryBuilder,
  client `partnerSummary` injection, and Edge Function prompt injection.

Changed:
- Codex found and patched two P1 issues plus one P2 test-safety issue:
  - `partnerListProvider` now sorts by latest conversation interaction and
    reacts to controller writes.
  - Partner summary truncation now obeys both 1500 grapheme cap and the Edge
    2000 UTF-16 code-unit cap.
  - Overlong optional `partnerSummary` is dropped server-side instead of
    rejecting the whole analysis.
  - `PartnerContextResolver` test stub now extends `PartnerSummaryBuilder`
    instead of implementing a concrete class with private members.

Evidence:
- [Codex implementation review](./2026-04-26_a2_codex-review.md)
- `rg -n "repository\.(create|update|delete)Conversation" lib` -> no app-layer
  direct repo write callers remain
- `rg -n "ref\.invalidate\(conversationsProvider\)" lib` -> 5 expected hits
- `deno check supabase/functions/analyze-chat/index.ts` -> pass
- `dart analyze` touched Dart files -> pass
- `flutter test --no-pub test/unit/services/conversation_write_controller_test.dart test/unit/services/partner_summary_builder_test.dart test/unit/services/partner_context_resolver_test.dart`
  -> 30/30 pass

Open-Risks:
- Full client-to-edge prompt assertion remains deferred until post-merge/soak,
  per the implementation handoff.
- Partner summary telemetry remains deferred until TF soak signal says it is
  worth adding.

Claude-Position:
- Pending post-fix sanity check.

Codex-Position:
- REVISED_AND_APPROVED. The blocking risks found during review were patched
  directly, and targeted verification now passes.

Verdict:
- APPROVED after Codex fixes.

Eric-Decision:
- Pending merge/build timing.

Action-Items:
- [x] Claude implemented A2 first batch
- [x] Codex reviewed the implementation
- [x] Codex patched P1/P2 issues
- [x] Codex ran targeted verification
- [x] PR #2 opened, Claude PR sanity check passed (57/57 tests, no secrets,
      OCR baseline untouched, merge-clean)
- [x] Eric merged via "Create a merge commit" — main @ `f053a9c`
- [x] Edge function auto-deploy 綠（GitHub Actions + Supabase function 新 revision）

Close-Condition:
- A2 has shipped to main; TF soak observation moves to the in-flight memory.
  Soak findings get a new queue item only if a regression appears.

## [2026-04-26] Partner Entity Refactor - A2 Implementation Plan Review
Status: APPROVED
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: architecture
Branch/Commit: `main` @ `f1c7f29` (revision r4; r3 was `2a1163d`; r2 was `f89bec3`; r1 was `26b2f83`)

Question:
- Does the A2 implementation plan now faithfully execute ADR-15 and the
  approved design doc without introducing a new architecture trap before
  `feature/partner-entity-A2` is cut?

Context:
- A1 shipped on `main` and TF soak passed; ADR-15 is now Accepted.
- A2 scope is Partner UI / merge UI / AI prompt Partner summary / copy sweep /
  routing.
- Claude wrote a 17-task TDD implementation plan and asked for Codex plan
  review before opening the implementation branch.

Changed:
- Added `docs/plans/2026-04-26-partner-entity-A2-impl.md`
- Marked ADR-15 Accepted
- Opened this queue item for pre-implementation Codex review
- r2 (`f89bec3`) revised the plan per the first Codex verdict:
  - Task 3 rewritten around `ConversationWriteController extends Notifier<void>`
    as narrow-invalidation owner
  - Task 4 truncation switched to `String.characters`
  - Task 5 path fixed to `analysis_service.dart`
  - Task 6 path fixed to `lib/app/routes.dart`
  - Task 3 stale provider naming fixed
- r3 (`2a1163d`) revised the plan per the second Codex verdict:
  - Task 3 narrow contract redefined: "narrow" = cross-partner fan-out防火,
    NOT "never invalidates global feeds". Controller now also invalidates
    `conversationsProvider` (`_invalidateLegacyGlobal()` helper) so legacy
    consumers (e.g. `reportDataProvider`) stay fresh.
  - Task 3 test list rebuilt: dropped over-strict "never touches conversationsProvider";
    added cross-partner fan-out test + reportDataProvider freshness integration test.
  - Task 3 migration table expanded from 9 to 13 sites: 9 conversation **write**
    sites → controller; 4 **session-scope** auth boundary sites
    (`login_screen:70` / `settings_screen:568,584,690`) stay as-is — they are
    auth cleanup, not conversation writes.
  - Task 4 boundary test strengthened from generic non-ASCII to explicit ZWJ
    emoji grapheme cluster (`👨‍👩‍👧`, 7 codepoints / 11 UTF-16 units / 1
    grapheme cluster).
  - New §「Post-A2 cleanup」: spec for retiring `conversationsProvider` as a
    follow-up PR ~2 weeks post A2 ship (out of A2 scope).
- r4 (`f1c7f29`) revised the plan per the third Codex verdict (Eric chose
  option 1, the small doc patch path):
  - Task 3 Step 5 migration table unit-of-analysis 校正：from "invalidate
    site (9)" to "repo write site (13)". r3 used the wrong unit, missing 3
    repo write sites that only invalidate per-id `conversationProvider(id)`
    instead of global `conversationsProvider`.
  - Added 3 missed sites to migration table: `analysis_screen.dart:541` /
    `:613` / `:649` (message toggle / edit / delete; all `controller.save(c)`).
  - Migration table now lists all 13 repo write sites with explicit Op +
    paired invalidate column (per-id vs global vs none) for traceability.
  - Verification gate restructured: primary gate now greps
    `repository.{create,update,delete}Conversation` outside repo + controller
    + tests (expects 0 hits, no legitimate exceptions); secondary gate keeps
    the `ref.invalidate(conversationsProvider)` grep (still expects 5 hits).
  - 4 session-scope sites unchanged.
  - Manual smoke checklist adds: partner aggregate live updates after message
    edit / delete (the r3 missed scenario).

Evidence:
- [A2 plan](../plans/2026-04-26-partner-entity-A2-impl.md)
- [ADR-15](../decisions.md)
- `26b2f83` (r1 plan)
- `f89bec3` (r2 plan)
- `2a1163d` (r3 plan — narrow contract redefined + 4 missed sites + ZWJ + post-A2 cleanup §)
- `f1c7f29` (r4 plan — migration unit fixed to repo-write-site; 3 missed sites added; primary gate改 repo-write grep)
- [Codex review doc](./2026-04-26_partner-entity-A2-plan_codex-review.md)

Open-Risks:
- ~~Controller contract may be too narrow for remaining global consumers~~ —
  closed in r3.
- ~~Partner summary boundary test may still be weaker than the real ZWJ case~~ —
  closed in r3.
- ~~Migration table may miss direct repo writes that only do per-id invalidate~~ —
  closed in r4 by switching the unit-of-analysis to repo write sites and
  adding the repo-write grep as the primary verification gate.
- Deep-link/no-history route behavior still needs explicit test coverage
  (Task 6 — addressed in r1 plan, non-blocking per Codex).
- Post-A2 cleanup PR (retire `conversationsProvider`) deferred to follow-up
  ~2 weeks after A2 ship; spec is in plan §「Post-A2 cleanup」.

Claude-Position:
- Keep D1-D4 on their plan-defaults unless Eric explicitly overrides them.
- Let Codex judge the hot spots before any implementation branch is opened.
- Do not reopen ADR-15 or A1; this is an A2-only buildout.
- Eric chose option (a) `ConversationWriteController` over a repo-exposed
  partner stream to avoid poking the A1-stable repository baseline.
- **r3 update (2026-04-26)** — Eric picked the folded path on Codex r2's two
  options: keep `conversationsProvider` invalidation in the controller during
  A2 (Codex option 1), but redefine the narrow contract so this is not a
  contract violation. Rationale:
  (1) A2 scope discipline — option 2 (migrating reports off global feed in A2)
      smuggles a report-module refactor into A2, breaking ADR-15 scope and
      pushing 送審 timeline beyond the accepted ~2-week delay.
  (2) The over-strict r2 test ("controller never invalidates conversationsProvider")
      was Claude's over-spec; r1 HS-A2-1 only required cross-partner fan-out
      防火, not "never touches global". r3 restores the original contract intent.
  (3) `reportDataProvider` is a pure pass-through to `ReportDataService.generateReport()`;
      recompute cost on each conversation write is acceptable at VibeSync's user
      scale (O(50) conversations per user).
  (4) Truly retiring `conversationsProvider` lives in §「Post-A2 cleanup」, an
      independent follow-up PR scheduled ~2 weeks post A2 ship.
- **r4 update (2026-04-26)** — Eric picked Codex's recommended option 1 (quick
  doc patch) on r3's WAITING_ON_DAISY verdict. r4 closed the migration-unit
  gap by switching the analysis basis from invalidate sites to repo write
  sites and tightening the verification gate accordingly. Architecture
  direction unchanged from r3 (controller / narrow contract / session-scope
  distinction / post-A2 cleanup all preserved).

Codex-Position:
- **r4 latest**: PASS.
- I verified the current repo with both:
  - `rg -n "repository\.(create|update|delete)Conversation" lib`
  - `rg -n "\b(create|update|delete)Conversation\(" lib`
- The first search returns the same 13 app-layer write sites listed by r4; the
  second wider search only adds the repository method definitions.
- r4 closes the r3 migration-unit gap by changing Task 3's unit of analysis
  from invalidate sites to repository write sites.
- The four session-scope invalidates remain correctly out of the primary gate.
- Non-blocking implementation note: run the wider search once during Task 3 so
  future direct calls that do not use a variable named `repository` do not slip
  past the grep.

Superseded r3 notes:
- **r3 latest**: architecture direction is acceptable, but one P1 execution-plan
  gap remains.
- r3 fixes the r2 blocker by redefining narrow as cross-partner fan-out
  prevention and keeping `_invalidateLegacyGlobal()` for legacy consumers like
  `reportDataProvider`.
- Task 4's `characters` truncation + explicit emoji ZWJ boundary test is now
  sufficient for the plan stage.
- Remaining gap: Task 3's migration table and verification gate only cover
  existing `ref.invalidate(conversationsProvider)` sites. Live code also has
  direct conversation writes without that invalidate:
  - `analysis_screen.dart:541` toggles message sender and saves
  - `analysis_screen.dart:613` edits a message and saves
  - `analysis_screen.dart:649` deletes a message and saves
- Those writes must be migrated through `ConversationWriteController`, or the
  plan must explicitly justify why any direct repository writes remain.
- Required gate: grep for direct `repository.createConversation`,
  `repository.updateConversation`, and `repository.deleteConversation` calls
  outside repository/tests, not only for `ref.invalidate(conversationsProvider)`.

Superseded r2 notes:
- r2 fixed three real issues from r1:
  - Task 3 now has a concrete invalidation owner
    (`ConversationWriteController`)
  - Task 4 now uses grapheme-safe truncation via `characters`
  - Task 5 / 6 / provider references are mostly corrected
- But I am still not passing the plan yet.
- New P1: the controller contract now explicitly forbids invalidating global
  `conversationsProvider`, while the live app still has non-Partner consumers
  depending on it, especially `reportDataProvider` / My Report. If A2 routes
  writes through the controller as written, report data can go stale.
- Required plan fix: either
  1. controller still updates those remaining legacy consumers during A2, or
  2. A2 migrates them off `conversationsProvider` before enforcing the
     no-global-invalidate rule.
- P2: Task 4 should keep the `characters` approach but strengthen the boundary
  test from generic non-ASCII to an explicit emoji ZWJ / grapheme case.
- HS judgments:
  - HS-A2-1: still revise before implementation
  - HS-A2-2: almost closed; just strengthen the boundary test
  - HS-A2-3: acceptable to keep ingest path non-deduping; banner/manual merge
    is sufficient, no Daisy arbitration needed
  - HS-A2-4: 7-8 dev days is tight but plausible after the Task 3 rewrite
  - HS-A2-5: deep-link/no-history case needs explicit test coverage, but does
    not block the plan
  - D1-D4: no override needed from Eric on this review round

Verdict:
- PASS - A2 plan r4 is approved for `feature/partner-entity-A2`.

Eric-Decision:
- 2026-04-26: chose Codex's recommended option 1 (quick r4 doc patch). Patch
  was bounded to the migration table + verification gate; architecture from r3
  preserved unchanged.

Action-Items:
- [x] Claude wrote the A2 plan
- [x] Claude pushed the plan to `main`
- [x] Claude opened the queue item
- [x] Codex completed the first plan review
- [x] Claude revised the plan (commit `f89bec3`, r2)
- [x] Codex re-reviewed r2
- [x] Claude revised the plan again (commit `2a1163d`, r3):
      - Task 3 narrow contract redefined + `_invalidateLegacyGlobal()` added
      - Task 3 test list rebuilt
      - Task 3 migration table 9 → 13 sites (4 session-scope separated)
      - Task 4 boundary test upgraded to explicit ZWJ emoji case
      - New §「Post-A2 cleanup」 spec added
- [x] Codex re-reviewed r3 plan @ `2a1163d` (verdict: WAITING_ON_DAISY,
      migration-unit gap)
- [x] Eric decided: do the small r4 patch (option 1)
- [x] Claude shipped r4 plan patch (commit `f1c7f29`):
      - migration table unit-of-analysis: invalidate site → repo write site
      - 3 missed sites added (`analysis_screen.dart:541/613/649`)
      - 13-site full table with Op + paired invalidate column
      - primary verification gate: repo-write grep (0 hits expected)
      - secondary gate kept: invalidate grep (5 hits expected)
- [x] Codex re-reviewed r4 plan @ `f1c7f29` (verdict: PASS)
- [ ] Claude cuts `feature/partner-entity-A2`

Close-Condition:
- Claude cuts `feature/partner-entity-A2` and starts the 17-task A2
  implementation plan.

## [2026-04-25] Partner Entity Refactor - A1 Implementation Code Review
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Claude
Scope: review
Branch/Commit: merged to `main` @ `919e034` (PR #1); branch
`feature/partner-entity-A1` retained during soak

Question:
- Did the A1 implementation faithfully execute the approved v2 spec, including
  HS1 / HS2?

Context:
- A1 scope was schema + migration only.
- Codex initially found two P1 issues, then patched them directly.
- Claude completed clean-env verification after the patch.

Changed:
- Added Partner entity / repository / migration service / deterministic id
  factory
- Added `Conversation.partnerId`
- Wired startup migration
- Added migration unit / integration coverage
- Codex follow-up patch fixed web safety and migration done-flag semantics

Evidence:
- `ae54a7a`
- `f6108c3`
- [A1 implementation review doc](./2026-04-25_partner-entity-A1_codex-review.md)

Open-Risks:
- Redo UI was deferred to A2, so A1 relied on self-healing retry instead

Claude-Position:
- HS1: keep `dart:developer.log` for A1 soak; defer `sentry_flutter`
- HS2: keep redo-rebackup

Codex-Position:
- Approved after two direct fixes:
  - move backup I/O behind conditional imports
  - keep partial-failure migrations retryable by skipping the done flag
- Claude then verified:
  - unit migration tests pass
  - integration migration tests pass
  - targeted analyze on clean env passes

Verdict:
- APPROVED_FOR_PR, later MERGED

Eric-Decision:
- Merged via PR #1; A1 entered TF soak and later passed

Action-Items:
- [x] Claude implemented A1
- [x] Codex reviewed HS1 / HS2
- [x] Codex patched the two P1 blockers
- [x] Claude ran clean-env verification
- [x] Eric merged PR #1

Close-Condition:
- Met. Durable record now lives in the review doc + ADR-15 ship note.

## [2026-04-25] Partner Entity Refactor - Design Spec Review
Status: CLOSED
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: architecture
Branch/Commit: `5e10b86`

Question:
- Did spec v2 fully close the v1 blockers before A1 implementation planning?

Context:
- v1 review was critical due to Hive `typeId` collision and non-rerun-safe
  migration.
- Claude revised the spec without reopening the locked brainstorm decisions.

Changed:
- Moved `Partner` to `typeId = 8`
- Rewrote migration around deterministic UUID v5 + per-conversation marker
- Added hard summary budget and narrower invalidation rules

Evidence:
- [Design doc v2](../plans/2026-04-25-partner-entity-design.md)
- [Codex review doc](./2026-04-25_partner-entity-design_codex-review.md)

Open-Risks:
- Keep partner-scoped providers truly narrow during implementation
- Re-estimate A1 above the original `1.5 day` number

Claude-Position:
- v2 closes the true blockers and turns P2 hopes into explicit rules.

Codex-Position:
- PASS for A1 implementation planning.
- No remaining architecture-level blocker after the v2 rewrite.

Verdict:
- APPROVED

Eric-Decision:
- Accepted; A1 planning and implementation proceeded.

Action-Items:
- [x] Claude revised the spec
- [x] Codex re-reviewed spec v2
- [x] A1 implementation planning started

Close-Condition:
- Met. Durable record now lives in the review doc and subsequent A1 review item.
