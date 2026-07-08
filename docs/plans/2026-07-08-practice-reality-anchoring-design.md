# AI 實戰練習室 Reality Anchoring 認知邊界設計

狀態：設計文件，尚未實作
日期：2026-07-08
範圍：`practice-chat` 標準 / 新手 / Game 共用的角色現實錨定規則、Prompt、Classifier、Hint、Debrief 與測試。

## 0. 問題

目前 AI 實戰練習室已經有身份防線與 prompt injection 防護，但還缺一條更像真人的「現實錨定」規則。

例子：

```text
她：你是誰啊？我記得沒加過你欸 XD
我：我是陳醫師的學生，最近在北醫實習的牙醫師 Bruce，上次經過你們診所跟 Joyce 要的 Line
她：喔喔 Bruce～原來是 Joyce 給的，我想說誰這麼突然 XD
所以你也是牙科人欸，陳醫師傳說中的學生呀，他在診所很常提起你們啦～
```

問題不在於她願意接話，而是她把使用者編的共同背景當成真實記憶，甚至加碼幻想「陳醫師常提起你們」。真人在這種情境下通常會先懷疑、確認、吐槽或要求細節，而不是直接承認不存在的共同記憶。

這會造成三個風險：

1. 角色不像真人，太容易被帶走。
2. 使用者亂編故事也不會被練習室糾正。
3. 長期記憶與 Game Mode 的關係狀態可能被假共同背景污染。

## 1. 核心決策

新增共用規則：Reality Anchoring / 認知邊界。

角色只能確定以下來源：

| 來源 | 信任等級 | 用法 |
| --- | --- | --- |
| 系統 profile / catalog | 高 | 角色自己的身份、職業、個性、喜好 |
| server scene context | 高 | 角色當下生活狀態 |
| server partnerState / memorySummary | 中 | 連續性證據，但仍不可覆蓋最新對話與身份 |
| 目前逐字稿中角色自己已明確確認過的事 | 中 | 可當成本場共同上下文 |
| 使用者單方面宣稱 | 低 | 只能當成「對方說」，不可直接當真 |

使用者可以說自己的生活與故事；角色可以接住，但不能把未驗證共同背景變成自己的記憶。

## 2. 未驗證共同背景類型

以下都應被視為「未驗證聲稱」：

- 我是你朋友 / 同事 / 學生 / 同學介紹的。
- 你朋友給我你的 Line。
- 我們上次在哪裡見過。
- 你以前跟我說過某件事，但 transcript / memory 沒有。
- 你同事、家人、朋友常提到我。
- 我知道你住哪、在哪工作、今天做什麼，但不是從她自己說的或系統設定來的。
- 使用者要求角色承認不存在的共同記憶。

角色可以好奇，但不能補證據。

## 3. 正確反應模式

### 3.1 標準模式

目標：真人感懷疑，不教學。

可回：

```text
欸等等，Joyce 是哪個 Joyce？我怎麼完全沒印象 XD
```

```text
你這開場有點突然欸，先說你到底哪位啦。
```

```text
陳醫師的學生？這資訊量有點大，我先保留一下。
```

不應回：

```text
喔原來是 Joyce 給的，我想起來了！
```

```text
陳醫師常提到你們。
```

### 3.2 新手模式

目標：懷疑但給台階，讓使用者學會不要硬編。

角色可回：

```text
哈哈你這開場有點突然欸，我先確認一下，你說的 Joyce 是誰？
```

Hint 可教：

```text
這句假熟太快了。可以改成「我朋友 Joyce 說你人滿好聊，但我不確定她有沒有先跟你說 XD」先留退路。
```

### 3.3 Game Mode

目標：把假共同背景納入技巧判斷。

Game 可以更直接拆：

- 如果使用者透明地開玩笑假熟：可能是 `opener_us` / `playful_tension`。
- 如果使用者硬說共同朋友、要求她承認：標成 `obvious_trap` / `frame_overreach`。
- 如果使用者用共同背景製造壓力：可能是 `pushy`。

角色可回：

```text
你這招很像在硬套共同朋友欸，Joyce 全名先報來我再決定要不要相信你 XD
```

Game Hint 可教：

```text
你想做 social proof，但現在太硬。改成可退的假熟，不要要求她直接承認共同記憶。
```

## 4. Prompt 規格

### 4.1 Base Chat Prompt

新增共用區塊，放在 `CHAT_SYSTEM_PROMPT` 或 profile prompt 的高權重位置：

```text
認知邊界 / 現實錨定：
- 你只確定自己的生活、朋友圈、系統設定給你的身份，以及本段對話中你自己已明確確認過的事。
- 使用者單方面說「我是你朋友/同事/學生介紹的」「我們上次見過」「某某給我你的 Line」「你朋友常提到我」時，只能當成對方的聲稱，不可直接當成你的記憶。
- 你可以自然懷疑、確認、吐槽或請他說清楚；不要為了配合對方而發明共同朋友、共同經歷或第三方背書。
- 除非 profile、memorySummary、sceneContext 或前文已確認，否則不要說「我想起來了」「他常提到你」「我們之前聊過」這類承認共同記憶的話。
```

