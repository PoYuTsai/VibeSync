# Spec 4 Phase 1 — Coach Action Card + Learning Deep Link Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Status:** ✅ SHIPPED 2026-05-02 at HEAD `2ca0257` (Tasks 0-15 all green; Task 16 doc closeout in this commit; Final Codex code review pending). Manual web smoke (heat 20/50/90 + flagged partner screenshots) is Eric's TF-side responsibility.
> **Source:** `VibeSync_Spec4_Coach_Action_Loop_Bruce.docx` + verbal alignment 2026-05-01.
> **Supersedes (Phase 1 only):** `2026-04-30-memory-coach-spec4-coach-action-loop-draft.md`. Draft was 7 actionTypes, this plan is 9 + adds Spec 3 gating that didn't exist when the draft was written.
> **Codex amendments applied:** see §10 for the diff log.

**Goal:** Replace `ScoreActionHint` usage in `analysis_screen.dart` with `CoachActionCard` driven by a deterministic app-side `CoachActionPolicy` that picks the single most useful interaction skill for the user to practice this turn, rendered with a **6-field card** (`actionLabel / whyNow / task / suggestedLine / avoid / learningLink`) and an exact-article deep link into the existing Learning Zone (CTA hidden when no exact article maps).

**Architecture:**

1. New domain layer `lib/features/analysis/domain/coach/`:
   - `coach_action_type.dart` — sealed enum of 9 actionTypes.
   - `coach_action_card_data.dart` — view model: `actionLabel / whyNow / task / suggestedLine / avoid / learningLink`.
   - `coach_action_policy.dart` — pure function: `(heatScore, gameStage, finalRecommendation, conversationMessages, practiceGoals, isDataQualityFlagged) -> CoachActionCardData`.
2. New presentation widget `lib/shared/widgets/coach_action_card.dart` consumes `CoachActionCardData`.
3. New mapping `lib/features/analysis/domain/coach/learning_link_resolver.dart`: pure `CoachActionType -> String?` returning either an exact `articleId` from the existing 20-article ID space (`'1'..'20'`) or `null`. **Phase 1 supports exact-article deep link only**; when resolver returns `null` the card hides its "看教學" CTA (no category landing page route exists yet, and pushing `/` lands on the home tab — that is an explicit non-goal for Phase 1).
4. `analysis_screen.dart:3819` swap: replace `ScoreActionHint(...)` usage with a `Consumer` that builds `CoachActionCardData` via policy + renders `CoachActionCard`.
5. **`ScoreActionHint` is NOT deleted in this PR.** Its file and tests stay in-tree as a rollback safety net while CoachActionCard soaks on TF. A follow-up cleanup commit (post Phase 1 TF smoke green) removes them. Its meeting-keyword guard logic is reproduced inside `CoachActionPolicy` so the new path never regresses on the low-heat invite suppression contract.

**Tech Stack:** Flutter 3 / Riverpod / `go_router` (deep link via `context.push('/article/<id>')`). No backend changes, no schema changes, no new Edge function, no new Hive box.

---

## 1. Pre-Implementation Reading (REQUIRED before Task 1)

Before writing any code, the implementer must read these to internalize current contracts:

| File | Why |
|------|-----|
| `lib/shared/widgets/score_action_hint.dart` | Existing widget being replaced — note `_meetingKeywords` list and `_canSurfaceMeetingHint` (score >= `hotMax+1` = 81) — this contract MUST survive in the new policy |
| `lib/features/analysis/domain/entities/analysis_models.dart:100-200` | `GameStageInfo` (current/status/nextStep) and `FinalRecommendation` (pick/content/reason/psychology) shape |
| `lib/features/analysis/domain/entities/enthusiasm_level.dart` + `lib/core/constants/app_constants.dart:9-11` | Heat tier thresholds: `coldMax=30 / warmMax=60 / hotMax=80` |
| `lib/features/user_profile/domain/entities/user_profile.dart:18-26` | `PracticeGoal` enum has 5 values — only **partial** overlap with the 9 actionTypes (mapping in §5.3) |
| `lib/features/user_profile/data/providers/partner_style_providers.dart:48-56` | `effectiveStyleProvider(partnerId)` already merges global + override; reuse it, do NOT call `userProfileControllerProvider` directly |
| `lib/features/user_profile/data/providers/data_quality_flag_provider.dart` | `dataQualityFlagProvider(partnerId)` — Spec 3 contract. `.isFlagged` is the only field policy needs |
| `lib/features/learning/data/articles_data.dart` | 20 articles, IDs `'1'..'20'`, 4 categories (`核心社交心法 / 深度交流 / 幽默與調情 / 非語言溝通`). No `subCategory`, no tags |
| `lib/app/routes.dart:121-126` | `/article/:id` route already wires `ArticleDetailScreen` — deep link is a one-liner |
| `test/widget/widgets/score_action_hint_test.dart` | 4 tests. The meeting-suppression cases (tests 2 & 3) MUST be re-expressed in `coach_action_policy_test.dart` — do not silently delete that coverage |
| `docs/plans/2026-04-30-memory-coach-spec4-coach-action-loop-draft.md` §5-§7 | Earlier brainstorm — useful but **non-binding**; this plan is the source of truth for Phase 1 |

