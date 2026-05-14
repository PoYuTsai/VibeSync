# 2026-05-14 CC Dogfood Handoff And Review Plan

Audience: Claude Code / CC
Owner after handoff: Claude for first-line hotfix, Codex for independent review
Status: active during TestFlight dogfood

## Why This Exists

Eric and Bruce are dogfooding the latest TestFlight builds after a large round of Spec 6 / opener / paywall / quota stabilization. A lot of the recent 1:1 Coach, opener, prompt, quota, and subscription work was driven in Codex sessions, so CC needs a clean entrypoint before acting as first-line bug fixer or second reviewer.

This file is the shared map. Read it before fixing dogfood bugs or reviewing recent feature areas.

## Required First Read

1. `AGENTS.md`
2. `docs/shared-agent-rules.md`
3. `docs/bug-log.md` recent entries from 2026-05-11 to 2026-05-14
4. `docs/integrations/revenuecat.md`
5. `docs/pricing-final.md`
6. `docs/reviews/ai-arbitration-queue.md` only for live handoff status; if text looks garbled, use this file as the clean map.
7. `git log --oneline --since="2026-05-10"`

## Current Product Direction

VibeSync is converging from "reply generator" into "a memory-based AI dating coach":

- Opener is the pioneer: help the user start a conversation from profile screenshots or manual clues.
- Analyze Chat is the main diagnostic layer: read the real chat, identify catchable points, heat, stage, and reply strategy.
- Coach 1:1 is the deeper coaching layer: answer user intent, ask clarifying questions when needed, and give concrete next steps based on context.
- Partner memory should reduce repeated setup: same partner can accumulate settings, traits, history, coach turns, opener drafts, and analysis state.
- Free users must be able to try the core product until quota is exhausted, then be guided to paywall.

## Recent Commit Landmarks

- `5f267c5` opener result draft cache and handoff cleanup
- `e660bcd` opener paid tier sync via `expectedTier` and RevenueCat app user id
- `b979198` remove backup/pioneer copy buttons where content is guidance, not direct copy
- `1f49470` opener JSON repair retry
- `54c0906` exact paywall product/package mapping
- `ce4aa9e` / `f0546c0` RevenueCat public SDK key guard/source
- `a01cb0f` / `6dc38a2` Paywall direct StoreKit fallback and package mapping
- `4954581` prevent paid tiers being downgraded to Free on empty RevenueCat response
- `6b18863` / `304e3da` Free quota alignment and opener quota allowance
- `26790b4` analysis format failure does not charge quota
- `7c19994` / `4184c75` prevent raw AI JSON from showing in UI

## Window A: Discord / TestFlight Monitor Prompt

Use this prompt for the CC window that listens to Eric + Bruce dogfood feedback.

```text
You are CC first-line hotfix for VibeSync TestFlight dogfood.

Start by reading:
- AGENTS.md
- docs/shared-agent-rules.md
- docs/reviews/2026-05-14_cc-dogfood-handoff-and-review-plan.md
- docs/bug-log.md recent 2026-05-11 to 2026-05-14 entries
- docs/integrations/revenuecat.md
- git log --oneline --since="2026-05-10"

Your role:
- Triage Discord/TestFlight bug reports from Eric/Bruce.
- Reproduce or infer the smallest root cause.
- If the bug is clear and contained, fix forward on main, run targeted tests, update docs/bug-log.md, commit + push.
- If the bug touches subscription/paywall/quota/Edge schema/OCR/prompt or could cause data loss, still investigate, but write a handoff in docs/reviews/ai-arbitration-queue.md or a new docs/reviews/YYYY-MM-DD_<topic>_claude-handoff.md and ask for Codex review before broad changes.

Hard rules:
- Do not mix OCR changes with subscription, prompt, cache, parser, or security changes.
- analyze-chat deploy must keep --no-verify-jwt.
- Do not force push.
- One commit = one issue.
- Commit message must include Reviewer-Hint and Next-Step trailers when Codex may review later.

Where to record:
- Root-cause bug: docs/bug-log.md
- Cross-agent handoff / needs review: docs/reviews/ai-arbitration-queue.md or docs/reviews/YYYY-MM-DD_<topic>_claude-handoff.md
- Durable architecture decision: docs/decisions.md
```

