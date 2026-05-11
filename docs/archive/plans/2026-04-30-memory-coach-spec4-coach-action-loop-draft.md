# Memory Coach Spec 4: Coach Action Loop

> Status: roadmap draft, do not implement before Spec 1 unless explicitly pulled forward
> Date: 2026-04-30
> Depends on: Spec 1 / Spec 2A, ideally Spec 3 for memory trust
> Parent roadmap: `docs/plans/2026-04-30-vibesync-memory-coach-roadmap.md`

## 1. Goal

Spec 4 的目標，是把 VibeSync 從「分析報告」推進成「教練任務」。

使用者不應只看到：

```text
熱度高，可以推進
```

而應該看到：

```text
今天練模糊邀約
先丟一個低壓力活動方向，不急著約時間和地點。
```

核心轉換：

```text
analysis -> practice
```

## 2. Product Principle

VibeSync 不是隱形代聊 Cyrano，也不是操控對方的 PUA 工具。

Spec 4 的教練原則：

```text
Coach Action teaches low-pressure, honest next steps.
It must reduce anxiety, not create anxiety.
It must help the user practice, not replace the user.
```

中文產品語感：

```text
不是幫你演一個更厲害的人，而是陪你練會更自然的互動。
```

## 3. Action Taxonomy v1

### 3.1 Soft Invite / 模糊邀約

Use when:

- Heat is high.
- 對方有接球。
- 對話中有活動、地點、興趣、餐廳、展覽、咖啡等自然鉤子。

Purpose:

- 用低壓力方式測試見面意願。

Example:

```text
這間咖啡廳感覺你會喜歡，下次有機會一起去踩點。
```

### 3.2 Lower-Pressure Reply / 降壓回覆

Use when:

- 對方回覆變短。
- 對方冷卻。
- 使用者訊息太急或太滿。
- 使用者明顯焦慮。

Purpose:

- 降低壓迫感，讓互動回到舒服節奏。

Example:

```text
哈哈懂，那你先忙，改天再聽你分享。
```

### 3.3 Extend Topic / 延伸話題

Use when:

- Heat is medium.
- 有可延伸素材，但還不到邀約時機。
- 對方願意聊，但互動還沒升溫到可以推進。
- 使用者正在陷入問答模式，需要把問題改成更有畫面的分享。

Purpose:

- 讓對話自然多跑幾輪。
- 避免對話變成面試，改用「先給，再問」的故事框架。

Sub-action:

```text
storyFrame
```

Story frame structure:

1. Scene / 場景：具體時間、地點、事件。
2. Point / 觀點或情緒：你從這件事裡的感受、發現或想法。
3. Pivot / 開放式提問：把球踢給對方，讓她容易分享自己的故事。

Example:

```text
不要只問「你喜歡旅行嗎？」

可以改成：
我上次去京都，本來以為會照表操課，結果迷路走進一間阿嬤開的小咖啡店，反而變成整趟最有記憶點的地方。
所以我後來覺得旅行最好玩的常常是意外。
你比較像規劃派，還是隨興走走派？
```

### 3.4 Emotional Resonance / 情緒共鳴

Use when:

- 對方分享壓力、抱怨、失落、期待、生活事件。

Purpose:

- 先接住情緒，再決定是否建議或轉話題。

Example:

```text
聽起來你今天真的有點累，難怪會想放空一下。
```

### 3.5 Explain Less / 少解釋一點

Use when:

- 使用者訊息過長。
- 使用者補充太多。
- 使用者聽起來在辯解、防衛、過度證明自己。

Purpose:

- 讓回覆更輕、更自然，降低需求感。

### 3.6 Pause Pursuit / 暫停追問

Use when:

- Heat is low.
- 對方明顯冷淡。
- 對方轉移話題。
- 對方沒有接球。

Purpose:

- 避免把互動推壞。
- 紅燈狀態不給邀約建議。

## 4. Selection Policy

