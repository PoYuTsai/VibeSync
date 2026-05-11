# Memory Coach Spec 2B: Partner Coaching Override

> Status: roadmap draft, do not implement before Spec 1 and Spec 2A  
> Date: 2026-04-30  
> Depends on: Spec 1 `About Me`, Spec 2A `Prompt Fallback Chain`  
> Scope: partner-level coaching preference override. No scoring changes, no OCR changes.

## 1. Why This Exists

Spec 1 creates global `About Me`:

```text
我是怎麼聊天的人？我想練什麼？我常聊什麼？
```

But real dating coaching has a second layer:

```text
面對不同對象，我可能想用不同節奏。
```

Example:

- Global style: 幽默。
- Partner A: 她也很俏皮，可以維持幽默。
- Partner B: 她比較慢熟，建議穩重一點。
- Partner C: 她很直接，建議少鋪陳，直接清楚。

This is what Bruce's second screenshot points to: a person icon on PartnerDetail that opens `我的風格` for this specific partner.

## 2. Product Definition

Spec 2B adds an optional partner-level coaching override.

Core rule:

```text
Partner override tunes coaching for this partner only.
It does not rewrite the global About Me.
```

Fallback priority:

```text
Partner override > Global About Me > Generic coaching
```

Meaning:

- If this partner has override, AI uses override for coaching tone / task examples.
- If no override, AI uses global About Me.
- If neither exists, AI uses generic coaching.

## 3. Why Not Spec 1

This must not be part of Spec 1.

Reasons:

- Spec 1 is low-risk local user profile storage.
- Spec 2B touches PartnerDetail, partner schema, and prompt fallback semantics.
- It requires UX copy explaining global vs partner-specific settings.
- If implemented too early, users may confuse `About Me` with `About this partner`.

Spec 1 should only include:

- Global About Me.
- Manual input cleanup.
- No prompt injection.
- No partner override.

## 4. Entry Point

Potential entry point on PartnerDetail AppBar:

```text
person icon / silhouette icon
```

Recommended tooltip:

```text
這個對象的互動設定
```

Avoid label:

```text
我的風格
```

Reason:

`我的風格` alone can sound global. The UI must make clear this setting is only for the current partner.

Suggested title:

```text
這個對象的互動設定
```

Subtitle:

```text
預設會使用「關於我」的設定。你也可以只針對這個對象微調語氣與練習重點。
```

## 5. Data Model

Recommended entity:

```dart
class PartnerCoachingOverride {
  final String partnerId;
  final InteractionStyle? interactionStyle;
  final List<PracticeGoal> practiceGoals;
  final String? notes;
  final DateTime updatedAt;
}
```

Fields intentionally excluded in v1:

- `topicSeeds`
- `customTopics`

Reason:

Topic seeds are mostly user-level. Partner-specific topics should come from partner memory / conversation history, not manual override.

## 6. Field Semantics

### 6.1 Interaction Style

Optional single select.

Options same as Spec 1:

- 穩重
- 直接
- 幽默
- 溫柔
- 俏皮

Copy:

```text
只針對這個對象調整建議語氣。
```

### 6.2 Practice Goals

Optional multi-select, max 3.

Options same as Spec 1:

- 自然邀約
- 降低焦慮
- 幽默回覆
- 拉近距離
- 少解釋一點

Copy:

```text
面對這個對象時，優先練這幾件事。
```

### 6.3 Notes

Optional text, max 100 chars.

Placeholder:

```text
例如：她比較慢熟，建議不要太快邀約，先多接情緒
```

## 7. Empty / Filled UX

### Empty State

```text
目前使用全域設定
會套用「我的報告 > 關於我」裡的風格和練習目標。

[針對這個對象微調]
```

### Filled State

```text
已針對這個對象微調
互動風格：穩重
練習目標：自然邀約、少解釋一點

[編輯] [重設為全域]
```

Reset copy:

```text
已改回使用全域設定
```

## 8. Prompt Contract

Spec 2B can only happen after Spec 2A defines safe prompt injection.

Prompt block should be explicit:

```text
[User Coaching Preferences]
Source: partner override
Interaction style: 穩重
Practice goals: 自然邀約、少解釋一點
Notes: 她比較慢熟，建議不要太快邀約

Use these only to adapt coaching tone, examples, and practice focus.
Do not use them to change heat score, dimension scores, partner traits, or evidence interpretation.
```

If no partner override exists, use global About Me block:

```text
Source: global about me
```

If neither exists, omit profile block entirely.

## 9. Non-Goals

Spec 2B does not:

- Change OCR。
- Change heat score。
- Change five-dimensional scores。
- Change partner traits。
- Change partner aggregate。
- Auto-generate partner override。
- Infer partner personality from photos。
- Add cloud sync。
- Add proactive notifications。

## 10. Tests

### Unit / Repository

- Save override by partnerId。
- Read override by partnerId。
- Clear override returns null。
- Override does not mutate global About Me。
- Empty override clears record。

### Provider

- Partner override resolves before global About Me。
- Global About Me resolves when no partner override。
- Empty profile resolves to null block。

### Widget

- PartnerDetail shows person icon / entry point。
- Empty override screen shows `目前使用全域設定`。
- Save override updates PartnerDetail state。
- Reset override shows `已改回使用全域設定`。
- Existing `...` menu behavior remains unchanged。

### Prompt Regression

- No override + no global profile equals old prompt。
- Override present injects `Source: partner override`。
- Override never appears in `recognizeOnly` / OCR-only path。

## 11. Implementation Timing

Recommended order:

1. Spec 1: About Me + manual input cleanup。
2. Spec 2A: safe global prompt fallback。
3. Spec 2B: partner coaching override。

Do not implement Spec 2B until Spec 2A has Codex review and OCR regression protection.

## 12. One-Line Summary

Spec 2B lets users say:

```text
平常我是一種風格，但面對這個對象，我想微調成另一種節奏。
```

It is valuable, but it belongs after global profile and safe prompt fallback are stable.

