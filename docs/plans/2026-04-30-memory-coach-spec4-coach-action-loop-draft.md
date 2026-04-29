# Memory Coach Spec 4: Coach Action Loop

> Status: brainstorm locked, implementation should be split into 4A / 4B  
> Date: 2026-04-30  
> Depends on: Spec 1 / Spec 2, and ideally Spec 3  
> Parent roadmap: `docs/plans/2026-04-30-vibesync-memory-coach-roadmap.md`

## 1. Goal

Turn VibeSync from an analysis report into a coaching loop.

The user should not only see:

```text
互動熱度高，可以推進
```

They should receive one concrete practice step:

```text
今天練模糊邀約
先提出一個活動方向，不急著約時間和地點。
```

## 2. Product Principle

VibeSync is not a hidden Cyrano. It should not replace the user's agency.

It should teach low-pressure, honest next steps:

```text
Coach Action teaches low-pressure, honest next steps.
It must not create anxiety, dependency, or manipulative tactics.
```

## 3. Action Taxonomy v1

### 3.1 Soft Invite

Use when:

- Heat is high.
- Partner has been responding positively.
- There is a natural activity / place / interest hook.

Purpose:

- Test willingness with low pressure.

Example:

```text
這間咖啡廳感覺你會喜歡，下次有機會一起去踩點。
```

### 3.2 Lower-Pressure Reply

Use when:

- Partner response becomes shorter.
- User sounds anxious.
- Pressure is rising.

Purpose:

- Restore comfort; avoid chasing.

Example:

```text
哈哈沒事，忙完再說。
```

### 3.3 Extend Topic

Use when:

- Heat is medium.
- There is topic material but not enough momentum for invite.

Purpose:

- Let conversation run naturally for a few more rounds.

### 3.4 Emotional Resonance

Use when:

- Partner shares feelings, stress, complaint, or life event.

Purpose:

- Receive emotion before solving the problem.

Example:

```text
聽起來你今天真的被消耗到。
```

### 3.5 Explain Less

Use when:

- User reply is too long.
- User over-justifies or sounds defensive.

Purpose:

- Keep reply lighter and less pressuring.

### 3.6 Pause Pursuit

Use when:

- Heat is low.
- Partner is cold, evasive, or clearly redirecting.

Purpose:

- Avoid pushing too hard.
- No invite suggestion under red-light conditions.

## 4. Selection Policy

Action type should be selected by deterministic app-side policy first, then rendered by AI.

Suggested policy:

- Heat 80+: prefer `softInvite`, then `extendTopic`.
- Heat 55-79: prefer `extendTopic`, or `emotionalResonance` if emotional content is present.
- Heat 31-54: prefer `lowerPressureReply` or `explainLess`.
- Heat 0-30: prefer `pausePursuit`; never recommend an invite.

Spec 1 / 2 modifiers:

- If practice goal includes `自然邀約`, high-heat cases can prioritize `softInvite`.
- If practice goal includes `降低焦慮`, low-heat cases can prioritize `lowerPressureReply` / `pausePursuit`.
- If practice goal includes `少解釋一點`, long user messages can prioritize `explainLess`.

Spec 3 modifier:

- If partner data quality is `blockedForAggregate`, action must rely only on the current conversation.

## 5. Coach Action Schema v2

Future structured response:

```json
{
  "actionType": "softInvite",
  "title": "今天練模糊邀約",
  "whyNow": "她有接住話題，而且互動熱度偏高，可以先用低壓力方式試探見面意願。",
  "instruction": "先提出一個活動方向，不急著約時間和地點。",
  "suggestedLine": "這間咖啡廳感覺你會喜歡，下次有機會一起去踩點。",
  "avoid": "不要馬上追問她哪天有空。",
  "followUpPrompt": "如果她回「好啊」，下一步再幫你轉成明確邀約。"
}
```

Fallback if schema is invalid:

```text
下一步建議
先用低壓力方式延續對話，不急著推進。
```

## 6. Relationship To ScoreActionHint

Do not show two competing cards.

Coach Action Card should replace or upgrade `ScoreActionHint`.

### Spec 4A: UI-Only Upgrade

- Keep existing `gameStage.nextStep` and `finalRecommendation`.
- Keep existing low-heat anti-invite guard.
- Repackage as a more coach-like card.
- No Edge schema change.
- No OCR change.

### Spec 4B: Structured Coach Action Loop

- Add optional `coachAction` schema.
- App-side policy decides `actionType`.
- AI renders natural card content.
- Legacy fields remain fallback.

## 7. Review Loop v1

Lightweight entry:

```text
對方回你了？
貼上她的回覆，我幫你判斷下一步。
```

Flow:

1. User receives Coach Action Card.
2. User sends or adapts the suggested line.
3. Partner replies.
4. User returns and adds the next conversation.
5. VibeSync reviews response and suggests next action.

No completion tracking, push, or task streaks in v1.

## 8. Placement

v1 placement:

- Show Coach Action Card below the conversation analysis result.

Not v1:

- Home task center.
- PartnerDetail persistent task panel.
- Learning tab deep link.

Future:

- Learning tab can evolve into "My Practice" and map `actionType` to short lessons.

## 9. Ethics / Tone Rules

Required:

- Do not teach cold violence, deliberate disappearance, or anxiety creation.
- Do not guarantee outcomes.
- Respect rejection.
- Strengthen user skill, not dependency.
- Keep advice honest and aligned with the user's own voice.

Healthy soft invite is allowed.

Manipulative push-pull / intermittent reinforcement is rejected.

Photo/profile analysis rule:

```text
Photos provide conversation clues, not personality diagnosis.
```

## 10. Success Criteria

Dogfood questions:

- Do I understand what to do next?
- Do I understand why now?
- Does the suggested line sound like me?
- Did it help me avoid a common mistake?
- Do I want to come back and paste the reply for review?

Early success metric:

```text
User feels they know the next step and wants to come back for review.
```

## 11. Non-Goals

- No push notifications.
- No external calendar / booking integrations.
- No automatic message sending.
- No manipulative PUA tactics.
- No full curriculum engine.
- No harsh scoring of the user.

## 12. Recommended Scope

Ship in two phases:

1. Spec 4A: Coach Action Card UI upgrade.
2. Spec 4B: Structured Coach Action schema + policy + review loop.

Do not bundle Spec 4B with Spec 1-3.
