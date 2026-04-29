# VibeSync Memory Coach Roadmap: Spec 1-5 Partner Handoff

> Audience: Bruce / Claude Code / Codex  
> Date: 2026-04-30  
> Purpose: readable summary of the product-positioning brainstorm and next execution path.

## Executive Summary

VibeSync should not position itself as a simple "help me reply" tool. General LLM apps can already produce a decent one-off reply when a user uploads a screenshot.

The stronger positioning is:

> VibeSync is a memory-based AI dating coach.

The defensible value is not just model quality. It is the product memory and coaching loop:

- It remembers the user.
- It remembers each partner.
- It understands the current interaction.
- It turns abstract advice into one concrete practice step.
- It helps the user review what happened next.

## Why This Matters

If VibeSync only generates better wording, users can replace it with ChatGPT / Gemini / Claude. If VibeSync remembers context, tracks partner history, knows what the user is practicing, and helps the user review progress, it becomes a coaching product rather than a reply box.

This reframes the app:

- From: "AI 幫我回一句"
- To: "AI 陪我練約會能力"

## Product Layer Model

| Layer | Meaning | Current State | Next Gap |
|---|---|---|---|
| 1. Conversation Analysis | Analyze one conversation | Mostly built: OCR, heat, five dimensions, suggestions | Tone still feels report-like |
| 2. Partner Memory | Remember each person | Partner card, multi-record, aggregate memory | Data quality guard for mixed people |
| 3. User Growth | Remember the user | Almost absent | About Me / practice goals |
| 4. Coach Action | Turn analysis into practice | First hint card exists | Structured coach task |
| 5. Proactive Coach | Pull user back at key moments | Not started | Progress nudge, pre-date prep, post-date review |

## The Main Risk

The near-term product risk is not visual polish. It is memory trust.

If conversations from different people are mixed into one Partner card, the AI will aggregate traits incorrectly. Once that polluted memory enters coaching advice, the product can sound confident but be wrong.

Therefore, the roadmap must build memory and memory-quality together.

## Spec 1: About Me / User Profile

Goal:

Let the app remember the user.

MVP:

- Add a `關於我` card at the top of `我的報告`.
- Let users choose interaction style, practice goals, topic seeds, custom topics, and optional notes.
- Keep it optional and editable.
- Store locally with encrypted Hive.
- Do not inject into AI prompts yet.

Product value:

- Opens the user growth layer.
- Lets future AI advice sound closer to the user's own rhythm.

Immediate next step:

Claude reviews Spec 1 and writes an implementation plan. Codex reviews before code.

## Spec 2: Prompt Fallback Chain

Goal:

Let AI advice safely use `關於我`.

Core rule:

```text
UserProfile can shape coaching, not scoring.
```

MVP:

- Convert profile into `userCoachingPreferences`.
- Inject a short `[User Coaching Preferences]` block only in normal analysis mode.
- Do not attach to OCR-only `recognizeOnly`.
- Do not attach to opener mode v1.
- Drop invalid profile data instead of failing analysis.

Must not affect:

- OCR.
- Heat score.
- Five-dimensional scores.
- Partner traits.
- Partner aggregate.

Risk:

Medium-high, because it touches `analyze-chat` prompt boundary. Requires Codex review and isolated Edge deploy.

## Spec 3: Partner Data Quality Guard

Goal:

Prevent mixed-person memory pollution.

MVP:

- Detect questionable partner data with deterministic heuristics.
- Show gentle PartnerDetail warning.
- Downgrade / hide long-term partner traits when data quality is blocked.
- Use existing reassign flow to fix misplaced records.

Example warning:

```text
這張卡可能混入不同人的聊天紀錄。整理後，整體分析才會更準。
```

Important principle:

AI can warn, but the user decides. Do not auto-move, auto-split, or claim certainty.

## Spec 4: Coach Action Loop

Goal:

Turn "analysis" into "practice".

MVP:

- Upgrade ScoreActionHint into Coach Action Card.
- Show one clear task after analysis.
- Example tasks:
  - 模糊邀約
  - 降壓回覆
  - 延伸話題
  - 情緒共鳴
  - 少解釋一點
  - 暫停追問

Example:

```text
今天練模糊邀約

現在互動熱度不錯，可以先丟一個低壓力邀約，不急著約時間。

「這間咖啡廳感覺你會喜歡，下次有機會一起去踩點。」
```

Split:

- Spec 4A: UI-only upgrade, no Edge schema change.
- Spec 4B: structured `coachAction` schema and review loop.

## Spec 5: Proactive Coach Loop

Goal:

Turn coaching into app-internal preparation, progress, and review.

Includes:

- Progress nudge after prior Coach Action.
- Pre-date preparation.
- Post-date reflection.
- Dormant conversation reminder.

Example:

```text
上次你準備用低壓方式邀約，後來她怎麼回？
```

Scope decision:

Spec 5 is roadmap only for now. Do not implement immediately.

No push notification in v1. Start with app-internal cards only.

## Domain Knowledge Principles

Use dating-coach material as inspiration, not truth.

Accepted:

- Soft invitation as a low-pressure way to test willingness.
- Green / yellow / red interpretation after an invite.
- Photos as observable conversation clues.
- Tasks that build user skill.

Rejected:

- Manipulative push-pull.
- Intentional anxiety creation.
- Personality diagnosis from photos.
- Stalking or invasive OSINT.
- Hidden Cyrano behavior.

Brand line:

> VibeSync teaches low-pressure, honest next steps. It should reduce anxiety, not create it.

## Recommended Execution Order

1. Spec 1: About Me / User Profile.
2. Spec 2: Prompt Fallback Chain.
3. Spec 3: Partner Data Quality Guard.
4. Spec 4A: Coach Action Card UI upgrade.
5. Spec 4B: Structured Coach Action Loop.
6. Spec 5A: In-app progress nudge.
7. Spec 5B/C: Pre-date prep and post-date reflection.

## What To Do Tomorrow

Do not start all specs at once.

Recommended next move:

```text
Claude reviews Spec 1 -> writes implementation plan -> Codex reviews -> Claude executes.
```

Spec 2-5 should stay as roadmap/design context until Spec 1 is planned cleanly.

## What Not To Do

- Do not mix OCR changes with profile / prompt / UI work.
- Do not let user profile change score or trait judgment.
- Do not build push reminders before app-internal reminders are validated.
- Do not build calendar / restaurant / booking agents.
- Do not implement all memory-coach specs in one PR.