## Window B: Normal CC Review Prompt

Use this prompt for the CC window that performs independent review by area.

```text
You are CC reviewer for VibeSync recent high-risk work.

Read:
- AGENTS.md
- docs/shared-agent-rules.md
- docs/reviews/2026-05-14_cc-dogfood-handoff-and-review-plan.md
- git log --oneline --since="2026-05-10"

Review one block at a time from the Review Blocks section.

For each block:
- Inspect only the listed scope first.
- Look for functional bugs, broken UX logic, security/privacy issues, quota/payment regressions, and missing tests.
- Classify findings as P0/P1/P2/P3.
- P0/P1 with obvious safe fix: patch directly, test, update docs/bug-log.md if root-cause bug, commit + push.
- Architecture, product judgment, or risky payment/quota change: write docs/reviews/YYYY-MM-DD_<topic>_claude-review.md and request Codex review.
- Do not rewrite broad prompts or schemas unless the review block explicitly asks and tests are updated.
```

## Review Blocks

### Block 1: RevenueCat / Paywall / Upgrade-Downgrade

Goal: ensure all purchase and plan transition flows are safe.

Primary files:

- `lib/core/services/revenuecat_service.dart`
- `lib/features/subscription/data/providers/subscription_providers.dart`
- `lib/features/subscription/domain/entities/subscription_state.dart`
- `lib/features/subscription/domain/services/subscription_tier_helper.dart`
- `lib/features/subscription/presentation/screens/paywall_screen.dart`
- `lib/features/subscription/presentation/screens/settings_screen.dart`
- `supabase/functions/sync-subscription/index.ts`
- `supabase/functions/sync-subscription/revenuecat_identity.ts`
- `supabase/functions/revenuecat-webhook/index.ts`
- `docs/integrations/revenuecat.md`

Scenarios to review:

- Free -> Starter monthly
- Free -> Starter quarterly
- Free -> Essential monthly
- Free -> Essential quarterly
- Starter monthly -> Essential monthly / quarterly
- Starter quarterly -> Essential monthly / quarterly
- Essential monthly -> Starter monthly / quarterly
- Essential quarterly -> Starter monthly / quarterly
- Same tier monthly <-> quarterly selection
- Restore purchase after app restart
- RevenueCat temporarily returns empty entitlement
- App displays paid tier but Edge quota reads Free
- Downgrade scheduled vs current tier display
- Managing/canceling subscriptions via App Store link

Known risks:

- Wrong package selected when tapping monthly but StoreKit opens quarterly.
- Paywall stuck at "方案資訊同步中".
- RevenueCat public app SDK key vs server/API key mix-up.
- Paid user tier falling back to Free after build/reinstall.
- Pending downgrade metadata becoming stale.

Suggested tests:

- `flutter test test/widget/screens/paywall_screen_test.dart`
- `flutter test test/unit/features/subscription/data/subscription_state_package_test.dart`
- Deno tests under `supabase/functions/sync-subscription/*_test.ts` if touching Edge logic

### Block 2: Quota / 429 / Usage Sync

Goal: Free/Starter/Essential should all work until quota is truly exhausted; 429 should be accurate and guide correctly.

Primary files:

- `supabase/functions/_shared/quota.ts`
- `supabase/functions/_shared/quota_test.ts`
- `supabase/functions/analyze-chat/rate_limiter.ts`
- `supabase/functions/analyze-chat/index.ts`
- `supabase/functions/coach-chat/generation.ts`
- `supabase/functions/coach-chat/index.ts`
- `lib/core/services/usage_service.dart`
- `lib/shared/widgets/analysis_preview_dialog.dart`
- `lib/features/analysis/presentation/widgets/rate_limit_dialog.dart`
- `lib/features/analysis/presentation/widgets/analysis_error_widget.dart`
- `lib/features/subscription/presentation/screens/settings_screen.dart`

Current limits:

- Free: monthly 30 / daily 15
- Starter: monthly 300 / daily 50
- Essential: monthly 800 / daily 120

Known risks:

- Free users blocked before using any feature.
- Image/opener cost incorrectly compared against a hardcoded low monthly cap.
- Edge Function says Free quota while app settings show Essential.
- Error message exposes raw FunctionException instead of friendly copy.
- Failed AI format response charges quota.

