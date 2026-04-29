# VibeSync Memory Coach Roadmap

> Status: product direction locked for next planning cycle  
> Owner: Eric / Codex / Claude  
> Date: 2026-04-30  
> Purpose: record the shared positioning and Spec 1-5 roadmap before implementation planning. This file is the main handoff index for future Claude Code / Codex sessions.

## 1. Positioning

VibeSync should not compete as a one-shot "help me reply" tool. ChatGPT, Gemini, Claude, and other general LLM apps can already answer that use case when a user uploads a screenshot and asks for a reply.

The stronger position is:

> VibeSync is a memory-based AI dating coach.

The product should help users:

- Remember each partner and the interaction history with that partner.
- Understand what is happening in the current conversation.
- Practice one concrete next move.
- Review patterns over time so the user becomes better, not just more dependent on AI.

This is closer to a learning / coaching product than a pure reply generator.

## 2. Product Layers

| Layer | Current Completion | Already Exists | Missing / Next Gaps |
|---|---:|---|---|
| 1. Conversation Analysis | ~75% | Screenshot / manual input, OCR, heat score, five dimensions, partner traits, reply suggestions, first actionable hint card | Tone still feels like an analysis report more than a coach; platform/source and conversation-context detection are still rough |
| 2. Partner Memory | ~55% | Partner cards, partnerId chain, multiple interaction records, merge / reassign / delete, aggregated partner traits, partnerSummary injection | Biggest gap is data quality: detecting when conversations from different people are mixed into one partner; no structured memory yet for effective topics, red flags, platform transfer, heat trend |
| 3. User Growth | ~10-15% | Old sessionContext has traces of user style / goal, but not persistent long-term profile | No real "About Me", global user profile, personal mistake patterns, practice goals, or coach memory |
| 4. Coach Action | ~20% | ScoreActionHint surfaces nextStep / finalRecommendation | Not yet an active coach loop; no task framing, review loop, progress tracking, cooldown reminders, or post-date follow-up |
| 5. Proactive Coach | 0% | None | No app-internal progress nudge, pre-date prep, post-date reflection, or opt-in reminders |

## 3. Core Risk

The biggest near-term product risk is memory trust, not UI polish.

Partner traits are aggregated from conversations under the same Partner card. If a user accidentally puts conversations from different people into one card, the long-term AI memory becomes polluted. That polluted memory can later produce wrong partner traits and wrong coaching advice.

Therefore the roadmap should not only make AI "smarter". It must make memory more trustworthy.

## 4. Spec Split

### Spec 1: About Me / User Profile

Goal: let the app remember who the user is.

Scope:

- Add a lightweight global user profile in the Report tab.
- Capture interaction style, practice goals, topic seeds, custom topics, and optional notes.
- Persist locally using existing encrypted Hive patterns.
- Keep the flow optional, editable, and completable in about 30 seconds.
- Do not inject this profile into AI prompts yet.

Value:

- Opens Layer 3: user growth.
- Makes VibeSync feel like it remembers the user, not only each partner.

Status:

- Design draft exists: `docs/plans/2026-04-30-two-layer-profile-spec1-about-me-design.md`
- Next action: Claude reviews Spec 1 and writes an implementation plan. Codex reviews before execution.

### Spec 2: Prompt Fallback Chain

Goal: let AI advice use the user's profile safely.

Scope:

- Convert `UserProfile` into a validated `userCoachingPreferences` payload.
- Inject a short `[User Coaching Preferences]` prompt block only for normal analysis mode.
- Use profile only to adapt coaching tone, examples, and practice focus.
- Never let profile affect OCR, heat score, five dimensions, partner traits, or evidence interpretation.
- Omit the block completely when no profile exists.
- Drop invalid / oversized profile input instead of failing analysis.

Value:

- Turns stored memory into actual personalization.
- Creates the foundation for "steady user gets steady wording, playful user gets playful wording".

Status:

- Design draft exists: `docs/plans/2026-04-30-memory-coach-spec2-prompt-fallback-chain-draft.md`
- High-risk boundary: touches `analyze-chat`; must be independently reviewed and deployed.

### Spec 3: Partner Data Quality Guard

Goal: protect partner memory from mixed-person contamination.

Scope:

