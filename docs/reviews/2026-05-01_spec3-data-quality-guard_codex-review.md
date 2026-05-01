# Codex Spec Review: Spec 3 Partner Data Quality Guard

**Review target**: `docs/plans/2026-05-01-spec3-data-quality-guard-design.md`  
**Reviewed commit**: `cd36a05`  
**Review type**: pre-implementation spec review  
**Verdict**: 🟡 APPROVED-WITH-AMENDMENTS

Spec direction is right: low-noise partner data-quality guard, local-first detection, no OCR / prompt / Edge Function changes, and a gentle "整理資料夾" UX instead of an error-warning UX.

Before writing the implementation plan, I would amend the design doc in four places below. These are not product disagreements; they are contract gaps that will otherwise become implementation ambiguity.

---

## Findings

### [P1] Flagged cards still inject contaminated partner context unless the spec gates `PartnerContextResolver`

The design says flagged cards should keep L1 immediate reply normal while L2 long-term memory should not keep contaminating the main card. In the current code, partner memory is not stored as one mutable "main card"; it is rebuilt from all conversation snapshots via `partner.aggregateOver(conversations)` and then injected into `analyze-chat` through `PartnerContextResolver`.

Relevant code:
- `lib/features/partner/domain/extensions/partner_aggregates.dart:39-74`
- `lib/features/partner/domain/services/partner_summary_builder.dart:29-71`
- `lib/features/analysis/data/services/partner_context_resolver.dart:37-49`
- `lib/features/analysis/presentation/screens/analysis_screen.dart:1317-1319`

If Spec 3 only adds a banner, a flagged partner will still send contaminated `興趣 / 性格 / 過往備註` into future analysis calls. That directly violates the product point of this spec: protecting memory credibility.

**Required amendment**: define a concrete flagged-state behavior for partner context. My recommendation:

- If unresolved data-quality flag exists, `PartnerContextResolver` should return a minimal partner header or `null`, not the aggregate trait/notes summary.
- This is client-side context gating, not Edge prompt editing, so it does not violate the "do not touch OCR / prompt / analyze-chat" rule.
- Partner detail UI can still show the banner and immediate conversation list; but long-term aggregate-driven advice must not use the contaminated summary until the user resolves the banner.

### [P1] New `partner_data_quality_states` box needs privacy and cascade contracts

The spec adds a new encrypted Hive box, but it does not explicitly add the same cleanup invariants we just learned from Spec 1/2:

- `StorageService.clearAll()` must clear the new box.
- Partner delete must clear data-quality state for that partner.
- Partner merge must clear the deleted source partner's data-quality state and invalidate related providers.
- Split should define what happens to source/new partner data-quality state after moving conversations.

Relevant code:
- `lib/core/services/storage_service.dart:132-140`
- `lib/features/partner/data/repositories/partner_repository.dart:64-99`
- `lib/features/partner/data/repositories/partner_repository.dart:123-136`
- `lib/features/partner/data/providers/partner_write_controller.dart:87-119`

**Required amendment**: add an explicit "Privacy / cascade contract" section to Spec 3, with tests required for `clearAll`, partner delete, merge source cleanup, and split cleanup.

### [P2] `Conversation.name` exists, but it is not a guaranteed OCR contact-name signal

The design puts `Conversation.name / OCR header / 分析後對話名稱欄位` as the first detection source. `Conversation.name` does exist, and OCR import can set it from `RecognizedConversation.contactName`, but it is also a general display/name field.

Relevant code:
- `lib/features/conversation/domain/entities/conversation.dart:14-15`
- `lib/features/analysis/domain/entities/analysis_models.dart:404-418`
- `lib/features/analysis/presentation/screens/analysis_screen.dart:950-957`
- `lib/features/analysis/presentation/screens/analysis_screen.dart:1016-1019`
- `lib/features/analysis/domain/services/screenshot_recognition_helper.dart:151-166`

There is no persisted provenance saying "this conversation name came from OCR header". There is also no sender-name field on `Message`.

**Required amendment**: implementation plan should not treat arbitrary `Conversation.name` as high-confidence. Add strict candidate rules:

- Reject placeholders and generic labels: `新對話`, `新的對話`, date-like labels, `互動紀錄`, `第 X 段`, empty strings.
- Prefer names that came through screenshot recognition flow going forward.
- For old data, accept `Conversation.name` only if it passes a conservative "looks like a person name / nickname" filter.
- Keep message regex fallback extremely narrow and capped; do not scan arbitrary full text for names.

### [P2] Remove `dismissedNamePairs` from v1 schema

The spec says v1 only persists confirmed same-person pairs, and "忽略一次" was explicitly removed. But the proposed Hive entity still reserves `dismissedNamePairs`.

Relevant design lines:
- `docs/plans/2026-05-01-spec3-data-quality-guard-design.md:190-196`
- `docs/plans/2026-05-01-spec3-data-quality-guard-design.md:199-203`

