# Memory Coach Spec 5: Proactive Coach Loop

> Status: roadmap draft, not for immediate implementation  
> Date: 2026-04-30  
> Depends on: Spec 1-4  
> Parent roadmap: `docs/plans/2026-04-30-vibesync-memory-coach-roadmap.md`

## 1. Goal

Turn VibeSync from a tool the user opens after every screenshot into a coach that can pull the user back at key relationship moments.

Core idea:

```text
VibeSync 不只是分析你貼進來的聊天，而是在關係推進的關鍵時刻，把你拉回來準備、行動、復盤。
```

## 2. Scope

Spec 5 includes:

- Progress nudge after a prior Coach Action.
- Pre-date preparation.
- Post-date reflection.
- Dormant conversation / cooldown reminder.
- Future opt-in push notification.

Spec 5 should not be implemented before Spec 1-4 are stable.

## 3. Sub-Specs

### Spec 5A: In-App Progress Nudge

Trigger:

- User previously received a Coach Action.
- Some time passes without a new conversation update.

Example:

```text
上次你準備用低壓方式邀約，後來她怎麼回？
```

Channel:

- App-internal card only.
- No push notification in v1.

### Spec 5B: Date Planned / Pre-Date Prep

Trigger:

- User manually taps `已約好見面`.
- Optional fields: time, place/activity, concern.

Example:

```text
見面前小提醒

今晚先不用想太多，目標不是表現完美，而是看彼此相處舒服不舒服。

這次練三件事：
1. 少一點面試感
2. 多接她的情緒
3. 準備一個輕鬆話題
```

### Spec 5C: Post-Date Reflection

Trigger:

- Date time passes, or user manually marks date completed.

Questions:

- `你覺得整體氣氛如何？`
- `對方有沒有主動延續話題？`
- `你有沒有哪裡想下次做得更好？`

Output:

```text
這次復盤

你做得好的地方：
...

下次可以練：
...

下一步建議：
...
```

### Spec 5D: Push Notification

Future only.

Push must be:

- Opt-in.
- Privacy-safe.
- Low frequency.
- Never anxiety-creating.

Do not ship push in Spec 5 v1.

## 4. Event Model

Future shared event language:

```text
CoachEvent
```

Types:

- `coachActionSuggested`
- `coachActionApplied`
- `replyReceived`
- `datePlanned`
- `dateCompleted`
- `reflectionSubmitted`
- `conversationDormant`

The purpose is to represent:

```text
上次建議 -> 使用者是否行動 -> 對方反應 -> 下一步
```

## 5. Reminder Channels

Priority:

1. App-internal card.
2. Badge / small dot.
3. Push notification.

v1:

- Use app-internal cards only.

Reason:

- Push can easily feel invasive.
- Dating-related reminders are sensitive.
- Product tone must be validated before external notifications.

## 6. Frequency Rules

Suggested hard limits:

- Max one proactive reminder per day.
- Same partner should not be nudged more than once in 48 hours.
- Low heat / red-light cases must not encourage pursuit.
- If user skips a reminder repeatedly, lower future frequency.
- Every reminder type must be dismissible.

Tone rule:

```text
主動教練要降低焦慮，而不是製造焦慮。
```

## 7. Privacy Rules

Spec 5 may store sensitive information:

- Date time.
- Date place/activity.
- User concern.
- Post-date feelings.
- Partner reaction.
- User self-reflection.

Rules:

- Store locally by default.
- Send only the minimum necessary text to AI.
- Allow deletion of each date event / reflection.
- Future push must not reveal partner name or private context.

Privacy-safe push example:

```text
VibeSync 有一個小提醒
```

Avoid:

```text
今晚跟 Candy 約會，記得不要太急
```

## 8. Learning Tab Relationship

Spec 5 can eventually turn Learning from a static article library into a personal practice plan.

Examples:

- User often over-explains -> recommend `20 字內回覆`.
- User has high heat but avoids inviting -> recommend `模糊邀約`.
- User completed a date -> recommend `見面後的第一則訊息`.

Future direction:

```text
學習專區 -> 我的練習
```

Not v1.

## 9. Non-Goals

- No push notification in v1.
- No calendar integration.
- No restaurant booking.
- No automatic message sending.
- No surveillance-like reminders.
- No reminder that pressures the user to chase.

## 10. Recommended Timing

Do not implement Spec 5 now.

Suggested order:

1. Finish Spec 1.
2. Finish Spec 2.
3. Finish Spec 3.
4. Ship Spec 4A / 4B.
5. Revisit Spec 5A app-internal nudge.

Spec 5 is the future "proactive coach" layer, not the next build.
