# VibeSync Memory Coach Roadmap

> Status: product roadmap draft, updated after Eric/Codex discussion
> Date: 2026-04-30
> Purpose: align Claude / Codex / Eric / Bruce on the next memory-coach direction before implementation.

## 1. Positioning

VibeSync should not compete with ChatGPT / Gemini / Claude as a one-shot reply generator.

The stronger positioning is:

```text
VibeSync is a memory-based AI dating coach.
```

Defensible value:

- It remembers the user.
- It remembers each partner.
- It understands the current interaction.
- It turns abstract advice into one concrete practice step.
- It helps the user review what happened next.

In Chinese product language:

```text
不是只幫你回一句，而是陪你練會約會互動。
```

## 2. Five-Layer Model

| Layer | Product Meaning | Current State | Main Gap |
|---|---|---|---|
| 1. Conversation Analysis | Understand one conversation | OCR, heat, dimensions, suggestions mostly built | Tone still feels like report, not coach |
| 2. Partner Memory | Remember each person | Partner card, multi-record, aggregate memory | Mixed-person data can pollute memory |
| 3. User Growth | Remember the user | Almost absent | About Me / practice goals / user rhythm |
| 4. Coach Action | Turn analysis into practice | ScoreActionHint seed exists | Needs task card and review loop |
| 5. Proactive Coach | Pull user back at key moments | Not started | Progress nudge, pre-date prep, post-date review |

## 3. Current Product Risk

The largest risk is not visual polish. It is memory trust.

If a user puts different people's conversations into one Partner card, partner traits and long-term advice become polluted. Once this polluted memory enters coaching, the app may sound confident but be wrong.

Roadmap principle:

```text
Memory is valuable only if it is clean enough to trust.
```

## 4. Spec Map

### Spec 1: About Me / 關於我

File:

```text
docs/plans/2026-04-30-two-layer-profile-spec1-about-me-design.md
```

Scope:

- Add global user profile / About Me.
- Store interaction style, practice goals, topic seeds, notes.
- Place entry at top of `我的報告`.
- Clean up manual input page by removing `你的風格` and `你的興趣`.
- No AI prompt injection.
- No partner-specific override.
- No OCR / Edge changes.

Why:

```text
Spec 1 remembers the user, but does not yet let AI use that memory.
```

### Spec 2A: Prompt Fallback Chain

File:

```text
docs/plans/2026-04-30-memory-coach-spec2-prompt-fallback-chain-draft.md
```

Scope:

- Convert About Me into safe `userCoachingPreferences`.
- Inject only into normal analysis prompt.
- Do not affect OCR, heat, dimensions, partner traits, or evidence interpretation.
- Do not inject into `recognizeOnly`.

Why:

```text
Spec 2A makes advice sound more like the user's coach without changing factual analysis.
```

### Spec 2B: Partner Coaching Override

File:

```text
docs/plans/2026-04-30-memory-coach-spec2b-partner-coaching-override-draft.md
```

Scope:

- Add optional partner-specific coaching override.
- Entry from PartnerDetail.
- Priority: partner override > global About Me > generic.
- Allows a user to adjust style / practice goals only for one partner.
- No scoring changes.
- No OCR changes.

Why:

```text
Spec 2B handles the case where the user wants a different rhythm for a specific partner.
```

Important:

Spec 2B is not part of Spec 1 MVP. It should wait until Spec 2A prompt fallback is safe.

### Spec 3: Partner Data Quality Guard

File:

```text
docs/plans/2026-04-30-memory-coach-spec3-partner-data-quality-guard-draft.md
```

Scope:

- Detect possible mixed-person Partner cards.
- Warn users before trusting polluted aggregate memory.
- Fall back to current-conversation advice when needed.
- Use existing reassign flow first.

Why:

```text
Before coaching gets smarter, memory must be trustworthy.
```

### Spec 4: Coach Action Loop

File:

```text
docs/plans/2026-04-30-memory-coach-spec4-coach-action-loop-draft.md
```

Scope:

- Upgrade `ScoreActionHint` into concrete coaching tasks.
- Example tasks: soft invite, lower-pressure reply, extend topic, emotional validation, explain less, stop chasing.
- Add `extendTopic.storyFrame` as the learning/practice pattern for replacing Q&A mode with story framing.
- Split into UI-only 4A, structured schema 4B, and learning deep link 4C.
- Bind each coach action to one existing learning article or category.

Why:

```text
Advice should become practice, not just analysis.
```

Spec 4C note:

```text
Coach Action should not only say what to do next; it should point users to the lesson that teaches the concept.
```

Example:

```text
extendTopic.storyFrame -> 故事框架代替問答
Practice: pick a recent small life event and split it into Scene / Point / Pivot.
```

### Spec 5: Proactive Coach Loop

File:

```text
docs/plans/2026-04-30-memory-coach-spec5-proactive-coach-loop-draft.md
```

Scope:

- In-app progress nudge.
- Pre-date prep.
- Post-date review.
- No push notification in v1.

Why:

```text
This is the step from reactive tool to active coach, but only after memory is safe.
```

## 5. Execution Order

Recommended:

1. Spec 1: About Me + manual input cleanup.
2. Spec 2A: Global prompt fallback.
3. Spec 2B: Partner coaching override.
4. Spec 3: Partner data quality guard.
5. Spec 4A: Coach Action Card UI.
6. Spec 4B: Structured Coach Action.
7. Spec 4C: Learning deep link from Coach Action to article/category.
8. Spec 5A: In-app progress nudge.
9. Spec 5B/C: Pre-date prep and post-date review.

Possible swap:

- Spec 3 can move before Spec 2B if dogfood shows mixed-person contamination is frequent.
- Spec 4A can be inserted earlier because it can be UI-only and low risk.

## 6. Near-Term Recommendation

Next immediate task:

```text
Claude reviews Spec 1 -> writes implementation plan -> Codex reviews -> Claude executes.
```

Do not start Spec 2A / 2B / 3 / 4 / 5 yet.

Spec 1 implementation plan must include:

- UserProfile data model.
- Encrypted Hive storage.
- Report tab About Me card.
- About Me edit page.
- Manual input cleanup.
- Unit / provider / widget tests.

## 7. Explicit Boundaries

Do not:

- Mix OCR changes with memory-coach work.
- Let user profile affect scores or evidence interpretation.
- Add partner override inside Spec 1.
- Implement proactive reminders before app-internal trust is stable.
- Build calendar / restaurant / external booking agents.
- Make VibeSync a hidden Cyrano that replaces the user.
- Use photos to diagnose personality.

## 8. Domain Knowledge Principle

Dating-coach material can inspire product mechanics, but it is not automatically true.

Accepted:

- Soft invite as low-pressure test.
- Green / yellow / red response interpretation.
- Stage-based coaching.
- Photo/profile clues as conversation material only.

Rejected:

- Manipulative push-pull.
- Anxiety creation.
- Personality diagnosis from photos.
- Stalking / invasive OSINT.
- Hidden ghostwriter behavior.

Brand line:

```text
VibeSync should reduce anxiety and help users practice honest next steps.
```

## 9. One-Line Summary

VibeSync's next stage is not "more AI features." It is:

```text
clean memory -> safer personalization -> concrete practice -> gentle follow-up.
```