Once a Hive field ships, it becomes migration baggage. Since v1 has no behavior for dismissed pairs, keeping the field now adds schema surface without product value.

**Required amendment**: v1 entity should only contain `partnerId`, `confirmedSamePersonPairs`, and `updatedAt`. Add `dismissedNamePairs` later only if v2 reintroduces "忽略一次".

### [P2] Read-time detection needs a hard scan cap or cache rule

The direction "read-time recompute on Partner detail open" is good, but the spec should define a bounded implementation so large partner cards do not become slow.

Relevant design lines:
- `docs/plans/2026-05-01-spec3-data-quality-guard-design.md:161-168`
- `docs/plans/2026-05-01-spec3-data-quality-guard-design.md:170-184`

**Required amendment**: add one of these contracts:

- Candidate extraction is primarily from `Conversation.name`; message regex fallback scans only the first N and last N incoming messages per conversation.
- Or store per-conversation derived candidates in memory during provider lifetime and invalidate on conversation save/reassign/delete.

I would choose the first for v1; simpler, lower false-positive risk, and enough for the low-recall MVP.

---

## Pre-Plan Grep Notes

- `Conversation.name` exists, but it is a mutable display/name field.
- `RecognizedConversation.contactName` exists and flows into screenshot recognition confirmation.
- `Message` has no sender label / contact-name field.
- Partner aggregate and partner prompt context are currently derived from all conversations under the partner.
- Next Hive typeId appears to be `14` after Spec 2's `PartnerStyleOverride(typeId: 13)`.

---

## Recommended Next Step

Ask CC to amend the design doc with:

1. Client-side partner-context gating when a data-quality flag is unresolved.
2. Privacy / cascade cleanup contract for the new Hive box.
3. Conservative name-candidate rules for `Conversation.name` and regex fallback.
4. Remove `dismissedNamePairs` from the v1 schema.
5. Read-time scan cap.

After those amendments, I am comfortable moving into `superpowers:writing-plans`.

No arbitration queue update from my side yet: these are implementation-contract amendments, not a product/architecture disagreement. If CC disagrees with any P1/P2 item, then queue it as `Daisy-Decision-Needed`.

Reviewer-Hint: Reviewed design doc at `cd36a05`; inspected current `Conversation.name`, screenshot recognition contact-name flow, partner aggregate, and partner context resolver.
Next-Step: CC amends design doc, then writes implementation plan; Eric/Bruce can continue Spec 2 TF smoke in parallel.

---

# Codex Code Review: Spec 3 Partner Data Quality Guard Implementation

**Review target**: `892cf10..18f9a3e`
**Review type**: post-implementation code review + direct fix
**Verdict**: 🟡 APPROVED-WITH-CODE-FIX

Implementation is broadly sound: OCR / Edge Function / prompt paths are untouched, `PartnerContextResolver` gates flagged partner context through a provider-backed view, the new Hive box is cleared by `StorageService.clearAll()`, and delete / merge / split cascade semantics are covered.

One functional issue was found and patched directly.

## Finding Fixed

### [P1] Split action chose the moving side by canonical sort order instead of the current partner card

`NamePair.canonical()` lower-cases and lexicographically sorts both names. The Partner detail split action used `pair.second` as the name to move into a new partner. That meant the side being moved was determined by sort order, not by the current card's identity.

Example: if the current card is `May` and the conflicting pair is `Anna / May`, the old action would move `May` conversations into a new card and leave `Anna` on the original `May` card.

Patch:
- Resolve the split target from `partner.name` first.
- Keep conversations matching the current partner card name on the source card.
- Move the other name into the new partner.
- Fall back to deterministic behavior only when the current partner name is not one of the detected names.
- Preserve user-facing display casing where possible instead of showing canonical lower-case names.

Files patched:
- `lib/features/partner/presentation/screens/partner_detail_screen.dart`
- `test/widget/features/partner/partner_detail_screen_test.dart`

## Verification

- `flutter analyze --no-fatal-infos lib test` → 0 issues
- `flutter test test/widget/features/partner/partner_detail_screen_test.dart` → 22/22 green
- Spec 3 risk surface subset → 107/107 green
- Spec 3 perimeter (`test/unit/features/user_profile/ test/unit/features/partner/ test/widget/features/partner/`) → 216 pass, 1 skip, 0 fail
- Full suite → 605 pass, 1 skip, 76 fail; matches known baseline stale failures, 0 new Spec 3 regressions observed

Reviewer-Hint: Full suite still has the existing stale failures (message booster copy, widget pumpAndSettle timeouts, etc.); this review only patches the Spec 3 split-direction bug.
Next-Step: Commit + push Codex fix; Eric/Bruce TF smoke should include a card named `May` with conversations named `May` and `Anna`, then verify `May` stays on the original card after split.
