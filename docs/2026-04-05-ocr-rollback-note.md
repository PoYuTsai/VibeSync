# 2026-04-05 OCR Rollback Note

## Current Stable Baseline

- Current OCR-stable baseline: `28c0965`
- Meaning:
  - `b46f619` rolled the repository back to the editable `043ac23` baseline
  - `28c0965` added back the missing `AppColors.glassTextSecondary` constant so the app can compile again
- If OCR behavior is being discussed, use `28c0965` as the source of truth, not the intermediate hotfix commits above it.

## What Was Rolled Back

The following later changes were part of the reverted range and should **not** be assumed to be active on current `main`:

- OCR request / prompt / parser / cache / UI fail-open experiments after `043ac23`
- Security hardening commits from this debugging batch
- CI/workflow tightening from this debugging batch
- New security docs / alerting / retention automation added during this debugging batch

In other words:

- current `main` is back on the older editable baseline
- only the compile fix from `28c0965` is intentionally kept on top

## Security Status After Rollback

Do **not** assume the previously discussed security improvements are live right now.

The rolled-back set includes commits such as:

- `555305c`
- `e82162b`
- `a164a22`
- `9400d7e`
- `c002de0`

Those changes were useful exploration, but they are not the current production baseline anymore after the full rollback.

If we want any of them back, they should be re-applied one by one on top of `28c0965`, with isolated verification each time.

## Working Rule Going Forward

- Do not batch OCR changes together.
- Do not run multi-agent parallel optimization on the OCR core path.
- Change one variable at a time.
- Verify with the same real screenshot set before moving to the next change.
- If OCR regresses again, prefer immediate rollback over stacked patching.
