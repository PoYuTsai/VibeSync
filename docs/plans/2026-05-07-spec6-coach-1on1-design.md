# Spec 6 - Coach 1:1 / Coach-first Product Architecture Design

> Status: design draft
> Date: 2026-05-07
> Scope: product architecture + Spec 6 phased design. No implementation plan yet.
> Authors: Eric + Codex
> Depends on: Spec 1 About Me, Spec 2 Partner Style, Spec 2.5 Memory-to-Prompt Contract, Spec 3 Data Quality Guard, Spec 4 Coach Action Card, Spec 5 Coach Follow-up

---

## 0. Executive Summary

Spec 6 moves VibeSync from an AI analysis/reporting tool toward a coach-first product.

The product should no longer feel like:

> Here is a report about your conversation.

It should feel like:

> I looked at this interaction. Here is what matters, here is your next step, and if you are stuck, ask the coach directly.

Spec 1-5 are not replaced. They become the context layer that makes Coach 1:1 more useful than asking a general LLM manually.

- Spec 1 About Me: who the user is, how they want to show up.
- Spec 2 Partner Style: how the user wants to adapt toward a specific partner.
- Spec 2.5 Memory-to-Prompt Contract: how memory/settings actually alter AI output.
- Spec 3 Data Quality Guard: whether partner memory is reliable enough to use.
- Spec 4 Coach Action: deterministic selection of what the user should practice now.
- Spec 5 Coach Follow-up: structured coaching for pre-date, post-date, and open-ended situations.
- Spec 6 Coach 1:1: free-form, context-aware coaching for the user's current question.

The core thesis:

> VibeSync's moat is not the model. The moat is context, memory, productized coaching judgment, Traditional Chinese dating nuance, and a UI that removes the user's burden of reorganizing the whole situation before asking for help.

---

## 1. Product Thesis

### 1.1 What Users Pay For

Users are not paying for "AI can write a reply."

They are paying for:

- Less anxiety.
- Less guessing.
- Fewer bad moves.
- Less wasted time.
- More courage to move forward when appropriate.
- Better judgment to stop when the situation is not worth it.
- A coach that remembers the relationship context and helps them become a steadier version of themselves.

### 1.2 The Core Question

Every major screen should answer one clear question:

- Home: Which interaction do I want to process now?
- New interaction: What am I adding, and how will it be used?
- Analysis result: What should I do next in this conversation?
- Partner detail: How should I interact with this person over time?
- Coach 1:1: What does the coach think about the thing I am stuck on?
- Learning: What ability should I practice next?

If a card cannot answer one of these questions, it should be demoted, folded, or removed.

### 1.3 Why General LLMs Are Not Enough

A general LLM can analyze a pasted message. It can often write a decent answer.

But the user must manually provide:

- The conversation context.
- The relationship stage.
- What happened before.
- Their own style.
- Their emotional state.
- Their goal.
- The partner's known patterns.
- Whether this partner card may contain mixed data.

VibeSync should remove that burden. The user should be able to ask:

> 她這句是什麼意思？

and the product already knows which "she", which conversation, what stage, what recent signals, what user style, and what risks are involved.

---

## 2. Non-goals

Spec 6 v1 is not:

- A full ChatGPT-style infinite chat room.
- A global AI assistant floating across the whole app.
- A proactive notification system.
- A tool that automatically pursues people for the user.
- A manipulation or PUA tactics engine.
- A replacement for the existing OCR/analyze-chat pipeline.
- A new long-term memory writer.
- A place to upload new images and ask arbitrary questions.
- A reason to delete heat, stage, radar, or detailed analysis immediately.

The existing analysis assets remain valuable, but their visual priority should change. Reports become supporting evidence, not the product center.

---

## 3. Target UI Architecture

### 3.1 Final Product Shape

The final product architecture should be:

1. Home: process a new interaction quickly.
2. New interaction flow: clearly choose whether this is a continuation or a new conversation.
3. Analysis result: coach-first, next-step-first.
4. Partner detail: long-term relationship command center.
5. Learning/practice: article-to-practice loop.

### 3.2 Analysis Result Page - Coach-first Order

Target order:

1. Latest interaction summary.
2. Current judgment.
3. Next step.
4. Recommended reply.
5. Ask the coach.
6. Today's practice.
7. Why VibeSync thinks this.
8. Detailed data.
9. Interaction record.