Suggested tests:

- Deno quota tests under `supabase/functions/_shared/quota_test.ts`
- `flutter test test/widget/widgets/analysis_preview_dialog_test.dart`
- `flutter test test/widget/widgets/rate_limit_dialog_test.dart`

### Block 3: Opener / Opening Rescue

Goal: opener should feel like the pioneer, not a stale result cache or generic reply generator.

Primary files:

- `lib/features/opener/presentation/screens/opening_rescue_screen.dart`
- `lib/features/opener/data/services/opener_service.dart`
- `lib/features/opener/data/services/opener_result_cache_service.dart`
- `supabase/functions/analyze-chat/index.ts`
- `supabase/functions/analyze-chat/opener_prompt_test.ts`
- `test/unit/features/opener/data/services/opener_service_test.dart`
- `test/unit/features/opener/data/services/opener_result_cache_service_test.dart`

Expected behavior:

- Each new opener entry starts clean.
- Recent opener results are saved locally and explicitly viewable.
- Old result must not auto-appear for a new target.
- Handoff to "她回覆了，開始分析對話" should use the current opener draft.
- Guidance-only pioneer backup should not show multiple copy buttons.
- Raw JSON must never be displayed.
- Failed format repair should not charge quota when marked no-charge.

Known risks:

- Stale opener result from partner A appears while generating partner B.
- 502 "format abnormal" from AI.
- 429 mismatch with paid tier.
- User spends quota then loses result by pressing back.

Suggested tests:

- `flutter test test/unit/features/opener/data/services/opener_service_test.dart`
- `flutter test test/unit/features/opener/data/services/opener_result_cache_service_test.dart`

### Block 4: Analyze Chat / Reply Quality / Prompt Contract

Goal: analysis should read the real chat, identify catchable points, and produce useful strategy + examples. Five reply styles should not be generic summaries.

Primary files:

- `supabase/functions/analyze-chat/index.ts`
- `supabase/functions/analyze-chat/server_guardrails.ts`
- `supabase/functions/analyze-chat/server_guardrails_test.ts`
- `supabase/functions/analyze-chat/logger.ts`
- `lib/features/analysis/data/services/analysis_service.dart`
- `lib/features/analysis/domain/entities/analysis_result.dart`
- `lib/features/analysis/domain/entities/analysis_models.dart`
- `lib/features/analysis/presentation/screens/analysis_screen.dart`
- `lib/features/analysis/presentation/widgets/final_recommendation_card.dart`
- `test/unit/services/analysis_service_test.dart`
- `test/unit/entities/analysis_models_test.dart`

Quality expectations:

- Identify which message(s) are worth replying to.
- Sometimes reply as one message, sometimes split into multiple cited replies.
- Chinese question detection must distinguish real question vs frame trap / throwaway question.
- Use emoji sparingly when it adds tone.
- Keep 1.8x length law as guideline, not a blind truncation.
- Five styles should include practical "how to接" logic, not just direct copy text.

Known risks:

- AI recommends "extend" as always recommended.
- Five styles summarize the other person instead of creating a reply path.
- Raw JSON leaks into UI.
- Result history / deeper follow-up loses previous analysis context.

### Block 5: Coach 1:1 / Session State

Goal: Coach 1:1 should keep context, answer user intent, and ask clarifying questions when needed.

Primary files:

- `supabase/functions/coach-chat/prompts.ts`
- `supabase/functions/coach-chat/generation.ts`
- `supabase/functions/coach-chat/index.ts`
- `supabase/functions/coach-chat/schemas.ts`
- `lib/features/coach_chat/data/providers/coach_chat_providers.dart`
- `lib/features/coach_chat/data/services/coach_chat_api_service.dart`
- `lib/features/coach_chat/presentation/widgets/coach_chat_card.dart`
- `lib/features/coach_chat/domain/entities/coach_chat_result.dart`
- `lib/features/analysis/presentation/screens/analysis_screen.dart`
- `test/unit/features/coach_chat/data/providers/coach_chat_providers_test.dart`
- `test/unit/features/coach_chat/data/services/coach_chat_api_service_test.dart`
- `test/unit/features/coach_chat/data/repositories/coach_chat_repository_impl_test.dart`