---

## 2. File Touch List (Concrete Paths)

### Create (new files)

```text
lib/features/analysis/domain/coach/coach_action_type.dart
lib/features/analysis/domain/coach/coach_action_card_data.dart
lib/features/analysis/domain/coach/coach_action_policy.dart
lib/features/analysis/domain/coach/learning_link_resolver.dart
lib/shared/widgets/coach_action_card.dart

test/unit/features/analysis/domain/coach/coach_action_policy_test.dart
test/unit/features/analysis/domain/coach/learning_link_resolver_test.dart
test/widget/shared/coach_action_card_test.dart
```

### Modify (existing files)

```text
lib/features/analysis/presentation/screens/analysis_screen.dart   # ~line 3819 swap; +import; +Consumer wrapper
```

### Deferred to follow-up cleanup PR (post Phase 1 TF smoke green)

```text
lib/shared/widgets/score_action_hint.dart
test/widget/widgets/score_action_hint_test.dart
```

Both stay in-tree during Phase 1 as a rollback safety net. They become unreferenced once `analysis_screen.dart` swaps to `CoachActionCard`, but `flutter analyze` does not error on unreferenced top-level widgets. Cleanup happens only after CoachActionCard has soaked one TF cycle without regressions.

**Out-of-scope (do NOT touch):**
- `supabase/functions/analyze-chat/**` — schema unchanged.
- `lib/features/learning/data/articles_data.dart` — content frozen; no new article IDs.
- Any prompt files. Any OCR path. Any RevenueCat / subscription code.
- `analysis_models.dart` AnalysisResult shape — Phase 1 uses existing fields only.

---

## 3. The 9 ActionTypes — Canonical Spec

| # | actionType | One-line meaning | Heat band (preferred) | Stage hint (preferred) |
|---|-----------|------------------|-----------------------|------------------------|
| 1 | `softInvite` | 模糊邀約 — 給一個低門檻、可拒可改的邀約 | 81+ (veryHot only) | close |
| 2 | `lowerPressureReply` | 降低壓力 — 把上一句拆掉追問味，留出空白 | 0-30 cold OR detected `qualificationSignal=false` w/ heavy questions | any |
| 3 | `extendTopic.storyFrame` | 故事框架 — 用「場景 + 觀點/情緒 + 開放式提問」延展 | 31-60 warm | premise / development |
| 4 | `emotionalResonance` | 情緒共鳴 — 先接住對方情緒再回 | any heat where `psychologyAnalysis.subtext` non-trivial OR `challengeSignal` detected (see naming note below) | any |
| 5 | `rightSizeReply` | 回得剛剛好 — 對齊 1.8x 黃金法則，避免過度延伸 | warm-hot when last user reply > partner × 1.8 | any |
| 6 | `playfulReply` | 輕鬆幽默 — 拋一個 playful 卡點 | 31-80 warm-hot | development / close |
| 7 | `pausePursuit` | 暫停追問 — 留白、不主動再傳 | 0-30 cold OR `shouldGiveUp=true`-adjacent (low but not give-up) | any |
| 8 | `preferenceSignal` | 輕量表達偏好 — 講一個自己的小喜好/觀點，不問問題 | 31-80 warm-hot | premise / development |
| 9 | `fitCheck` | 互動品質觀察 — 描述「這次互動感覺如何」，**不貼人格標籤** | always available as fallback when none of 1-8 fits cleanly | any |

**Selection priority (deterministic, top-down):**

```text
1. shouldGiveUp == true                                        -> NO CARD (existing 🚫 banner already handles this; we render nothing)
2. dataQualityFlag.isFlagged                                   -> SAFE SET ONLY: {emotionalResonance, rightSizeReply, lowerPressureReply, fitCheck}
                                                                  rationale: long-term traits unsafe; current-message-only
3. heat >= 81 AND meeting-language gameplay confirmed          -> softInvite
4. heat <= 30 AND payload contains meeting keyword             -> pausePursuit (this enforces ScoreActionHint's old meeting-suppression contract)
5. heat <= 30                                                  -> lowerPressureReply OR pausePursuit (tie-broken by practiceGoals)
6. last user reply length / last partner reply length > 1.8    -> rightSizeReply
7. challengeSignal detected OR strong subtext signal           -> emotionalResonance
8. heat 31-80 AND practiceGoals contains humorousReply         -> playfulReply
9. heat 31-80 AND gameStage in {premise, development}          -> extendTopic.storyFrame OR preferenceSignal (tie-broken by practiceGoals: explainLess -> preferenceSignal, otherwise storyFrame)
10. else                                                       -> fitCheck (always-safe fallback)
```

