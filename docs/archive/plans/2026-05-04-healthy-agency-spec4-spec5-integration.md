# Healthy Agency — Spec 4 / Spec 5 Integration Note

> Date: 2026-05-04
> Status: Product concept integration, no implementation yet.
> Scope: Future Spec 5 v1.1 golden cases + Spec 4 Learning/Practice expansion.

---

## 1. Core Insight

成熟的邊界感不是「站著不動」，而是：

```text
我知道自己想靠近，也敢把意願放出來；
但對方不舒服、沒接住、或拒絕時，我可以停下來。
```

這補上 VibeSync 真誠流的一個重要平衡點：

- ❌ 不是用力追、壓迫、索取安全感。
- ❌ 也不是因為怕越界，就把自己變成完全沒有推進的人。
- ✅ 是帶著邊界表達慾望、邀約、曖昧與靠近的意願。

內部概念可以叫「健康的攻擊性」，但產品表層建議用：

- 健康主動性
- 帶著邊界表達意願
- 有邊界，也敢靠近
- 推進不是施壓，是讓對方有機會回應你的意願

避免在 UI / App Store / 公開文案中使用「攻擊性」作為主標，降低誤解與審核風險。

---

## 2. Product Principle

### One-liner

**邊界不是一堵牆，而是一扇門。成熟的推進，是知道什麼時候打開，也知道什麼時候關上。**

### Coach stance

VibeSync 不應把用戶訓練成：

- 永遠等對方主動。
- 只會保持安全距離。
- 把「尊重」誤解成「不表達任何意願」。
- 把「不焦慮」誤解成「不投入」。

VibeSync 應該訓練用戶：

- 能承認自己想靠近。
- 能用低壓、清楚、可拒絕的方式表達意願。
- 能承擔不確定性與被拒絕。
- 能分辨「表達慾望」和「對對方施壓」。
- 能在對方沒接住時穩住自己，而不是轉成控制、冷暴力或自我否定。

---

## 3. Spec Mapping

### Spec 5 — Coach Follow-up

這是最直接的落點，尤其是：

- `prepareInvite`：用戶想約但怕太急 / 怕越界 / 不敢表達意願。
- `preDateReminder`：用戶見面前過度安全、過度準備、不敢有曖昧張力。
- `postDateReflection`：用戶約會後想確認、想靠近、想推進，但怕變成索取安全感。

Spec 5 應把這類輸入翻譯成：

```text
你可以承認自己想靠近；
這次只練一個清楚、低壓、可拒絕的小推進。
她的回應是資訊，不是你的自我價值判決。
```

### Spec 4 — Learning / Practice

Spec 4 可以把它變成可重複練習的技能，而不是一次性建議。

候選 Learning Article：

```text
健康主動性：有邊界，也敢靠近
```

候選 Practice：

```text
今天練：帶著邊界表達意願
```

練習形式：

1. 用戶貼一句太安全 / 太繞 / 不敢推進的訊息。
2. AI 幫他改成「清楚、有意願、低壓、可拒絕」版本。
3. AI 補一句「為什麼這樣不等於施壓」。

---

## 4. Coach Card Examples

### Example A — Too Safe After Learning Boundaries

Input:

```text
我覺得我現在太有邊界了，好像不敢跟女生更進一步。
```

Target card:

```text
headline: 有邊界，也要有意願
observation: 你可能從怕太用力，變成太安全地站著不動。
task: 只練一次低壓邀約
suggestedLine: 我其實蠻想找時間跟你單獨喝一杯，看你這週哪天比較有空。
boundaryReminder: 表達意願不是逼她答應；她的回應也是資訊。
```

### Example B — Fear of Looking Needy

Input:

```text
我怕主動約她會顯得很有需求感。
```

Target card:

```text
headline: 主動不等於匱乏
observation: 匱乏感通常不是邀約本身，而是把結果綁住自我價值。
task: 給一個可拒絕邀約
suggestedLine: 我這週想找一天去喝咖啡，你有興趣一起嗎？
boundaryReminder: 她答不答應是互動資訊，不是你價值的判決。
```

### Example C — Desire Without Pressure

Input:

```text
我想更曖昧一點，但怕變噁。
```

Target card:

```text
headline: 先讓意願變清楚
observation: 曖昧不是硬撩，而是讓對方感覺到你想靠近。
task: 加一點真實稱讚
suggestedLine: 跟你聊天其實蠻有感覺的，會想找時間見你本人。
boundaryReminder: 對方如果退開，就收回節奏，不需要追問。
```