Action type should be selected by deterministic app-side policy first, then rendered by AI.

Reason:

- 任務選擇要穩定、可測。
- AI 可以負責自然文字，但不應每次自由決定策略。
- 這樣也方便綁定學習文章。

Suggested policy:

- Heat 80+: prefer `softInvite`, then `extendTopic`.
- Heat 55-79: prefer `extendTopic`, or `emotionalResonance` if emotional content is present.
- Heat 31-54: prefer `lowerPressureReply` or `explainLess`.
- Heat 0-30: prefer `pausePursuit`; never recommend an invite.

Spec 1 / 2A modifiers:

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
  "subType": null,
  "title": "今天練模糊邀約",
  "whyNow": "她有接住話題，而且互動熱度偏高，可以先用低壓力方式試探見面意願。",
  "instruction": "先提出一個活動方向，不急著約時間和地點。",
  "suggestedLine": "這間咖啡廳感覺你會喜歡，下次有機會一起去踩點。",
  "avoid": "不要馬上追問她哪天有空。",
  "followUpPrompt": "如果她回「好啊」，下一步再幫你轉成明確邀約。"
}
```

Story frame example:

```json
{
  "actionType": "extendTopic",
  "subType": "storyFrame",
  "title": "今天練故事框架",
  "whyNow": "你現在有話題可以接，但如果只一直問問題，對方容易覺得像被面試。",
  "instruction": "先分享一個小故事，再把問題自然丟回去。",
  "suggestedLine": "我上次去京都，本來以為會照表操課，結果迷路走進一間阿嬤開的小咖啡店，反而變成整趟最有記憶點的地方。你旅行比較像規劃派，還是隨興走走派？",
  "avoid": "不要連續問三個問題，也不要把故事講超過一分鐘。",
  "followUpPrompt": "挑一件你最近發生的小事，我可以幫你拆成場景 / 觀點 / 開放式提問。"
}
```

Fallback if schema is invalid:

```text
下一步建議
先用低壓力方式延續互動，不急著推進。
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

### Spec 4C: Learning Deep Link / 學習文章綁定

Spec 4C binds a Coach Action to one existing learning article or category.

Core idea:

```text
教練不只告訴你下一步，也告訴你如果想練這一步，該去哪裡學。
```

This belongs in Spec 4, not Spec 1 / 2 / 3.

Reason:

- Spec 4 owns coaching actions.
- Learning links are an extension of a specific action.
- The user receives advice, then can immediately learn the concept behind it.

## 7. Learning Deep Link Design

### 7.1 UI Placement

Inside Coach Action Card, below the main instruction:

```text
延伸學習
想練這一步？看 3 分鐘教學：模糊邀約
```

Interaction:

- Tap opens Learning tab article detail if exact article exists.
- If exact article does not exist, open the mapped category.
- Never block the main action.

### 7.2 Mapping Policy

Use deterministic app-side mapping.

Do not let AI freely choose arbitrary article titles.

Reason:

- Existing learning library has finite content.
- Free selection will hallucinate article names.
- Deterministic mapping is testable and stable.

Suggested mapping:

| `actionType` | Learning Category | Preferred Article |
|---|---|---|
| `softInvite` | 邀約策略 | 模糊邀約 |
| `lowerPressureReply` | 心態建設 / 訊息交流 | 降低壓迫感、不要追問 |
| `extendTopic` | 訊息交流 | 延伸話題、開放式提問 |
| `extendTopic.storyFrame` | 訊息交流 / 對話深度 | 故事框架代替問答 |
| `emotionalResonance` | 關係加溫 | 情緒共鳴、先接住感受 |
| `explainLess` | 訊息交流 | 少解釋一點、降低需求感 |
| `pausePursuit` | 心態建設 | 停止追問、尊重冷卻 |

If the exact article does not exist in the current 20 articles:

```text
fall back to category landing page
```