- Detect when conversations under one partner card look like different people.
- Surface a gentle PartnerDetail warning when data is questionable.
- Downgrade or block partner-level aggregate claims when memory is not trusted.
- Provide clear recovery through existing reassign flow.
- Use deterministic heuristic v1; no LLM identity resolver.

Value:

- Prevents wrong long-term memory from damaging the coaching layer.
- Makes partner cards safer as the product grows.

Status:

- Design draft exists: `docs/plans/2026-04-30-memory-coach-spec3-partner-data-quality-guard-draft.md`
- Should ship before structured Coach Action relies heavily on partner aggregate memory.

### Spec 4: Coach Action Loop

Goal: move from analysis report to coaching practice.

Scope:

- Upgrade ScoreActionHint into a Coach Action Card.
- Define a small action taxonomy: soft invite, lower-pressure reply, extend topic, emotional resonance, explain less, pause pursuit.
- Use app-side policy to select action type; AI can render natural content later.
- Add a lightweight review loop entry: "Did they reply? Paste it back and I will help with the next step."

Value:

- Makes users feel they are practicing and improving.
- Differentiates VibeSync from a generic AI reply box.

Status:

- Design draft exists: `docs/plans/2026-04-30-memory-coach-spec4-coach-action-loop-draft.md`
- Can split into 4A UI-only upgrade and 4B structured schema.

### Spec 5: Proactive Coach Loop

Goal: turn one-off coaching into app-internal preparation, progress, and review.

Scope:

- App-internal progress nudge after a previous Coach Action.
- Manual "date planned" marker and pre-date prep.
- Post-date reflection prompt.
- Dormant conversation / cooldown reminder.
- No push notification in v1; future push must be opt-in and privacy-safe.

Value:

- Creates the second-layer coach experience: VibeSync remembers what the user was trying to practice and pulls them back at the right moment.
- Extends value beyond "reply generation" into relationship learning.

Status:

- Roadmap draft exists: `docs/plans/2026-04-30-memory-coach-spec5-proactive-coach-loop-draft.md`
- Not for immediate implementation. Keep in roadmap until Spec 1-4 are stable.

## 5. Recommended Build Order

1. Spec 1: About Me / User Profile
2. Spec 2: Prompt Fallback Chain
3. Spec 3: Partner Data Quality Guard
4. Spec 4A: Coach Action Card UI upgrade
5. Spec 4B: Structured Coach Action Loop
6. Spec 5A: In-app progress nudge
7. Spec 5B/C: Pre-date prep and post-date reflection

Spec 1 and Spec 2 can be discussed together, but must ship as separate PRs.

Spec 3 should be isolated because it touches the memory trust boundary.

Spec 4A can be inserted earlier if dogfood needs a stronger coaching feel without touching Edge schema.

Spec 5 should stay in roadmap until the memory and task layers are stable.

## 6. Domain Knowledge Rules

Use domain material as inspiration, not truth. The team explicitly caught a Gemini article where push/pull was written backwards, so all coaching content must be filtered through evidence and product ethics.

Accepted:

- Soft invitation as a low-pressure, consent-respecting way to test willingness.
- Green / yellow / red interpretation after a soft invite.
- Photo / profile clues as conversation material only.
- Learning tasks that help the user become more capable.

Rejected:

- Manipulative push-pull / intermittent reinforcement tactics.
- Personality diagnosis from photos.
- Stalking or invasive OSINT.
- Hidden Cyrano behavior where the product replaces the user's agency.
- Advice that creates anxiety or dependency.

Brand line:

> VibeSync should teach low-pressure, honest next steps. It must not create anxiety, dependency, or manipulative tactics.

## 7. Non-Goals For The Next Cycle

- Do not build restaurant booking, calendar scheduling, or external real-world agents.
- Do not turn the product into a hidden Cyrano that writes everything for the user.
- Do not over-expand into a fully proactive agent before memory quality is trustworthy.
- Do not mix OCR changes with unrelated prompt / profile / UI changes.
- Do not try to solve all five specs in one PR.
- Do not use user profile to change heat score, five-dimensional scores, partner traits, or OCR behavior.

## 8. Immediate Next Step

The next executable step is:

> Claude reviews Spec 1 and writes a focused implementation plan. Codex reviews that plan before code is written.

Do not start Spec 2-5 implementation until Spec 1 is reviewed and planned.