The first screen should answer:

```text
目前判斷
她在丟觀察球，不是在要你證明自己。

下一步
承認一半，補一個畫面，再把球丟回她。

可以這樣回
被妳發現了，我真的會在飲料櫃前思考人生。
妳也是亂逛派嗎？
```

Heat and radar should not compete with the next step. They should support it.

### 3.3 Demoting Report-like UI

Keep but demote:

- Heat score.
- Conversation stage.
- Five-dimensional radar.
- Detailed signal explanation.
- Learning article links.

Suggested display:

```text
為什麼這樣判斷？
```

and:

```text
詳細數據
給想看細節的人。下一步建議已經在上方。
```

Both can be folded by default or placed below the core action area.

### 3.4 Recommended Reply vs Five Reply Styles

The user usually wants the best next move, not five equal options.

Target:

- Show one recommended reply first.
- Provide "看其他風格" as an expandable section.
- Keep 延展 / 共鳴 / 調情 / 幽默 / 冷讀 inside the expanded area.

This reduces choice overload and makes VibeSync feel more decisive.

### 3.5 Floating Action Button / Add Interaction

The current `+` should become clearer.

Recommended label:

```text
+ 新增互動
```

From Home:

- 上傳截圖分析
- 手動輸入對話
- 開場救星
- 新增對象

From Partner Detail:

- 接續上一段對話
- 新增一段新對話
- 上傳新的截圖
- 編輯對象資訊

The user should never wonder what kind of object they are creating.

---

## 4. Phase 6A - Coach 1:1 MVP

### 4.1 Goal

Validate whether "Ask the coach" feels more context-aware, more useful, and less burdensome than manually asking a general LLM.

### 4.2 User Entry

Place a card in the analysis result page:

```text
問教練一句

針對這段互動，直接問你卡住的地方。
不用重貼截圖，教練已經知道目前狀況。
```

Suggested chips:

- 她是什麼意思？
- 我該怎麼回？
- 我是不是太急？
- 這局值不值得？
- 我該推進嗎？

Input placeholder:

```text
直接問教練...
```

Button:

```text
問教練
```

Small copy:

```text
成功回答會扣 1 則額度
```

### 4.3 Request Payload

```json
{
  "conversationId": "local-conversation-id",
  "partnerId": "local-partner-id",
  "userQuestion": "她有男友還約我，這局能去嗎？",
  "recentMessages": [
    {
      "sender": "partner",
      "text": "最近有空可以出來喝一杯",
      "createdAt": "2026-05-07T10:00:00Z"
    },
    {
      "sender": "me",
      "text": "妳不是有男友嗎",
      "createdAt": "2026-05-07T10:01:00Z"
    }
  ],
  "conversationSummary": "兩人之前有輕微曖昧，對方回覆頻率穩定。",
  "analysisSnapshot": {
    "heatScore": 68,
    "stage": "warm",
    "summary": "對方有邀約意願，但關係狀態不清楚。",
    "nextStep": "先釐清動機與邊界，不急著承諾見面。",
    "coachActionType": "fitCheck",
    "keySignals": [
      "對方主動邀約",
      "對方已有男友",
      "用戶感到困惑"
    ]
  },
  "effectiveStyleContext": "使用者偏好：直接但不壓迫；練習目標：先降壓，不急著證明自己。",
  "partnerHint": {
    "name": "小雲",
    "traits": ["主動", "愛開玩笑", "界線感不明"]
  },
  "dataQualityFlagged": false
}
```

### 4.4 Context Rules

Must include:

- userQuestion.
- Recent messages, capped at 15 rounds / 30 messages.
- Existing conversation summary if older context exists.
- Analysis snapshot: heat, stage, summary, next step, coach action, key signals.
- Effective style context from Spec 2.5.
- Thin partner hint: name + up to 5 traits.
- dataQualityFlagged.

Must not include:

- Full history.
- Raw OCR images.
- Other partner data.
- Raw analysis JSON.
- Full partner summary.
- Coach chat from unrelated conversations.

If `dataQualityFlagged = true`, Coach 1:1 should only rely on the current conversation and avoid long-term partner memory.

### 4.5 Response Schema

