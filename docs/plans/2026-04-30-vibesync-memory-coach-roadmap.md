# VibeSync Memory Coach Roadmap

> Status: product direction checkpoint, pending detailed spec brainstorming
> Owner: Eric / Codex / Claude
> Date: 2026-04-30
> Purpose: record the shared product-positioning discussion before starting the next spec cycle. This file is meant as a clean handoff for future Claude Code / Codex sessions.

## 1. Positioning

VibeSync should not compete as a one-shot "help me reply" tool. ChatGPT, Gemini, and other general LLM apps can already do that when the user uploads a screenshot and asks for a reply.

The stronger position is:

> VibeSync is a memory-based AI dating coach.

The product should help users:

- Remember each partner and the interaction history with that partner.
- Understand what is happening in the current conversation.
- Practice the next concrete social move.
- Review patterns over time so the user becomes better, not just more dependent on AI.

This is closer to a learning / coaching product than a pure reply generator.

## 2. Four-Layer Product Model

| Layer | Current Completion | Already Exists | Missing / Next Gaps |
|---|---:|---|---|
| 1. Conversation Analysis | ~75% | Screenshot / manual input, OCR, heat score, 5 dimensions, partner traits, reply suggestions, first actionable hint card | Tone still feels like analysis report more than teacher; platform/source and conversation-context detection are rough |
| 2. Partner Memory | ~55% | Partner cards, partnerId chain, multiple interaction records, merge / reassign / delete, aggregated partner traits, partnerSummary injection | Biggest gap is data quality: detecting when conversations from different people are mixed into one partner; no structured memory yet for effective topics, red flags, platform transfer, heat trend |
| 3. User Growth | ~10-15% | Old sessionContext has traces of user style / goal, but not persistent long-term profile | No real "About Me", global user profile, personal mistakes, practice goals, or coach memory |
| 4. Coach Action | ~20% | ScoreActionHint surfaces nextStep / finalRecommendation | Not yet an active coach loop; no tasks, review, progress tracking, cooldown reminders, or post-date follow-up |

## 3. Core Risk

The biggest near-term product risk is not UI polish. It is memory trust.

Currently, partner traits are aggregated from all conversations under the same Partner card. If a user accidentally puts conversations from different people into one card, the long-term AI memory becomes polluted. That polluted memory can later produce wrong partner traits and wrong coaching advice.

Therefore, the next roadmap should not only make the AI "smarter". It must also make the memory more trustworthy.

## 4. Recommended Spec Split

### Spec 1: Two-Layer Profile / About Me

Goal: Let the app remember who the user is.

Scope:

- Add a global user profile: style, interests, practice goals, interaction preferences.
- Place the entry point in My Report, likely as a fixed top card named "About Me" / "關於我".
- Persist locally using the existing encrypted Hive storage pattern.
- Keep the first version intentionally small and editable.

Value:

- Opens Layer 3.
- Makes VibeSync feel like it understands the user, not only the partner.

### Spec 2: Prompt Fallback Chain

Goal: Make AI advice use memory without becoming a risky autonomous agent.

Scope:

- Resolve prompt context in this order:
  `partner override -> user profile -> generic coaching defaults`
- Inject resolved profile context into the analysis / reply prompt.
- Keep OCR and prompt changes isolated per existing OCR safety rules.
- Do not add proactive notifications, automatic follow-up, or complex agent behavior yet.

Value:

- Turns stored memory into actual personalization.
- Creates the foundation for "steady user gets steady wording, playful user gets playful wording".

### Spec 3: Partner Data Quality Guard

Goal: Protect partner memory from mixed-person contamination.

Scope:

- Detect when conversations under one partner card look like different people.
- Warn before injecting low-confidence aggregate partner memory into AI prompts.
- Provide a clear way to move / split wrongly placed interaction records.
- Treat this as a trust-boundary feature, not a cosmetic warning.

Value:

- Prevents wrong long-term memory from damaging the coaching layer.
- Makes partner cards safer as the product grows.

### Spec 4: Coach Action Loop v1

Goal: Move from analysis report to coaching practice.

Scope:

- Turn nextStep / finalRecommendation into concrete practice tasks.
- Examples: soft invitation, lower-pressure reply, stop over-explaining, keep reply under 20 words, ask one better follow-up.
- Later versions can add review, cooldown, post-date follow-up, and progress tracking.

Value:

- Makes users feel they are practicing and improving.
- Differentiates VibeSync from a generic AI reply box.

## 5. Recommended Build Order

1. Spec 1: Two-Layer Profile / About Me
2. Spec 2: Prompt Fallback Chain
3. Spec 3: Partner Data Quality Guard
4. Spec 4: Coach Action Loop v1

Spec 1 and Spec 2 can be brainstormed together, but should ship as separate PRs.

Spec 3 should be isolated because it touches the memory trust boundary.

Spec 4 should wait until profile + partner memory are usable, otherwise it risks becoming generic template advice.

## 6. Non-Goals For The Next Cycle

- Do not build restaurant booking, calendar scheduling, or external real-world agents.
- Do not turn the product into a hidden Cyrano that writes everything for the user.
- Do not over-expand into a fully proactive agent before memory quality is trustworthy.
- Do not mix OCR changes with unrelated prompt / profile / UI changes.
- Do not try to solve all four layers in one PR.

## 7. Spec 1 Brainstorm Starting Point

The next detailed brainstorm should answer these questions:

1. What exact fields belong in "About Me" v1?
2. Should the UI live only in My Report, or also be reachable from Settings?
3. How much should the user write manually versus choose from chips?
4. What is the minimum profile that creates real AI value without feeling like a long onboarding form?
5. Should profile setup be optional, recommended, or required before deeper analysis?
6. How should profile data be shown back to the user so it feels useful, not creepy?
7. What prompt wording can use the profile while preserving the 1.8x golden rule and heat strategy?

## 8. Working Hypothesis For Spec 1

Start small:

- A My Report top card: "關於我".
- Three editable sections:
  - 我的互動風格: chips such as 穩重 / 直接 / 幽默 / 溫柔 / 俏皮.
  - 我想練習: chips or short text such as 自然邀約 / 降低焦慮 / 幽默回覆 / 拉近距離 / 不過度解釋.
  - 我的補充說明: short free text, capped.
- First version is optional and editable anytime.
- The app should explain the value plainly: "這會讓 VibeSync 的建議更像你的節奏".

