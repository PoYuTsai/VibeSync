# Spec 6 Coach 1:1 Smoke Cases

> Last updated: 2026-05-07
> Purpose: make the "有記憶的 AI 約會教練" positioning testable during TestFlight and agent reviews.

## Automated Check

Run:

```bash
deno test --allow-env supabase/functions/coach-chat/quality_smoke_test.ts
```

This verifies the prompt contract still covers Spec 6's core promise: use memory, converge judgment, ask only when needed, preserve the user's voice, and respect boundaries.

## Manual Test Pass Criteria

Each Coach 1:1 answer should pass all five:

- It names or clearly uses at least one concrete basis from the current context, such as the other person's line, heat/stage, summary, user style, or trusted partner hint.
- It gives one working judgment and one smallest next step instead of handing the user a menu of options.
- It asks one clarifying/reflection question only when the user's feeling, goal, draft, or cost tolerance is missing.
- It keeps the user's real voice when polishing a draft, using `keep_original` or `light_edit` when the draft is already good.
- It states boundary/cost clearly when there is a partner, pressure, sexual tension, or unclear intent.

## Smoke Scenarios

### 1. Line Meaning

User asks: `她說我很有故事是什麼意思？`

Context: partner said `你感覺是個很有故事的人`; latest analysis says heat around 60-70 and stage is warming.

Expected:

- Coach gives at most two possible meanings, then chooses one working read.
- Coach references the actual line or stage signal naturally.
- Coach suggests one reply or one observation, not a list of strategies.

### 2. Invite Anxiety

User asks: `我想約她，但怕太急，怎麼問？`

Context: partner opened a lifestyle window such as `最近工作有點累，想找地方放空`.

Expected:

- If intent/cost is unclear, Coach asks one free clarification.
- If enough context exists, Coach gives one low-pressure invitation.
- Coach does not push a high-commitment date when the signal is weak.

### 3. Draft Polish

User asks: `我有想說的，幫我優化`

Draft: `其實我也想見你，但我怕太突然哈哈`

Expected:

- Coach explains whether to keep, lightly edit, rewrite, or not send.
- Coach preserves sincerity and short natural phrasing.
- Coach does not turn the draft into generic dating-script language.

### 4. Data Quality Flagged

User asks: `她是不是對我沒興趣？`

Context: partner profile is flagged unreliable; only current conversation should be trusted.

Expected:

- Coach says the judgment is based on this conversation only.
- Coach does not cite long-term traits, memory, or profile facts.
- Coach uses reflection if the user's emotional goal is unclear.

### 5. Attached Partner

User asks: `她有男友還約我單獨喝酒，我要去嗎？`

Expected:

- Coach distinguishes friend invite, flirtation, emotional vacancy, and boundary ambiguity without labeling the other person.
- Coach asks what role the user is willing to stand in, or gives one boundary-safe next step.
- Coach makes time cost and emotional cost explicit.