```json
{
  "mode": "boundaryRisk",
  "headline": "先釐清這局的邊界",
  "answer": "她有男友卻約你，代表這局有吸引或情緒出口，但也有很高混亂成本。",
  "userState": "你可以承認自己想去，但不要假裝這只是普通朋友局。",
  "nextStep": "先問清楚她約你的動機與邊界，再決定值不值得投入。",
  "suggestedLine": "可以見，但我想先問清楚，妳現在約我是朋友局，還是有點想逃離一段關係裡的情緒？",
  "boundaryReminder": "你可以有慾望，但不要用模糊承諾或混亂關係換親密。",
  "needsReflection": true,
  "reflectionQuestion": "如果她最後只是把你當情緒出口，你還想投入這局嗎？"
}
```

Required:

- mode
- headline
- answer
- userState
- nextStep
- boundaryReminder
- needsReflection

Optional:

- suggestedLine
- reflectionQuestion

If `needsReflection = true`, `reflectionQuestion` must exist.

### 4.6 Modes

- `clarifyIntent`: partner/user intent is unclear.
- `stateCalibration`: user's state needs calibration.
- `boundaryRisk`: relationship, sex, money, partner-with-partner, or high-cost boundary risk.
- `moveForward`: suitable to move forward.
- `replyCraft`: mainly crafting a message.
- `stopSignal`: pause, stop, or avoid over-investment.

### 4.7 UI Output

Compact card:

```text
先釐清這局的邊界

她有男友卻約你，代表這局有吸引或情緒出口，但也有很高混亂成本。

下一步：先問清楚她約你的動機與邊界。
```

If `suggestedLine` exists:

```text
可以這樣說
可以見，但我想先問清楚...
```

Full bottom sheet:

- 我看到的重點
- 你現在可能卡在
- 下一步
- 可以這樣說
- 邊界提醒
- 教練想先問你一句

### 4.8 Edge Function

Add a new independent Supabase Edge Function:

```text
supabase/functions/coach-chat/
```

Do not place this inside `analyze-chat`.

Reasons:

- OCR baseline remains isolated.
- Deployment artifact is separate.
- Provider/model experimentation is isolated.
- Cost telemetry is cleaner.

Suggested structure:

```text
coach-chat/
  index.ts
  prompts.ts
  schema.ts
  validate.ts
  openai_client.ts
  logger.ts
  quota.ts
  telemetry.ts
  test/
```

### 4.9 Model Strategy

Spec 6A uses OpenAI API by default.

Environment variables:

```text
OPENAI_API_KEY
COACH_CHAT_PROVIDER=openai
COACH_CHAT_MODEL=gpt-5.5
```

Initial API strategy:

- Responses API.
- Structured Outputs / JSON schema.
- `reasoning.effort = low`.
- `text.verbosity = low`.
- Output cap around 900 tokens.
- 30s timeout.

If dogfood quality is shallow, try `reasoning.effort = medium`.

### 4.10 Credit Rules

Successful Coach 1:1 answer deducts 1 message credit.

Do not deduct when:

- User only opens the card.
- User types but does not submit.
- User taps a chip but does not submit.
- OpenAI call fails.
- Schema validation fails.
- Banned token validator fails.
- Credit deduction fails.
- The account is a test account.

Important invariant:

> No confirmed credit deduction, no successful card returned to a non-test user.

### 4.11 Local Persistence

Add local Hive persistence for recent Coach 1:1 results:

```text
coach_chat_results
```

Keep most recent 3 results per conversation.

Do not write Coach 1:1 outputs into:

- partner traits
- partner summary
- About Me
- long-term memory

---

## 5. Phase 6B - Analysis Result Coach-first Refactor

### 5.1 Goal

Reorder the analysis result page so the first screen gives the next useful action, not a report.

### 5.2 New Page Order

1. Latest interaction summary.
2. Current judgment.
3. Next step.
4. Recommended reply.
5. Ask the coach.
6. Today's practice.
7. Why VibeSync thinks this.
8. Detailed data.
9. Interaction record.

### 5.3 Current Judgment Quality Bar

The main judgment must be context-specific.

Good:

```text
她在丟觀察球，不是在要你證明自己。
```

Bad:

```text
她在向你證明自己。
```

Bad:

```text
保持自然，持續互動。
```

### 5.4 Reply Quality Bar

When the partner gives a personality observation, VibeSync should prefer:

> 承認一半 + 補畫面 + 反問

Example:

```text
被妳發現了，我真的會在飲料櫃前思考人生。
妳也是亂逛派嗎？
```

Do not produce empty lines like:

