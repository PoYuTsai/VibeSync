# Codex Review: Spec 4 Phase 1 Coach Action Card Plan

> Date: 2026-05-01  
> Reviewed plan: `docs/plans/2026-05-01-spec4-phase1-coach-action-card-impl.md`  
> Plan commit after amendments: `e8d525d`  
> Verdict: `APPROVED-WITH-AMENDMENTS`, amendments accepted by Claude / CC  
> Current gate: cleared 2026-05-01. Eric dogfood-smoked Spec 3 as acceptable and explicitly asked CC to proceed with Spec 4 Phase 1.

## Summary

Codex reviewed the Spec 4 Phase 1 implementation plan before production code was written.

The plan direction is approved:

- Replace `ScoreActionHint` usage with `CoachActionCard`.
- Add deterministic app-side `CoachActionPolicy`.
- Use 9 locked actionTypes.
- Add exact-article Learning deep links.
- Keep backend, OCR, prompt, schema, and Hive untouched.

## Amendments Accepted

1. Learning fallback must not use `context.push('/')`.
   - Reason: `/` opens `MainShell` on home tab, not Learning.
   - Resolution: exact article link only. If no article maps, hide the CTA.

2. Do not delete `ScoreActionHint` in Phase 1.
   - Reason: keep rollback safety while the new card soaks in TF.
   - Resolution: replace usage only. Cleanup deferred until Phase 1 TF smoke is green.

3. Remove `shitTest` wording from Spec 4 surface.
   - Reason: product positioning avoids PUA / red-pill terminology.
   - Resolution: new code uses `challengeSignal`.

4. Fix test paths to mirror feature structure.
   - Resolution:
     - `test/unit/features/analysis/domain/coach/coach_action_policy_test.dart`
     - `test/unit/features/analysis/domain/coach/learning_link_resolver_test.dart`
     - `test/widget/shared/coach_action_card_test.dart`

5. Resolve the TF gate contradiction.
   - Reason: current workflow commits directly to `main`, so "write now, hold merge" is not true unless a feature branch is used.
   - Resolution: no production code until Spec 3 TF smoke is acceptable and Eric gives go signal. Gate cleared on 2026-05-01.

6. Card field count corrected from 5 to 6.
   - `actionLabel / whyNow / task / suggestedLine / avoid / learningLink`

7. Plan open questions locked.
   - `extendTopicStoryFrame` stays one enum value for Phase 1.
   - Policy lives under `analysis/domain/coach/`.
   - `learningLink` can be null.
   - No emoji in card header.
   - TF gate remains binding.

## Current Status

Implementation may start.

Next allowed step:

```text
Eric dogfood smoke accepted Spec 3 as OK
-> Eric asked CC to proceed
-> CC executes the locked implementation plan
-> Codex reviews code diff
```

## Related Product Note

Spec 5 product scope was expanded on 2026-05-01 from "Proactive Coach Loop" to "Relationship Rhythm & Mindset Coach". That discussion is recorded in:

```text
docs/plans/2026-04-30-memory-coach-spec5-proactive-coach-loop-draft.md
docs/plans/2026-04-30-vibesync-memory-coach-roadmap.md
```