**Naming note — `challengeSignal`:** the upstream field on `PsychologyAnalysis` is named `shitTest` (legacy term, frozen). All **new** Spec 4 code (policy / tests / docs / variable names) MUST use `challengeSignal` (or `emotionalTensionSignal`) as the local name. Read it from `psychology.shitTest != null` at the call site, then never propagate the legacy name into Spec 4 surfaces. Renaming the upstream field is out of scope (would touch analyze-chat schema parsing).

**Practice-goal tie-breakers (only when steps above produce a tie):**

| PracticeGoal | Bumps actionType priority |
|--------------|---------------------------|
| `softInvite` | softInvite (heat 81+ only) |
| `reduceAnxiety` | lowerPressureReply, pausePursuit |
| `humorousReply` | playfulReply |
| `buildCloseness` | emotionalResonance |
| `explainLess` | rightSizeReply, preferenceSignal |

Tie-breakers MAY NOT override the heat / data-quality / meeting-suppression rules. They only choose between options the upstream rules already approved.

---

## 4. Card Field Spec

| Field | Type | Source | Length cap | Notes |
|-------|------|--------|-----------|-------|
| `actionLabel` | `String` | static per actionType (table in policy) | ≤ 12 chars | e.g. `'模糊邀約'`, `'故事框架'`, `'回得剛剛好'` |
| `whyNow` | `String` | composed from heat tier + gameStage + signals | ≤ 60 chars | e.g. `'熱度 88、對方提到週末空檔，可以給具體選項'` |
| `task` | `String` | static per actionType template | ≤ 40 chars | One single concrete micro-action, NOT multi-step |
| `suggestedLine` | `String?` | from `finalRecommendation.content` IF safe + matches actionType, else static template, else `null` | ≤ 80 chars | If `null`, the card omits this row gracefully |
| `avoid` | `String` | static per actionType | ≤ 40 chars | e.g. `'別連問三題'` |
| `learningLink` | `String?` (articleId) | from `LearningLinkResolver.resolve(actionType)` | — | Returns articleId if exact match in 20-article set, else `null`. **Phase 1 hides the CTA row entirely when `null`** — no category fallback navigation (no learning-tab route exists). |

**Suggestion-line safety filter (re-implements ScoreActionHint guard):** any line containing `_meetingKeywords` (`見面 / 邀約 / 約她 / 約他 / 約出來 / 約出門 / 約會 / 吃飯 / 喝咖啡 / 看電影 / 一起去 / 碰面 / 見個面`) is suppressed when `heat < 81` — set `suggestedLine = null` and the card hides that row. Existing test cases at `score_action_hint_test.dart:40-99` are the regression contract.

**Spec 3 flagged-partner override:** when `dataQualityFlagged == true`, `whyNow` MUST be sourced from current-conversation-only signals. Forbidden tokens: `'你們之前 / 上次聊到 / 通常她 / 她總是 / 從歷史看'`. (Implemented as a string-containment denylist in policy + asserted in tests.)

---

## 5. Risks (User-Requested Section)

### 5.1 — CoachActionPolicy picks the wrong actionType

**Likelihood:** High during initial tuning. **Impact:** Medium — wrong but never harmful (no red-line breach), just unhelpful.

**Mitigations:**
- Selection rules in §3 are **purely deterministic** — same input always produces same output. No randomness, no ML.
- Each rule has a dedicated `coach_action_policy_test.dart` test case (~25 cases minimum).
- `fitCheck` is the always-safe fallback. The test "no rule matched -> fitCheck" exists explicitly.
- Phase 1 ships behind no flag; we observe TF feedback and tune the priority list in Phase 1.5 if needed (one-line edits in policy).
- **NOT mitigated:** subjective "this would have been a better pick" feedback. We accept that risk because Phase 1's job is to make ScoreActionHint smarter and more honest, not optimal.

### 5.2 — Learning article route stability + Codex amendment 2

**Likelihood:** Low. **Impact:** Low — Phase 1 only navigates when an exact articleId exists; otherwise the CTA is simply hidden. No fake category landing.

**Findings from code:**
- Routes are stable: `GoRoute('/article/:id')` exists, `articleId: state.pathParameters['id']!`.
- Article IDs are stable strings `'1'..'20'`. No renumbering in the last 60 commits (`git log --oneline -60 -- lib/features/learning/data/articles_data.dart`).
- **No category-landing route exists.** `learning_screen.dart` shows the full list grouped by category, with no navigation target per category.
- **Codex amendment 2 (locked):** `context.push('/')` is **forbidden as a fallback** — `/` resolves to `MainShell` index=0 (home), NOT the Learning tab. A genuine learning-tab deep link (e.g. `/?tab=learning` or a new `/learning` route + shell tab sync) is out of scope for Phase 1.

**Decision (locked):** `learningLink` is a nullable `String?` (the articleId). When `null`, `CoachActionCard` hides the CTA row entirely — no "看教學" button, no fake navigation. Two of the nine actionTypes (`softInvite`, `pausePursuit`) have no exact matching article today; their cards ship in Phase 1 with no learning CTA. This is acceptable because:
- Both are safety-critical actionTypes (low heat / cooldown / pulled invite) where action > learning.
- A future Phase 1.5 can either author dedicated articles for them OR introduce a real learning-tab route.