### 7.3 Data Contract

Suggested app-side model:

```dart
class LearningRecommendation {
  final String actionType;
  final String? subType;
  final String categoryId;
  final String? articleId;
  final String title;
  final String ctaLabel;
}
```

Example:

```dart
LearningRecommendation(
  actionType: 'softInvite',
  categoryId: 'invite_strategy',
  articleId: 'soft_invite',
  title: '模糊邀約',
  ctaLabel: '看 3 分鐘教學',
)
```

Story frame example:

```dart
LearningRecommendation(
  actionType: 'extendTopic',
  subType: 'storyFrame',
  categoryId: 'conversation_depth',
  articleId: 'story_frame',
  title: '故事框架代替問答',
  ctaLabel: '看 3 分鐘教學',
)
```

### 7.4 Interactive Practice Example

Learning link is passive. Coach Action can also invite one immediate practice.

For `extendTopic.storyFrame`:

```text
練習一下
挑一件你最近發生的小事，我幫你拆成：
1. 場景
2. 觀點或情緒
3. 開放式提問
```

This is still Spec 4B / 4C, not Spec 5.

Reason:

- It happens right after analysis.
- It is user-initiated.
- It does not require proactive reminder or push.

### 7.5 Non-Goals For 4C

Do not:

- Generate new article content.
- Rewrite the existing 20 articles.
- Let AI choose arbitrary article names.
- Add a full curriculum engine.
- Add progress tracking / course completion.
- Add push reminders for learning.

Spec 4C is a link bridge, not a learning platform rebuild.

## 8. Review Loop v1

Lightweight entry:

```text
對方回你了？
貼上她的回覆，我幫你判斷下一步。
```

Flow:

1. User receives Coach Action Card.
2. User reads optional learning link if needed.
3. User sends or adapts the suggested line.
4. Partner replies.
5. User returns and adds the next conversation.
6. VibeSync reviews response and suggests next action.

No completion tracking, push, or task streaks in v1.

## 9. Placement

v1 placement:

- Show Coach Action Card below the conversation analysis result.
- Learning link appears inside Coach Action Card.

Not v1:

- Home task center.
- PartnerDetail persistent task panel.
- Full Learning tab redesign.
- Learning progress dashboard.

Future:

- Learning tab can evolve into `My Practice`.
- It can show recommended lessons based on repeated Coach Actions.

## 10. Ethics / Tone Rules

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

## 11. Success Criteria

Dogfood questions:

- Do I understand what to do next?
- Do I understand why now?
- Does the suggested line sound like me?
- Did it help me avoid a common mistake?
- If I want to learn more, is there a clear article to read?
- Do I want to come back and paste the reply for review?

Early success metric:

```text
User feels they know the next step and has a clear learning path if they want to improve.
```

## 12. Tests

### Coach Action

- Heat 80+ maps to `softInvite` when positive signals exist.
- Heat 0-30 never maps to `softInvite`.
- Long user messages can map to `explainLess`.
- `blockedForAggregate` ignores partner memory.

### Learning Link

- `softInvite` maps to invite strategy article/category.
- `lowerPressureReply` maps to pressure / anxiety article/category.
- `pausePursuit` maps to stop chasing / cooldown article/category.
- Missing article falls back to category.
- Learning link tap opens correct Learning route.
- AI cannot inject arbitrary article title.

## 13. Non-Goals

- No push notifications.
- No external calendar / booking integrations.
- No automatic message sending.
- No manipulative PUA tactics.
- No full curriculum engine.
- No harsh scoring of the user.
- No rewriting the 20 learning articles inside this spec.

## 14. Recommended Scope

Ship in three phases:

1. Spec 4A: Coach Action Card UI upgrade.
2. Spec 4B: Structured Coach Action schema + policy + review loop.
3. Spec 4C: Learning Deep Link mapping from action type to article/category.

Do not bundle Spec 4B / 4C with Spec 1.