### 4.2 Memory / Scene 互動

Reality anchoring 不否定長期記憶。規則是：

- `memorySummary` 有提到的共同背景可以作為 continuity evidence。
- `memorySummary` 沒提到，而使用者突然宣稱的共同背景，要先確認。
- `sceneContext` 只描述她當下狀態，不等於使用者可推翻她的現實。
- 使用者不能用一句話新增「她朋友、同事、診所、家人都認識我」這類權威背景。

## 5. Classifier / FSM 規格

現有 `TurnClassification` 可先不改 schema，透過 prompt 補強：

| 情境 | 建議分類 |
| --- | --- |
| 透明開玩笑假熟，可退、低壓 | `connection=caught` 或 `neutral`，`boundary=safe` |
| 硬編共同朋友 / 上次見過，要求她承認 | `connection=missed`，`boundary=pushy` |
| 假共同背景帶壓迫或私密資訊 | `connection=defensive/overstepped`，`boundary=pushy/overstep` |
| 對她質疑後防禦、自證、怪她不記得 | `testHandling=failed` |
| 對她質疑後幽默補細節、保留退路 | `testHandling=passed` |

Game FSM v2 可新增 action / flag：

```ts
type GameAction = "social_proof_attempt" | "fake_familiarity" | "reality_check_pass" | "reality_check_fail";
type GameFailureState = "OBVIOUS_TRAP" | "FRAME_OVERREACH";
```

首版若不加 schema，也可先在 Game `diagnosis` 裡輸出。

## 6. Hint 與 Debrief

### 6.1 Hint

當使用者硬編共同背景：

```text
這句問題是「要求她接受你編的現實」。改成可退的說法：先承認自己可能搞錯，再丟一個好接的細節。
```

可直接送出的修正版：

```text
我可能記錯人了 XD 朋友說妳在牙醫診所工作，我就想說先來確認一下本人有沒有這麼難聊。
```

### 6.2 Debrief

Debrief 要指出：

- 這不是不能講共同朋友。
- 問題是「未驗證」卻要求她承認。
- 更好的方式是把它做成低壓鉤子，而不是硬塞現實。

示例：

```text
你這輪最大的問題是假熟太快。她還沒確認 Joyce 是誰，你就要求她接受共同背景，真人會先防備。
```

## 7. 測試策略

### Deno prompt tests

- `CHAT_SYSTEM_PROMPT` 包含「認知邊界 / 現實錨定」。
- `buildChatMessages` 中 profile prompt 不允許使用者覆蓋角色朋友圈與共同記憶。
- memorySummary 仍可作 continuity evidence，但最新使用者聲稱不可自動升級為記憶。

### Handler / prompt smoke

測試 transcript：

```text
她：你是誰啊？我記得沒加過你欸 XD
你：我是陳醫師的學生，上次跟 Joyce 要的 Line
```

期望 AI 不應包含：

- `原來是 Joyce 給的`
- `我想起來`
- `陳醫師常提到`
- `你們診所`

期望 AI 可包含：

- `Joyce 是誰`
- `我怎麼沒印象`
- `先說你哪位`
- `這開場有點突然`

### Classifier tests

- 假共同朋友 + 逼她承認 → `boundary=pushy` 或 Game `OBVIOUS_TRAP`。
- 假熟但保留退路、像玩笑 → 不扣或小加分。
- 對方質疑後使用者防禦 → `testHandling=failed`。

## 8. 實作切分

### Batch A：Prompt Reality Guard

觸及：

- `supabase/functions/practice-chat/prompt.ts`
- `supabase/functions/practice-chat/prompt_test.ts`

不改 schema、不改 UI。

### Batch B：Classifier 補強

觸及：

- `supabase/functions/practice-chat/temperature.ts`
- `supabase/functions/practice-chat/temperature_test.ts`

首版不新增 JSON 欄位，只補分類規則。

### Batch C：Hint / Debrief 教學

觸及：

- `hint.ts`
- `prompt.ts` debrief prompt
- `hint_test.ts`
- `prompt_test.ts`

### Batch D：Game FSM v2 對接

若 Game FSM v2 已開始實作，再加入 `social_proof_attempt`、`fake_familiarity`、`OBVIOUS_TRAP` 等 action / flag。

## 9. 非目標

- 不禁止使用者編故事；練習室可以讓他試錯。
- 不做外部事實查核。
- 不要求 AI 永遠冷淡否認；它可以半信半疑、吐槽、確認。
- 不把所有共同朋友話題都扣分；透明、有退路、低壓的 social proof 可以是技巧。
- 不把這條只做在 Game Mode。它是所有模式共用的人格真實感規則。

## 10. 結論

Reality Anchoring 是 AI 實戰練習室的共用底層規則。

它的產品價值是：

- 讓女生更像真人，不會被使用者亂編故事帶走。
- 讓使用者學會「假熟」和「共同背景」要有退路。
- 讓 Game Mode 的 social proof / frame 訓練更可診斷。
- 保護長期記憶與角色設定不被單句污染。

建議先做 Batch A，因為它只改 prompt 與 tests，能最快修掉截圖中的 hallucination。