**Article ID ↔ actionType static mapping (locked, 9 rows, exact-only):**

| actionType | articleId (exact) | Source title | Notes |
|-----------|------------------|---------------|-------|
| `softInvite` | `null` | — | No exact article. CTA hidden in Phase 1. |
| `lowerPressureReply` | `'10'` | 讓人放鬆的 11 個小細節 | |
| `extendTopicStoryFrame` | `'14'` | 會說故事的人最迷人 | |
| `emotionalResonance` | `'11'` | 主動傾聽：被低估的超能力 | |
| `rightSizeReply` | `'12'` | 訊息調情的潛規則 | |
| `playfulReply` | `'3'` | 如何變得更幽默 | |
| `pausePursuit` | `null` | — | No exact article. CTA hidden in Phase 1. |
| `preferenceSignal` | `'2'` | 深度對話的藝術 | |
| `fitCheck` | `'18'` | 社交技巧是可以練的 | |

This mapping is **a single 9-row `Map<CoachActionType, String?>` constant** in `learning_link_resolver.dart`. Tunable in one PR.

**Future enabler (NOT in Phase 1 scope):** when the Learning tab gets a real route, a Phase 1.5 follow-up can switch the resolver return type to `({String? articleId, String? categoryRoute})` and unhide the CTA for the two `null` rows. The 9-row map is the pivot point.

### 5.3 — Should ScoreActionHint be kept as fallback? (Codex amendment 3 — flipped)

**Decision (locked, post Codex review): YES — keep ScoreActionHint and its widget tests in-tree during Phase 1. Cleanup deferred to a separate PR after TF smoke green.**