Known risks:

- User asks, spinner runs, but result stays previous turn.
- Needs tapping/retrying two or three times before result appears.
- Coach does not receive preset question like "我該推進嗎？".
- Keyboard covers input or cannot dismiss.
- Multiple conversations under same partner may pollute context.

### Block 6: Analysis Page UX / Navigation / Keyboard / Learning Links

Goal: the page should feel like a coaching workspace, not a static report.

Primary files:

- `lib/features/analysis/presentation/screens/analysis_screen.dart`
- `lib/features/conversation/presentation/widgets/new_conversation_sheet.dart`
- `lib/features/learning/presentation/screens/learning_screen.dart`
- `lib/features/learning/presentation/screens/article_detail_screen.dart`
- `lib/app/routes.dart`
- `test/widget/features/analysis/analysis_screen_continue_input_test.dart`

Known risks:

- Keyboard hides active input.
- Back navigation leaves empty new conversations.
- "回首頁找真實對話練一次" routes back to Learning article page instead of home/new conversation.
- Bottom action hierarchy unclear.
- Collapsible report sections lose or hide important paid analysis.

### Block 7: Partner Memory / Merge / Storage / Privacy

Goal: same partner memory should help context without leaking across unrelated conversations or deleting data accidentally.

Primary files:

- `lib/features/partner/presentation/dialogs/partner_settings_dialog.dart`
- `lib/features/partner/data/repositories/partner_repository_impl.dart` if present
- `lib/features/analysis/data/services/partner_context_resolver.dart`
- `lib/features/coach_follow_up/domain/services/coach_follow_up_partner_hint_builder.dart`
- `lib/core/services/storage_service.dart`
- `test/unit/repositories/partner_repository_merge_test.dart`
- `test/unit/repositories/partner_repository_delete_test.dart`
- `test/unit/repositories/partner_repository_cascade_test.dart`
- `test/unit/services/storage_service_clear_all_test.dart`

Known risks:

- "立即合併" opens unnecessary picker instead of merging obvious same-name duplicate.
- Partner delete removes records with hidden 0-round conversations.
- Coach memory from conversation A over-influences clean conversation B.
- Opener drafts not associated clearly enough with partner/conversation.

### Block 8: App Review / Web / Legal

Goal: App Review should see a stable support/legal surface.

Primary files:

- `docs/app-review-final-checklist.md`
- `docs/launch-readiness-checklist.md`
- `docs/testflight-regression-checklist.md`
- separate repo: `C:/Users/eric1/OneDrive/Desktop/vibesync-web`

Recent web repo status:

- `vibesync-web` was moved out of VibeSync root into its own project.
- Latest web commit: `9977074 [docs] 更新官網產品與支援文案`
- Web now has `/support`, updated `/privacy`, updated `/terms`, and Blog content from remote commit `ada8aa0`.

Known risks:

- App Store support URL must open.
- Privacy/Terms must mention Coach 1:1, opener, screenshots/photo picker usage, subscription plans, and support email.
- Public repo exposure should be checked before switching private near launch.

## Bug Report Storage Rules

If CC fixes a bug:

1. Add or update an entry in `docs/bug-log.md`.
2. If Codex should review later, add a short handoff to `docs/reviews/ai-arbitration-queue.md` or create `docs/reviews/YYYY-MM-DD_<topic>_claude-handoff.md`.
3. Commit and push.
4. Include commit trailers:

```text
Reviewer-Hint: <what Codex should inspect, if anything>
Next-Step: <dogfood/test/review/deploy next action>
```

If CC only reviews and finds issues:

1. Write `docs/reviews/YYYY-MM-DD_<topic>_claude-review.md`.
2. Put findings first, ordered by severity.
3. For P0/P1, either patch directly if safe or mark `Needs-Codex-Review`.

## Do Not Do Without Eric / Codex Review

- Broad OCR rewrite
- Analyze-chat response schema change
- Subscription/paywall architecture rewrite
- Hive migration or destructive local data migration
- Large prompt rewrite without tests
- Anything that could charge quota incorrectly
- Anything that could downgrade paid users to Free
- Force push or history rewrite
