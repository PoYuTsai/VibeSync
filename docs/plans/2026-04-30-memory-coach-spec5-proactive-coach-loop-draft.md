# Memory Coach Spec 5: Relationship Rhythm & Mindset Coach

> Status: roadmap draft, not for immediate implementation  
> Date: 2026-04-30  
> Updated: 2026-05-01 after Eric/Codex discussion on post-date, intimacy-aftercare, short-term relationship maintenance, and mindset management  
> Depends on: Spec 1-4  
> Parent roadmap: `docs/plans/2026-04-30-vibesync-memory-coach-roadmap.md`

## 1. Goal

Turn VibeSync from a tool the user opens after every screenshot into a coach that helps the user manage relationship rhythm, expectations, and mindset at key moments.

Core idea:

```text
VibeSync 不只是分析你貼進來的聊天，而是在關係推進的關鍵時刻，把你拉回穩定、誠實、有界線的狀態。
```

Spec 5 should acknowledge the real entry motivation many young male users have:

```text
想約出來、想升溫、想親密，是很多人的真實起點。
```

But the product must not stop at "how to close more." The higher-value coaching path is:

```text
入口動機：我想推進、想見面、想親密。
真正價值：我更懂自己、懂對方、懂節奏、懂界線，也知道自己要什麼、不要什麼。
```

Internal positioning line:

```text
VibeSync 不羞辱你的慾望，但也不讓你被慾望牽著走。
```

External product tone should use cleaner language:

- 關係推進
- 見面後復盤
- 親密後節奏
- 界線與承諾
- 暈船降溫
- 篩選與自我價值

## 2. Scope

Spec 5 includes:

- Progress nudge after a prior Coach Action.
- Pre-date preparation.
- Post-date reflection.
- Intimacy-aftercare / close-after rhythm management.
- Short-term relationship maintenance.
- Relationship expectation, boundary, and mindset management.
- Dormant conversation / cooldown reminder.
- Future opt-in push notification.

Spec 5 should not be implemented before Spec 1-4 are stable.

Core coaching stance:

```text
不是每段關係都要走向交往，但每段互動都應該讓使用者更懂自己、更有界線、更有選擇力。
```

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

### Spec 5D: Intimacy-Aftercare / Close-After Rhythm

Trigger:

- User manually marks `有親密接觸`.
- User mentions relationship-definition pressure, guilt, anxiety, over-commitment, or wanting to send a long emotional message after intimacy.
- User asks how to answer questions such as `你會對我負責嗎？`.

Purpose:

```text
親密發生後，幫使用者不逃避、不亂承諾、不焦慮控制，也不把對方物化成攻略結果。
```

Coach principles:

- 不逃避責任。
- 不亂給承諾。
- 不用承諾換親密。
- 不情緒勒索。
- 不急著控制對方。
- 不把親密當成綁定對方的籌碼。

Example coaching output:

```text
你現在不缺一句更漂亮的話，而是要先穩住自己的節奏。

可以這樣拆：
1. 接住對方的感受。
2. 說清楚你的態度。
3. 不急著用壓力定義彼此。

範例：
我不會敷衍你，也不會把昨晚當沒事。
我對你是有好感的，也想繼續認識你。
但我希望我們不要因為一晚就急著用壓力定義彼此，慢慢看彼此是不是真的適合，好嗎？
```

Avoid:

- 教使用者裝冷淡。
- 教使用者用話術逃避責任。
- 教使用者用承諾綁住對方。
- 使用 `收割 / 控住 / 壞女人 / 玩咖 / 高分妹` 這類物化或攻擊語言。

Internal note:

`close / 收尾 / 親密後` can appear in internal specs, but user-facing UI should prefer `親密後節奏` or `關係升溫後`.

### Spec 5E: Short-Term Relationship Maintenance

Trigger:

- User says they are not sure whether they want a serious relationship.
- Relationship is casual, undefined, or "seeing each other."
- User wants to keep meeting without over-promising.
- One side wants stability while the other wants freedom.

Purpose:

```text
如果不是立刻走長期關係，也要保持誠實、尊重、輕鬆、不過度承諾，並保護自己的界線。
```

Common states:

- 曖昧中。
- 偶爾見面。
- 短期互動。
- 還在觀察。
- 親密但未定義。
- 一方想穩定，一方想自由。

Coach asks:

```text
你現在比較像哪一種狀態？

A. 想繼續輕鬆認識
B. 想推進成穩定關係
C. 親密後有點焦慮
D. 對方變冷，我開始患得患失
E. 我其實不確定自己要什麼
```

Output should help the user manage:

1. 期待管理  
   我是不是想太快？是不是把對方的回覆過度解讀？

2. 邊界管理  
   我有沒有用承諾換親密？有沒有讓對方誤會？有沒有忽略自己的底線？

3. 心態管理  
   我是不是暈船、焦慮、想控制、怕失去，或只是被外型和刺激感帶著走？

### Spec 5F: Relationship Fit / Selection Reflection

Trigger:

- User asks whether the other person is worth continuing.
- User notices mismatched values, unclear intent, entitlement, disrespect, unstable communication, or incompatible life goals.
- User is anxious because the other person is attractive or high-status.

Purpose:

```text
幫使用者判斷自己要什麼、不要什麼，而不是只追求把關係推進。
```

Important:

- Do not label the partner with insults or diagnoses.
- Focus on observable behavior.
- Help the user separate attraction, ego, scarcity, and actual fit.

Example output:

```text
先不要急著判斷她是什麼樣的人。
我們先看三件事：
1. 她有沒有尊重你的時間？
2. 她有沒有穩定接球？
3. 你跟她相處後，是更放鬆，還是更焦慮？
```

### Spec 5G: Push Notification

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
- `intimacyMarked`
- `relationshipStatusChecked`
- `reflectionSubmitted`
- `conversationDormant`

The purpose is to represent:

```text
上次建議 -> 使用者是否行動 -> 對方反應 -> 使用者心態 -> 下一步
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
- User is anxious after intimacy -> recommend `親密後節奏`.
- User keeps over-investing in unclear relationships -> recommend `期待與界線管理`.

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
- No "how to control her after close" framing.
- No red-pill / PUA / demeaning labels in user-facing copy.
- No moralizing the user's desire. Coach it into clarity and responsibility.

## 10. Recommended Timing

Do not implement Spec 5 now.

Suggested order:

1. Finish Spec 1.
2. Finish Spec 2.
3. Finish Spec 3.
4. Ship Spec 4A / 4B.
5. Revisit Spec 5A app-internal nudge.

Spec 5 is the future "relationship rhythm and mindset coach" layer, not the next build.

## 11. Current Parking Lot (2026-05-01)

These are product notes captured from Eric/Codex discussion. They are not implementation-ready.

### 11.1 Real User Motivation

We should not pretend every user comes in with a polished "healthy relationship" mindset.

For many young male users, the honest starting point is:

```text
我想約出來。
我想升溫。
我想親密。
我想知道怎麼不要搞砸。
```

VibeSync should meet that reality without becoming a low-level manipulation product.

### 11.2 Mature Product Transformation

The product should transform:

```text
怎麼收更多
```

into:

```text
怎麼更懂自己、更會互動、更能篩選，也更能承擔自己的選擇。
```

This is the difference between a reply generator and a real coach.

### 11.3 Spec 4 vs Spec 5 Boundary

Spec 4 handles:

```text
這一輪訊息，今天練哪一個互動能力？
```

Spec 5 handles:

```text
這段關係現在走到哪？我的心態穩不穩？下一步要不要推進、維持、降溫，或停止？
```