**Reasoning (Codex's argument, accepted):**
- We are in TF stabilization mode (送審前最後穩定化, per project CLAUDE.md). New widgets need a soak window; deleting the old one same-PR removes the rollback safety net.
- `flutter analyze` does not error on unreferenced top-level widgets, so leaving the file in-tree is cost-free until cleanup.
- A separate cleanup commit makes regression bisection cheaper (one commit = one concern).

**What this PR DOES change:**
- `analysis_screen.dart:3819` no longer renders `ScoreActionHint` (replaced by `CoachActionCard`).
- `score_action_hint_test.dart` keeps running (verifies ScoreActionHint still works in isolation, even though no production caller uses it). Deletion of these tests is part of the deferred cleanup PR, not this one.

**Test coverage migration (still done in Phase 1, regardless of fallback question):**
The 4 widget tests in `score_action_hint_test.dart` are **mirrored** (not replaced) into `coach_action_policy_test.dart` so the meeting-suppression + tier-fallback contract is enforced at the policy layer:
- test 1 ("high heat shows actionable next-step") → policy test: heat 90 + close stage → softInvite, suggestedLine surfaces.
- test 2 ("low heat suppresses meeting payload") → policy test: heat 20 + meeting keyword in nextStep → pausePursuit, NOT softInvite.
- test 3 ("low heat suppresses meeting recommendation body") → policy test: heat 35 + meeting body → suggestedLine is null.
- test 4 ("missing payload renders safe tier fallback") → policy test: heat 50 + empty recommendation → fitCheck or extendTopicStoryFrame, no crash.

After mirroring, both test suites coexist temporarily — the duplication is an explicit, time-boxed cost.

### 5.4 — How Spec 3 dataQualityFlag plugs in

**Already wired upstream.** `dataQualityFlagProvider(partnerId)` returns `DataQualityFlag` with `.isFlagged`. The integration is one line in `analysis_screen.dart`:

```dart
// Pseudocode for plan; not the final code:
final partnerId = ref.watch(conversationProvider(widget.conversationId))?.partnerId;
final flagged = partnerId == null
    ? false
    : ref.watch(dataQualityFlagProvider(partnerId)).isFlagged;
```

Then pass `flagged` into the policy. The policy's §3 rule 2 already reduces actionType space to safe set when flagged.

**Risk:** the user's red line says "Spec 3 flagged 時，只能用當下對話". Two ways to break this:
1. Policy reads `effectiveStyleProvider(partnerId).practiceGoals` even when flagged → that's still **per-partner override**, which is "long-term per-partner data". 
   - **Mitigation:** when `flagged == true`, policy ignores `practiceGoals` entirely — use only global `practiceGoals` from `effectiveStyle.practiceGoals` IS partner-merged but the partner override path is exactly the long-term trait we shouldn't trust. **Decision: when flagged, policy uses ONLY heat + gameStage + last 2 messages + 1.8x ratio.** No practiceGoals at all.
2. `whyNow` text leaks long-term traits via the prompt → not an issue here because Phase 1 generates `whyNow` from a static template per-actionType + the current heat / stage values; no AI generation.

### 5.5 — Which existing widget tests will break

**Inventory (`grep -rln 'ScoreActionHint\|score_action_hint' test/`):**

```
test/widget/widgets/score_action_hint_test.dart           — STAYS in Phase 1 (Codex amendment 3); deleted in deferred cleanup PR.
```

**Searched for indirect breakage:**

```bash
grep -rln "ScoreActionHint\|score_action_hint" test/ lib/
# Returns ONLY: lib/shared/widgets/score_action_hint.dart, lib/features/analysis/presentation/screens/analysis_screen.dart, test/widget/widgets/score_action_hint_test.dart
```

No widget test imports `ScoreActionHint` outside its own test file. Analysis-screen widget tests (if any) likely pump `AnalysisScreen` and assert on `find.text('下一步')` — that headline is **going away** from the production render path. Need to grep up-front:

```bash
grep -rn "find.text('下一步')" test/
# Run during Task 0 (pre-flight). If hits exist, those tests need updating to '本回合練什麼' or to the actionLabel.
```

**Pre-Task-1 verification step:** run that grep in Task 0 and add any hits to Task 13 (analysis screen wiring) so the same PR fixes them.

### 5.6 — Other risks not in user's list (Codex should review)

- **R6.1 — `effectiveStyleProvider` returns AsyncValue / sync data.** Source confirms it's a sync `Provider.family`, not Async — safe to `ref.watch`.
- **R6.2 — `conversationProvider` may return null** during initial load, so `partnerId` resolution must handle null → treat as `flagged=false` and skip practiceGoals.
- **R6.3 — Card rendering inside the existing `if (_shouldGiveUp) ... else ...` ternary** at `analysis_screen.dart:3791-3824` — must keep the give-up branch intact and only swap the else branch.
- **R6.4 — `GlassmorphicContainer` styling parity.** ScoreActionHint uses `GlassmorphicContainer`. CoachActionCard SHOULD reuse the same container so visual diff is minimal — Bruce's design pass focuses on "本回合練什麼" headline, not chrome.
- **R6.5 — Resolver return type is `String?` (articleId only).** Codex amendment 2 removed the categoryFallback path. The mapping table is a `Map<CoachActionType, String?>` keyed by enum, value is `'1'..'20'` or `null`. Task 4 enforces (via test) that every non-null value still exists in `articlesData` so a future article-renumber doesn't silently break the deep link.
- **R6.6 — i18n.** All copy is Traditional Chinese hardcoded, matching project convention. No i18n abstraction in Phase 1.

---

## 6. TDD Task Breakdown

Each task is one TDD cycle: red test → run (fail) → minimal impl → run (pass) → commit. Commit message format: `[feat] Spec 4 Phase 1 Task N — <short>`. Frequent commits, one task one commit.

### Task 0: Pre-flight verification (no code, no commit)

- Run `grep -rn "find.text('下一步')" test/` — record hits.
- Run `flutter test` once on baseline — record green count (call this `baselineGreen`).
- Confirm `score_action_hint.dart` import is only in `analysis_screen.dart` (we already did, but re-verify against current HEAD).
- Confirm `articles_data.dart` IDs `'2', '3', '10', '11', '12', '14', '18'` still exist (lookup table sanity).

**Output:** a 3-line scratch note pinned in PR description: `baselineGreen=N, downStep_hits=…, articleIds_ok=true|false`.

### Task 1: CoachActionType enum

**Files:** Create `lib/features/analysis/domain/coach/coach_action_type.dart`.

**Step 1 — Test (`test/unit/features/analysis/domain/coach/coach_action_policy_test.dart`):**

```dart
test('CoachActionType has 9 distinct values matching spec', () {
  expect(CoachActionType.values.length, 9);
  expect(CoachActionType.values.toSet(), {
    CoachActionType.softInvite,
    CoachActionType.lowerPressureReply,
    CoachActionType.extendTopicStoryFrame,
    CoachActionType.emotionalResonance,
    CoachActionType.rightSizeReply,
    CoachActionType.playfulReply,
    CoachActionType.pausePursuit,
    CoachActionType.preferenceSignal,
    CoachActionType.fitCheck,
  });
});
```

**Step 2:** `flutter test test/unit/features/analysis/domain/coach/coach_action_policy_test.dart` → fail (type missing).

**Step 3:** Add the enum (file has no behavior, just 9 values + brief docComment per value).

**Step 4:** Run test → green.

**Step 5:** Commit.

### Task 2: CoachActionCardData view model

**Files:** Create `lib/features/analysis/domain/coach/coach_action_card_data.dart`.

**Step 1 — Test:** equality + `toString`, all 6 fields preserved.

**Step 2-5:** Standard `@immutable` data class, `==`, `hashCode`. No Hive — this is a transient view model, never persisted.

### Task 3: LearningLinkResolver — exact-article path

**Files:** Create `lib/features/analysis/domain/coach/learning_link_resolver.dart`, `test/unit/features/analysis/domain/coach/learning_link_resolver_test.dart`.

**Step 1 — Tests** (one per actionType, all 9):

```dart
test('softInvite -> null (no exact article in current 20-set)', () {
  expect(LearningLinkResolver.resolve(CoachActionType.softInvite), isNull);
});

test('extendTopicStoryFrame -> articleId 14', () {
  expect(LearningLinkResolver.resolve(CoachActionType.extendTopicStoryFrame), '14');
});

test('pausePursuit -> null', () {
  expect(LearningLinkResolver.resolve(CoachActionType.pausePursuit), isNull);
});
// ... 6 more tests, one per actionType, asserting the §5.2 table.
```

**Step 2-5:** Implement as `static const Map<CoachActionType, String?> _table = {...}` + `static String? resolve(CoachActionType t) => _table[t]`. **No `LearningLinkRef` class** — return type is plain nullable String (the articleId). Codex amendment 2 dropped the categoryFallback path.

### Task 4: LearningLinkResolver — articleId-still-exists guard

**Files:** Same.

**Step 1 — Test:** for every actionType where `articleId != null`, assert that `articleId` is found in `articlesData` from `articles_data.dart`. This guards against silent drift if articles are renumbered.

**Step 2-5:** Either import `articlesData` and iterate, or hard-code expected IDs and add a comment in `articles_data.dart` near each affected ID like `// referenced by LearningLinkResolver — do not renumber`.

### Task 5: CoachActionPolicy — base structure + fitCheck fallback

**Files:** Create `lib/features/analysis/domain/coach/coach_action_policy.dart`.

**Step 1 — Test:** with all-empty / neutral input, returns `fitCheck`.

```dart
test('empty signals -> fitCheck fallback', () {
  final card = CoachActionPolicy.evaluate(
    heatScore: 50,
    gameStage: GameStageInfo(current: GameStage.opening, nextStep: ''),
    finalRecommendation: FinalRecommendation(pick: 'extend', content: '', reason: '', psychology: ''),
    messages: [],
    practiceGoals: const [],
    isDataQualityFlagged: false,
  );
  expect(card.actionLabel, '互動品質觀察');
});
```

**Step 2-5:** Implement skeleton that returns hardcoded fitCheck card. All 9 static label/task/avoid templates added in §6 helper struct.

### Task 6: Policy — softInvite at heat 81+

**Step 1 — Test:** heat 90, close stage, recommendation content non-empty → softInvite, suggestedLine surfaces.

**Step 2-5:** Add rule 3 from §3.

### Task 7: Policy — meeting-language suppression at low heat (THE regression contract)

**Step 1 — Tests (3, ported from `score_action_hint_test.dart`):**
- heat 20 + nextStep `'直接約她出來吃飯'` → pausePursuit, suggestedLine null.
- heat 35 + recommendation content `'週末要不要一起去喝咖啡？'` → suggestedLine null (regardless of actionType).
- heat 25 + nextStep contains `'見個面'` → pausePursuit (NOT softInvite even if recommendation suggests it).

**Step 2-5:** Implement rules 4 + the suggestionLine safety filter from §4.

### Task 8: Policy — extendTopic.storyFrame for warm + premise

**Step 1-5:** Test + impl rule 9. Tie-breaker: `practiceGoals.contains(explainLess)` flips to `preferenceSignal` instead.

### Task 9: Policy — emotionalResonance trigger (challengeSignal / strong subtext)

**Step 1-5:** Test + impl rule 7. Read `psychologyAnalysis.subtext` from analysis result — that field is not in the policy input contract today (we passed `finalRecommendation` only).

**Plan amendment:** add `PsychologyAnalysis? psychology` to policy input. Source from `analysisResult.psychologyAnalysis` at the analysis_screen call site (§Task 13).

**Naming (Codex amendment 4):** the upstream field is named `shitTest` (legacy). All new Spec 4 code refers to it as `challengeSignal` — read `psychology.shitTest != null` once at the policy entry point and assign to a local `final challengeSignal = psychology?.shitTest != null;`. **Do NOT propagate the legacy token into Spec 4 variable names, test descriptions, doc comments, or commit messages.**

### Task 10: Policy — rightSizeReply (1.8x ratio)

**Step 1 — Test:** messages where last user reply char count > last partner reply × 1.8 → rightSizeReply (heat warm-hot).

**Step 2-5:** Implement rule 6. Use `Message.text.length` (CJK char count) as proxy. Reuse if `lib/features/analysis/domain/services/` already has a 1.8x checker — check first.

### Task 11: Policy — practiceGoal tie-breakers + dataQualityFlag safe-set

**Step 1 — Tests:**
- heat 50 + premise + practiceGoals = [humorousReply] → playfulReply (rule 8 wins over 9).
- isDataQualityFlagged=true + heat 90 + close → returns from safe set only (NOT softInvite); falls back to fitCheck.
- isDataQualityFlagged=true → practiceGoals input is **ignored** (sanity test: same flagged input with [softInvite] vs [reduceAnxiety] returns same actionType).
- whyNow text from flagged path contains none of: `你們之前 / 上次 / 通常她 / 她總是`.

**Step 2-5:** Implement rules 1-2 + tie-breakers + denylist assert in policy `whyNow` builder.

### Task 12: CoachActionCard widget

**Files:** Create `lib/shared/widgets/coach_action_card.dart` + `test/widget/shared/coach_action_card_test.dart`.

**Step 1 — Tests (4):**
- All 6 fields populated (with non-null `learningLink` articleId) → all rows rendered.
- `suggestedLine == null` → "試試這樣回" row absent (matches old test 4 contract).
- `learningLink == null` → "看教學" CTA row absent **and** no fallback navigation is wired.
- Tap learningLink with `articleId='14'` → navigates `/article/14` (verify with `find.byKey(const Key('coach_action_learning_cta'))` + a mock router that captures `push` calls; do NOT exercise the real go_router stack in this widget test).

**Step 2-5:** Build the widget with `GlassmorphicContainer` chrome (parity with ScoreActionHint), header `'本回合練什麼 · {actionLabel}'`, body rows for `whyNow / task / suggestedLine? / avoid / learningLink?`. Tap behavior: `context.push('/article/$articleId')` when articleId is non-null. When `learningLink == null`, the entire CTA row is omitted (no fake category route, no `/` push — Codex amendment 2).

### Task 13: Wire into AnalysisScreen

**Files:** Modify `lib/features/analysis/presentation/screens/analysis_screen.dart` only at `:3819` (the `else { ScoreActionHint(...) }` branch).

**Step 1 — Test:** if existing analysis_screen widget tests exist (`grep -rn "AnalysisScreen" test/`) for nextStep — update them. If none, write a new one: pump `AnalysisScreen` with conversation that has heat 90 + close stage + meeting recommendation, expect `'本回合練什麼'` headline and `'模糊邀約'` actionLabel rendered.

**Step 2:** Run → fail.

**Step 3 — Implement:** wrap the else branch with `Consumer` that:
1. Reads `effectiveStyle` via `ref.watch(effectiveStyleProvider(partnerId))` (skip if partnerId null).
2. Reads `flagged` via `ref.watch(dataQualityFlagProvider(partnerId)).isFlagged` (skip if partnerId null → false).
3. Reads conversation messages via `ref.read(conversationProvider(widget.conversationId))?.messages ?? []`.
4. Calls `CoachActionPolicy.evaluate(...)` → `CoachActionCardData`.
5. Renders `CoachActionCard(data: cardData)`.

**Step 4:** Run → green.

**Step 5:** Commit.

### Task 14: ScoreActionHint cleanup deferred — verify-only step

**Files:** None modified. **Codex amendment 3:** ScoreActionHint and its tests stay in-tree this PR.

**Step 1 — Verify nothing renders ScoreActionHint in production:**

```bash
grep -rn "ScoreActionHint" lib/
# Expected: only the file itself (lib/shared/widgets/score_action_hint.dart). No call sites in any screen.
```

**Step 2 — Verify both legacy + new tests run green:**

```bash
flutter test test/widget/widgets/score_action_hint_test.dart
flutter test test/widget/shared/coach_action_card_test.dart
flutter test test/unit/features/analysis/domain/coach/
```

**Step 3 — Document deferred cleanup in PR description:**

> Follow-up cleanup PR (post Phase 1 TF smoke green): delete `lib/shared/widgets/score_action_hint.dart` and `test/widget/widgets/score_action_hint_test.dart`. Tracked in §5.3.

**Step 4-5:** No commit (no file change). Move to Task 15.

### Task 15: Regression sweep

- Run `flutter test` whole suite — **must equal `baselineGreen` from Task 0** (delta = -4 from removed score_action_hint_test.dart, +N from new coach tests). Document delta in PR description.
- Run TF perimeter from `docs/testflight-regression-checklist.md` items relevant to analysis screen (if list exists).
- Manual smoke on web preview: 1 conversation each at heat 20 / 50 / 90, plus 1 dataQualityFlagged conversation. Screenshot each and attach to PR.

### Task 16: Snapshot + memory

- Update `docs/snapshot.md`: Spec 4 Phase 1 line.
- Update `docs/decisions.md`: ADR for "ScoreActionHint usage replaced by deterministic CoachActionPolicy + CoachActionCard; legacy widget retained in-tree pending TF-soak cleanup follow-up".
- Save memory: project "Spec 4 Phase 1 shipped at HEAD <sha>; legacy ScoreActionHint cleanup deferred per Codex amendment 3".

---

## 7. Locked Decisions (Codex review answers Q1–Q5)

Originally posed as open questions; locked by Codex review 2026-05-01:

1. **Q1 (single enum vs subtype) — LOCKED: single enum.** `CoachActionType.extendTopicStoryFrame` is one value. No subtype machinery in Phase 1. If a future variant (e.g. `extendTopic.openQuestion`) becomes needed, add it as a sibling enum value (e.g. `extendTopicOpenQuestion`) — flat namespace, no subtype field.
2. **Q2 (file location) — LOCKED: `lib/features/analysis/domain/coach/`.** Policy reads `AnalysisResult`-shaped input, so colocating with `analysis/` is correct for Phase 1. If Spec 4 grows past Phase 1 we can extract a sibling `coach/` feature directory; until then, no premature feature carve-out.
3. **Q3 (`learningLink == null`) — LOCKED: nullable, hide CTA when null.** `LearningLinkResolver.resolve` returns `String?` (the articleId). When null, `CoachActionCard` omits the entire CTA row. No category-deep-link fallback in Phase 1 (no real route exists; pushing `/` would land on the home tab, not learning — see §5.2).
4. **Q4 (emoji) — LOCKED: no emoji on `CoachActionCard` header.** Bruce's "less is more" stance preserved. The actionLabel text alone is the headline.
5. **Q5 (TF gate) — LOCKED: gate cleared 2026-05-01.** Eric dogfood-smoked Spec 3 as acceptable and explicitly asked CC to proceed. Phase 1 ships via direct commits to `main` (consistent with project workflow); a separate feature branch is NOT used. See §9 for the trigger record.

---

## 8. Product Red Lines (Re-asserted, for Test Coverage)

These are encoded as policy tests, not just code review notes:

- **No cold-shoulder tactics:** `pausePursuit` task copy says `'今天先不主動再傳，明天觀察她有沒有開新話題'`, NOT `'故意不回'` or `'消失'`. Test asserts the avoid field never contains `'消失 / 不回 / 已讀不回'`.
- **No status-game playbook:** no actionType references "推拉 / 製造焦慮 / 反差". Tests assert `task` field never contains those tokens.
- **fitCheck is descriptive, not labeling:** `task` says `'觀察這次的節奏，記下一個感覺'`, NOT `'判斷她是不是 X 型人格'`. Test asserts `task` for fitCheck never contains `'人格 / 型 / 是 ... 的人'`.
- **All actions return to: stable self / honest expression / respect / connection.** This is harder to encode as a hard test, but every `whyNow` template is reviewed in Codex pass against the four pillars.

---

## 9. Execution Handoff — TF Gate (Codex amendment 5)

**Hard gate before any code work begins on this plan:**

> Spec 3 (Partner Data Quality Guard) gate cleared on 2026-05-01. Eric dogfood-smoked the current Spec 3 flow as acceptable (`還可以`) and asked CC to continue. Bruce broader dogfood feedback is still welcome, but it no longer blocks Spec 4 Phase 1 execution.

Once the gate clears, Phase 1 ships via direct commits to `main` (project default workflow — no feature branch). Two execution options:

1. **Subagent-Driven (this session)** — fresh subagent per task, review between tasks, fast iteration.
2. **Parallel Session (separate)** — open new session with `superpowers:executing-plans`, batch execution with checkpoints.

**Recommendation:** Subagent-driven — Tasks 1–13 are tight TDD loops (5–15 min each) and benefit from inline review.

**Trigger record:** Eric explicitly said Spec 3 is acceptable in dogfood and asked CC to proceed on 2026-05-01. This satisfies the "Spec 3 TF smoke OK，Spec 4 Phase 1 開工" trigger.

---

## 10. Codex Amendment Log (2026-05-01 review)

| # | Codex Note | Action Taken | Sections Changed |
|---|-----------|---------------|-------------------|
| 1 | Plan file untracked — commit + push | Will commit + push immediately after this revision | (workflow, no doc change) |
| 2 | Forbid `context.push('/')` learning fallback | `LearningLinkResolver.resolve` now returns `String?`; CTA hidden when null; no category-route navigation in Phase 1 | Architecture bullet 3, §4 learningLink row, §5.2 (full rewrite + mapping table simplified), Task 3 (test list + return type), Task 12 (tap behavior) |
| 3 | Don't delete ScoreActionHint this PR | Flipped recommendation; legacy widget + tests stay in-tree as rollback safety net; cleanup deferred to follow-up commit post TF smoke | Architecture bullet 5, §2 Delete → Deferred, §5.3 (full flip), §5.5 (legacy test stays), Task 14 (verify-only, no commit), Task 16 (ADR wording) |
| 4 | Rename `shitTest` to `challengeSignal` in new code | Naming note added to §3; Task 9 explicitly forbids legacy token in Spec 4 surfaces; upstream field name unchanged (out of scope) | §3 rule 7 + naming note, Task 9 |
| 5 | TF gate workflow inconsistency | Locked: once Spec 3 smoke is acceptable, ship Spec 4 via direct main commits (option A from Codex). Gate cleared 2026-05-01 by Eric dogfood signal. | Header status line, §7 Q5, §9 (rewrite) |
| 6 | Goal said 5-field, §4 had 6 | Goal sentence rewritten to explicitly say 6-field with the field list | Goal line |
| 7 | Test paths should mirror feature structure | All test paths updated: `test/unit/features/analysis/domain/coach/` and `test/widget/shared/` | §2 Create list, Task 1, Task 3, Task 12 |