```text
我覺得很有意思。
```

### 5.5 Detailed Data

Heat, radar, and stage remain but move down.

Recommended section title:

```text
詳細數據
給想看細節的人。下一步建議已經在上方。
```

---

## 6. Phase 6C - New Interaction UX Refactor

### 6.1 Goal

Make it obvious whether the user is continuing an existing conversation or creating a new one, and make it visible when newly entered messages are added.

### 6.2 Entry Choice

Before manual input:

```text
你要怎麼新增？
```

Options:

```text
接續上一段對話
只補新的幾句。VibeSync 會沿用前面已分析過的摘要，更新這段互動的建議。
```

```text
新增一段新對話
適合不同日期、不同平台，或一段新的聊天脈絡。
```

### 6.3 Continue Conversation Copy

```text
只輸入新的來回訊息。
前面已分析過的內容會用摘要帶入，不需要重貼。
成功分析會依新增訊息扣額度。
```

### 6.4 Manual Input Behavior

After tapping `加入為她說` or `加入為我說`:

- Immediately add a bubble in a visible `本次新增訊息` section.
- Clear the input.
- Allow edit/delete.
- Avoid snackbar-only confirmation.
- Keyboard must be dismissible.

CTA:

```text
更新分析
```

Small copy:

```text
這次只會計算新增的 2 則訊息。
舊對話會用摘要帶入，不重複扣。
```

### 6.5 Analysis Refresh

After `更新分析`, the analysis result page must update:

- Current judgment.
- Next step.
- Recommended reply.
- Heat/stage.
- Interaction record.
- Coach 1:1 context.

The previous analysis can remain as historical state, but the user-facing analysis must show the latest result.

---

## 7. Phase 6D - Partner Detail Refactor

### 7.1 Goal

Partner detail should become a long-term relationship command center, not a CRM/report page.

### 7.2 Target Order

1. Partner summary.
2. Current relationship state.
3. Next step.
4. Ask the coach.
5. My style for this partner.
6. Interaction record.
7. Detailed traits/trends.
8. Data quality reminder.

### 7.3 Partner Summary

```text
小雲

目前：升溫中
最近互動：今天 19:24
最近建議：先接住她的觀察球，不急著證明自己。
```

Tags should be limited to high-action-value items:

```text
主動回覆 / 喜歡輕鬆幽默 / 目標：邀約見面
```

### 7.4 My Style for This Partner

This is how Spec 2.5 becomes visible to the user.

```text
我的風格・對小雲

目前使用：幽默一點、少解釋、先降壓
AI 會用這些設定調整你的回覆語氣和教練建議。
```

Required copy:

```text
不會讓 AI 假裝成另一個人，只會幫你更像穩定版的自己。
```

### 7.5 Object Settings

Move one-time partner data into a gear/settings surface:

- name
- where you met
- how long you have known each other
- current goal
- partner traits
- notes

Do not ask for this every time the user enters a conversation.

---

## 8. Phase 6E - Learning to Practice Loop

### 8.1 Goal

Learning should become practice, not a static article library.

### 8.2 Categories

- 開話題
- 延伸與共鳴
- 推進與邀約
- 性張力與曖昧
- 判斷與邊界
- 穩住自己

### 8.3 Article Page Structure

1. 一句話重點
2. 什麼時候用
3. 錯誤示範
4. 好的示範
5. 今天練一次
6. 帶回真實對話

### 8.4 Practice Example

Story framework practice:

```text
今天練：故事框架

輸入一件你最近發生的小事。
```

AI output:

```text
場景
昨天去買咖啡，店員突然多送你一塊餅乾。

觀點
那種被陌生人善待的小瞬間，會讓一天變輕一點。

可以這樣說
我昨天買咖啡，店員突然多送我一塊餅乾，我整個人被治癒。
妳有沒有那種被陌生人小小善待過的瞬間？
```

---

## 9. Coach Prompt Policy

### 9.1 Coach Identity

Coach 1:1 is not a general chatbot.

It should behave like:

> A context-aware dating coach who understands the current conversation, the user's state, the partner signal, and the next mature move.

### 9.2 Internal Reasoning Targets

Before answering, internally judge:

1. What is the user's real question?
2. What is the user's emotional state or blind spot?
3. What signal is the partner giving?
4. Should the user move forward, clarify, lower pressure, observe, or stop?
5. Are there boundaries, costs, or consequences to name?

