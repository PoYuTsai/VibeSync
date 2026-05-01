# Codex Code Review — Spec 4 Phase 1 Cleanup

**Date:** 2026-05-02
**Reviewer:** Codex
**Scope:** cleanup commit `0d7ff06`
**Verdict:** APPROVED-WITH-AMENDMENTS

## Summary

Cleanup commit `0d7ff06` is correct in code scope: it removes the legacy `ScoreActionHint` widget, removes its isolated widget tests, and drops the stale policy comment that referenced the now-deleted legacy widget. Production still routes through `CoachActionCard`, and the policy rules were not changed by the cleanup commit.

I found one process/documentation drift after the cleanup: the current snapshot and ADR still said the legacy widget was retained pending TF smoke. I patched those current-state docs so the next Claude/Codex session does not reopen an already-completed cleanup loop.

## Findings Patched

### P2 — Current docs still described cleanup as pending

**Severity:** Documentation / handoff risk
**Files:** `docs/snapshot.md`, `docs/decisions.md`

After `ScoreActionHint` was deleted, `docs/snapshot.md` and ADR #16 still said the rollback widget and its tests were retained pending TF smoke. That stale state is exactly the kind of handoff drift that sends future sessions down the wrong path.

**Patch:** Updated snapshot + ADR #16 to record:

- TF smoke passed with Eric's dogfood feedback.
- `ScoreActionHint` cleanup completed at `0d7ff06`.
- Production path now only uses `CoachActionCard`.
- Full-suite cleanup sweep remained at baseline (`+638 ~1 -76`).
- Phase 1.5 candidates are softInvite/pausePursuit articles or a real Learning tab route.

## Checked And Accepted

- `lib/shared/widgets/score_action_hint.dart` deleted.
- `test/widget/widgets/score_action_hint_test.dart` deleted.
- `coach_action_policy.dart` cleanup only removed the stale "mirror legacy widget" comment.
- `git grep "ScoreActionHint|score_action_hint" -- lib test` returns no matches.
- `CoachActionCard` remains wired in `analysis_screen.dart`.
- Meeting-language and low-heat suppression contracts remain covered by `coach_action_policy_test.dart`.

## Verification

CC reported before review:

```bash
flutter analyze
# No issues found

flutter test
# +638 ~1 -76; baseline -76 unchanged
```

Codex additionally verified:

```bash
git diff 0d7ff06^..0d7ff06 --stat -- lib test
# 3 files changed, 288 deletions

git grep -n "ScoreActionHint\|score_action_hint" -- lib test
# no matches
```

## Next Step

Spec 4 Phase 1 is now closed. Move forward to Phase 1.5 decision-making only if we want better learning coverage: add exact articles for `softInvite` / `pausePursuit`, or implement a real Learning tab route for category-level deep links.
