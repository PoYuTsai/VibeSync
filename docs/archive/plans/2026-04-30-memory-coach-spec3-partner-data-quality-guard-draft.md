# Memory Coach Spec 3: Partner Data Quality Guard

> Status: brainstorm locked, pending implementation planning  
> Date: 2026-04-30  
> Depends on: Partner Entity A2 + dogfood findings  
> Parent roadmap: `docs/plans/2026-04-30-vibesync-memory-coach-roadmap.md`

## 1. Goal

Protect partner memory from being polluted when conversations from different people are placed under the same Partner card.

This is a trust-boundary feature. It protects Layer 2 memory before Layer 4 coaching relies on it too heavily.

## 2. Product Principle

One Partner card should represent one person.

If the card may contain conversations from different people, VibeSync should not pretend the long-term aggregate memory is reliable.

Core rule:

```text
Partner memory is useful only when partner data quality is trusted.
```

## 3. User Experience Goal

The app should:

1. Detect questionable partner data.
2. Explain uncertainty gently.
3. Help the user move misplaced interaction records.
4. Reduce or block unreliable aggregate analysis when needed.

The app should not blame the user.

Use:

```text
這張卡裡有幾段互動紀錄看起來不太一致
建議確認是不是同一個人，這樣整體分析會更準
```

Avoid:

```text
你放錯了
這不是同一個人
AI 確定這是錯的
```

## 4. Status Model

```dart
enum PartnerDataQualityStatus {
  clean,
  needsReview,
  blockedForAggregate,
}
```

Result object:

```dart
class PartnerDataQualityResult {
  final PartnerDataQualityStatus status;
  final List<String> reasons;
  final List<String> suspiciousConversationIds;
}
```

## 5. Detection v1

Use deterministic heuristic v1. Do not use LLM identity resolution.

Potential signals:

1. Conversation name difference:
   - Multiple records under one partner have very different names.
   - Example: `Bruce Chiang`, `Candy`, `C`.

2. Partner name vs conversation names:
   - Partner name is `小明`, but conversation names repeatedly look like different people.

3. Trait / tag overlap:
   - Conversation-level traits have very low overlap and are directionally conflicting.
   - Use conservatively; one person can behave differently across contexts.

4. Manual reassign signal:
   - If user repeatedly reassigns records away from a partner, future warnings may be stronger.

Suggested scoring:

```text
0-39 = clean
40-69 = needsReview
70-100 = blockedForAggregate
```

Protective rule:

```text
Do not enter blockedForAggregate unless at least two independent signals are present.
```

## 6. UI Behavior

### PartnerDetail Banner

`needsReview`:

```text
有幾段互動紀錄看起來不太一致，建議確認是不是同一個人。
```

`blockedForAggregate`:

```text
這張卡可能混入不同人的聊天紀錄。整理後，整體分析才會更準。
```

Buttons:

```text
查看互動紀錄
我確認是同一個人
```

### Partner Traits Fallback

When `blockedForAggregate`, do not show long-term partner traits as if they were reliable.

Fallback card:

```text
先整理互動紀錄
這張卡裡可能混入不同人的聊天。整理後，我們再幫你整理可靠的對方特質。
```

### Record-Level Action

Keep the existing `改派到其他對象` action.

Future action, not v1:

```text
另存成新對象
```

## 7. Prompt Guard

Before building AI prompt context, read `PartnerDataQualityResult`.

`clean`:

- Inject partner summary / partner traits / partner interests normally.
- Coach can mention long-term trend.

`needsReview`:

- Inject partner summary with caution.
- Prompt block:

```text
[Partner Data Quality]
Some records under this partner may be inconsistent.
Avoid strong long-term personality claims unless directly supported by the current conversation.
```

`blockedForAggregate`:

- Do not inject partner aggregate / summary.
- Use only current conversation.
- Prompt block:

```text
[Partner Data Quality]
This partner card may contain records from different people.
Do not use partner-level memory or long-term traits.
Give advice only based on the current conversation.
```

## 8. Dismiss Strategy

When user taps `我確認是同一個人`, hide the warning for that partner signature.

Suggested local key:

```text
partner_data_quality_dismissed_{uid}_{partnerId}_{signature}
```

`signature` should include conversation ids / updatedAt hash, not only partnerId.

If new conversation data changes the signature, the warning can reappear.

Do not permanently write AI uncertainty into the Partner entity in v1.

## 9. Tests

Required groups:

1. Clean card:
   - Similar names / same partner.
   - Expect `clean`, no warning.

2. Needs review:
   - Cross-platform nicknames like `糖糖 / Candy / Candy 糖糖`.
   - Expect at most `needsReview`, not blocked.

3. Blocked:
   - Clearly different names plus low trait overlap.
   - Expect `blockedForAggregate`.

4. Dismiss:
   - Warning hides after confirmation.
   - New signature can show warning again.

5. Prompt guard:
   - `blockedForAggregate` excludes partner aggregate.
   - `needsReview` adds caution.

6. Reassign recovery:
   - Reassign suspicious record.
   - Both source and target partners recalculate.

## 10. Non-Goals

- Do not build full identity resolution.
- Do not claim the AI can prove whether two screenshots are the same person.
- Do not block users from saving.
- Do not use photos to diagnose personality.
- Do not auto-merge or auto-split.
- Do not use face recognition.
- Do not modify OCR / analyze-chat parser.

## 11. Product Acceptance

Dogfood should answer:

- I know why the app warned me.
- I know how to fix it.
- After fixing, partner traits and long-term analysis feel more trustworthy.