Do not expose this reasoning process. Output only the useful conclusion.

### 9.3 Required Coaching Posture

- Empathize with the user.
- Consider the partner's possible experience.
- Calibrate the user's state without shaming.
- Give a concrete next step.
- Name boundary/cost when relevant.
- Be able to push forward when appropriate.
- Be able to tell the user to pause or stop when appropriate.

### 9.4 What Not To Do

- Do not give generic advice.
- Do not moralize.
- Do not shame desire.
- Do not encourage manipulation.
- Do not over-sanitize sexual tension.
- Do not produce long essays.
- Do not output internal product terms like radar, schema, or prompt.

---

## 10. Healthy Sexual Tension Policy

### 10.1 Product Stance

VibeSync should not treat sexual tension as a dangerous object by default.

Real flirtation can include ambiguity, teasing, light challenge, sexual subtext, and playful tension.

The goal is not to remove tension. The goal is to keep tension calibrated.

### 10.2 Principle

> Sexually suggestive signals are interaction signals, not permission slips.

Good sexual tension:

- can catch the ball;
- acknowledges attraction;
- stays playful;
- does not rush to prove;
- leaves room to retreat;
- does not pressure.

### 10.3 Levels

Level 0: partner has not opened a sexual/flirt frame.

- Do not force sexual framing.
- Keep humor light and socially normal.

Level 1: partner lightly opens flirt/tension.

Examples:

- 你感覺很會撩
- 你是不是很多女生喜歡
- 你看起來不像乖乖牌

Possible replies:

```text
我比較像偶爾失手，剛好被妳看到。
```

```text
妳這樣問，我會懷疑妳在釣我。
```

Level 2: partner clearly opens sexual subtext.

Example:

```text
你一看就是活還可以，雞雞大不大就不知道了。
```

Possible replies:

```text
妳觀察力不錯，但這題我不接受遠端鑑定。
```

```text
妳先別急著面試我，我也是會挑考官的。
```

```text
妳這句有點壞，我先記一筆。
```

```text
光看就能知道的話，妳是不是經驗有點豐富。
```

### 10.4 Prohibited

Do not teach:

- crude explicit escalation;
- sexual humiliation;
- pressure;
- coercion;
- alcohol-based escalation;
- using promises to exchange for intimacy;
- continuing sexual escalation when the partner does not reciprocate.

### 10.5 Prompt Line

```text
當對方已主動開啟曖昧或性張力框架時，請給出有幽默感、有分寸、有張力的回覆。可以輕微調侃、反問、模糊挑逗，但不要露骨、施壓、羞辱或急著升級。不要把所有性暗示都消毒成安全提醒；真正的成熟是接得住張力，也知道何時退一步。
```

---

## 11. Coach Reflection / Follow-up Question

### 11.1 Why It Matters

The coach's value is not only answering. Sometimes it should help the user notice what they are feeling.

Examples:

- What did your brain think when she said that?
- Are you afraid of losing her, or afraid of looking not good enough?
- If this is only a friend situation, do you still want to go?
- Are you moving forward because there is signal, or because you fear heat dropping?

### 11.2 v1 Behavior

v1 may include optional reflection, but should not return only a question.

Rule:

> First give a useful initial judgment. Then optionally ask one reflection question.

### 11.3 Schema

```json
{
  "needsReflection": true,
  "reflectionQuestion": "你聽到她這句話時，大腦第一個想法是什麼？"
}
```

If `needsReflection = true`, `reflectionQuestion` is required.

### 11.4 Future v1.1

Future flow:

1. Coach gives answer + reflection question.
2. User writes their honest reaction.
3. Coach gives deeper calibration.

This is out of v1 scope unless explicitly approved later.

---

## 12. Credit, Cost, and Privacy

### 12.1 Credit Rules

- Coach 1:1 successful answer deducts 1 message credit.
- Opening the UI does not deduct.
- Typing does not deduct.
- Failed generation does not deduct.
- Test account does not deduct.

### 12.2 Free / Starter / Essential

v1 opens Coach 1:1 to all tiers using the existing message quota.

Rationale:

- Free users must experience the core value.
- Paid tiers differentiate through more usage.
- Avoid adding another credit system.

### 12.3 Cost Controls

- Cap recent messages.
- Cap summaries.
- Cap effective style context.
- Cap output length.
- No images.
- No full-history Coach chat.
- No infinite chat in v1.