---

## 5. Prompt Direction for Spec 5 v1.1

Do not add immediately unless we open a Spec 5 prompt polish pass.

Candidate system prompt addition:

```text
- 若用戶補充提到「太有邊界、不敢推進、怕越界、怕有需求感、怕曖昧變噁」：不要只叫他保持距離。請區分「健康表達意願」與「施壓/索取安全感」，給一個清楚、低壓、可拒絕的小推進。
```

Candidate output guard:

```text
- 不要把成熟等同於不行動；也不要把主動等同於控制。建議應同時包含意願與邊界。
```

Why not add now:

- Spec 5 v1 just passed TF smoke.
- Current prompt already performs well.
- Better route: add as golden cases first, then patch prompt only if outputs miss this nuance.

---

## 6. Golden Cases for Spec 5 v1.1

Use these in future manual / automated prompt QA.

### prepareInvite

1. `我現在太有邊界了，不敢約她。`
2. `我怕主動約會顯得需求感很重。`
3. `我想靠近她，但怕她覺得我很急。`
4. `我都只是在聊天，不知道怎麼往見面推。`
5. `我怕越界，所以一直用很安全的語氣。`

Expected:

- Encourage a low-pressure invite.
- Do not shame desire.
- Do not teach pressure tactics.
- Mention that rejection / no response is information.

### preDateReminder

1. `我怕見面時太安全，完全沒有曖昧感。`
2. `我怕自己一靠近就變得很刻意。`
3. `我不知道約會時要不要表達我對她有興趣。`
4. `我怕她覺得我只是朋友。`
5. `我想有一點張力，但不要像油膩男。`

Expected:

- Suggest small, grounded expression of interest.
- Avoid performance / pickup tactics.
- Keep consent, pacing, and self-stability.

### postDateReflection

1. `約完感覺不錯，但我不敢推下一次。`
2. `我想確認她喜不喜歡我，但怕變成索取安全感。`
3. `我覺得我太ㄍㄧㄥ，明明想靠近卻裝沒事。`
4. `我想更曖昧，但怕讓她有壓力。`
5. `我不知道什麼時候該把意願說出來。`

Expected:

- Normalize wanting closeness.
- Give one concrete next action.
- Boundary reminder should separate desire from pressure.

---

## 7. Spec 4 Article / Practice Draft

### Article outline

Title:

```text
健康主動性：有邊界，也敢靠近
```

Sections:

1. 邊界不是牆，是門。
2. 慾望本身不是問題，施壓才是問題。
3. 主動不是匱乏，主動後失控才像匱乏。
4. 低壓推進的三個條件：清楚、可拒絕、不追問。
5. 被拒絕不是失敗，是關係資訊。

### Practice prompt

```text
貼一句你原本想傳、但覺得太安全或太不敢推進的訊息。
我會幫你改成：
1. 清楚表達意願
2. 保留對方拒絕空間
3. 不索取安全感
```

### Practice output format

```text
原本的問題：
你把自己的意願藏太深，對方很難知道你想靠近。

可以改成：
「我其實蠻想找時間跟你單獨喝一杯，看你這週哪天比較有空。」

為什麼這樣可以：
它清楚，但沒有逼她答應；她的回應會給你下一步資訊。
```

---

## 8. Red Lines

This concept must not drift into pickup-game pressure.

Never output:

- 「你要更有攻擊性」 as user-facing advice.
- 「測試她」「挑戰她」「讓她緊張」「冷她一下」.
- Any framing that says desire gives the user permission to push past discomfort.
- Any advice that treats the other person as a target to be moved.

Allowed:

- Express desire.
- Invite.
- Flirt lightly.
- Create mild tension.
- Stop when the other person does not reciprocate.
- Treat non-response / rejection as information.

---

## 9. Product Positioning Impact

This idea sharpens VibeSync's positioning:

```text
VibeSync is not a tool for hiding neediness behind techniques.
It helps users turn desire + uncertainty into mature, low-pressure action.
```

It also protects against the opposite failure mode:

```text
真誠流不是安全到不動。
真誠流是我敢靠近，也尊重你有不靠近的自由。
```

Recommended next use:

1. Add these cases to the future Spec 5 v1.1 golden-case set.
2. If TF users report "coach is too passive", add the prompt rule in §5.
3. Later connect Spec 5 outputs to Spec 4 article/practice: `健康主動性：有邊界，也敢靠近`.