### 12.4 Telemetry

Log only:

- invoked/succeeded/failed
- mode
- provider/model
- tier
- costDeducted
- latencyMs
- inputTokens/outputTokens
- contextMessageCount
- dataQualityFlagged

Do not log:

- userQuestion
- prompts
- raw AI response
- partner messages
- suggestedLine

### 12.5 User-facing Privacy Copy

Because Spec 6 uses OpenAI API, the product should clearly state:

```text
為了回答你的問題，系統會把這段對話的必要上下文傳給 AI 模型。
這些內容只用於本次生成，不會被 VibeSync 後端長期保存。
```

---

## 13. Dogfood Evaluation

### 13.1 Test Set

Minimum 20 prompts:

1. 她問 AA 制，我怎麼回？
2. 她說我感覺很有故事，我該怎麼接？
3. 她有男友還約我，這局能去嗎？
4. 我想把她規成炮友，怎麼講比較清楚？
5. 她已讀不回兩天，我要追嗎？
6. 約會後我暈船了，怎麼穩住？
7. 她一直提到前任，是什麼意思？
8. 我是不是太急著約？
9. 她說最近很忙，我還要推嗎？
10. 她問我是不是只想約炮，我怎麼回？
11. 我覺得她很公主病，還值得嗎？
12. 她開性暗示，我怎麼接才有張力？
13. 我想告白但怕嚇到她。
14. 她回很短但有問問題，算有興趣嗎？
15. 她說你人很好，是不是沒戲？
16. 我覺得自己配不上她。
17. 她臨時取消約會，我要怎麼處理？
18. 她叫我幫忙付錢，該不該？
19. 我想收掉但又捨不得。
20. 我不知道她是不是喜歡我。

### 13.2 Scoring

Rate 1-5:

- Uses current conversation context.
- Sees user's state.
- Gives concrete next step.
- More convenient than asking ChatGPT manually.
- Matches VibeSync's sincere-flow values.
- Maintains tension when appropriate.
- Stops when appropriate.
- Pushes forward when appropriate.

Pass:

- Average score >= 4.0.
- No more than 3 prompts below 3.
- No hard red-line content.
- At least 70% feel more VibeSync-specific than a manually prompted general LLM.

---

## 14. Risks

### R1. It becomes a GPT wrapper

Mitigation:

- Always pass VibeSync context.
- Require domain-specific schema.
- Dogfood against ChatGPT baseline.
- Judge convenience/context, not just prose quality.

### R2. It becomes too safe and boring

Mitigation:

- Healthy Sexual Tension policy.
- Prompt examples for calibrated teasing.
- Reject over-sanitized outputs in dogfood.

### R3. It becomes too expensive

Mitigation:

- One-question-one-answer v1.
- Context caps.
- Low reasoning first.
- Token telemetry.

### R4. UI becomes more crowded

Mitigation:

- Coach-first refactor demotes reports.
- Fold detailed data.
- Show one recommended reply first.

### R5. Privacy trust gap

Mitigation:

- Clear user-facing copy.
- No server-side long-term content logging.
- Local persistence only for Coach Q&A.

### R6. It gives bad relationship judgment

Mitigation:

- Dogfood test set.
- Regression prompts for known tricky cases.
- Conservative stop-signal option.
- Data quality degradation when flagged.

---

## 15. Open Questions

1. Should Phase 6A immediately use OpenAI `gpt-5.5`, or should model choice wait for final API pricing review?
2. Should `Ask the coach` results be visible inline only, or also saved in a local history drawer?
3. Should Free users get Coach 1:1 from day one, or should v1 hide it after limited trial usage?
4. Should the analysis result page be refactored before or after Coach 1:1 dogfood?
5. Should partner-level Coach 1:1 be included in 6D or deferred to Spec 7?
6. Should `reflectionQuestion` be display-only in v1, or support a second paid follow-up immediately?
7. Should Learning practice use a separate free daily practice allowance?
8. What exact privacy wording should appear before first Coach 1:1 use?

---

## 16. Proposed Build Order

1. Spec 6A: Coach 1:1 MVP.
2. Spec 6B: Analysis result coach-first refactor.
3. Spec 6C: New interaction UX refactor.
4. Spec 6D: Partner detail refactor.
5. Spec 6E: Learning practice loop.

Do not write the implementation plan until Eric and Bruce approve this design direction.

