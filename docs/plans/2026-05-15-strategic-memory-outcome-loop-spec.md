# VibeSync Strategic Memory / Outcome Loop Spec

> Status: design spec, no implementation yet
> Date: 2026-05-15
> Purpose: define the smallest safe loop from AI advice -> user action -> outcome -> better future coaching.

## 1. Product Thesis

VibeSync's moat is not only that it remembers facts. The real value is that it turns past outcomes into better judgment.

The user-facing promise:

```text
它記得我怎麼聊、她怎麼反應，所以下次建議會更準。
```

This spec moves the product from "AI gives advice" toward "AI learns which advice worked for this person, with this partner, in this situation."

Important boundary:

- Do not write raw Coach 1:1 answers directly into long-term memory.
- Do not silently infer permanent traits from one outcome.
- Only capture structured outcome events after the user gives an explicit signal.
- Consolidated memory must stay small, scoped, and confidence-aware.

## 2. Definitions

| Term | Meaning |
| --- | --- |
| Advice Event | A specific AI suggestion, reply, opener, or next action shown to the user. |
| Outcome Event | The user's report of what happened after that advice. |
| Strategy Memory | A small, structured, confidence-aware lesson that can improve future advice. |
| Fact Memory | Stable information about a partner or user, such as interests, city, known context. |
| User Pattern Memory | Cross-partner coaching observations about the user's habits, strengths, and recurring blind spots. |

Examples:

| Type | Example |
| --- | --- |
| Fact Memory | `她喜歡貓`, `她住台中`, `她最近在忙課程` |
| Partner Strategy Memory | `她對輕微冷讀會接球，但太快邀約會變冷` |
| User Pattern Memory | `使用者容易在剛有熱度時解釋太多，適合短一點、留一點球給對方` |

## 3. MVP Product Loop

The MVP is a lightweight outcome loop, not a full relationship CRM.

Flow:

1. VibeSync gives a suggestion from Analyze, Coach 1:1, or Opener.
2. User either uses it, edits it, asks Coach, or does not send it.
3. Later, VibeSync asks one small question: `這步後來怎麼樣？`
4. User taps a quick outcome.
5. The app stores a structured event.
6. Future Coach 1:1 can use a small memory summary when confidence is high enough.

Outcome reporting should not deduct quota.

## 4. Entry Points

### v0.1 Required

Start with Coach 1:1 and Analyze because those are closest to actual interaction outcomes.

| Surface | Trigger | UI |
| --- | --- | --- |
| Coach 1:1 | After a formal coach answer | Small outcome card below the answer |
| Analyze result | After `本回合怎麼接` or AI recommended reply | Small outcome card near the bottom action area |

### v0.2 Candidate

Opener should join later. Opener is a pioneer move, but the meaningful outcome starts after the other person actually replies.

| Surface | Why later |
| --- | --- |
| Opener | Needs real reply before the coach can know whether the opener worked |
| Learning practice | Useful later, but not core to first memory loop |
| Report | Better as read-only summary, not first capture point |

## 5. Outcome UI

Suggested card copy:

```text
這步後來怎麼樣？
```

Quick chips:

```text
她有接
她冷回
她沒回
我沒送出
我改問教練
```

Optional note:

```text
補一句發生什麼事，讓教練下次更準
```

If user taps `她有接` or `她冷回`, show a follow-up CTA:

```text
補她回了什麼，重新分析
問教練怎麼接
```

UX rules:

- The card is optional and dismissible.
- Never nag every time.
- Do not block the user from continuing.
- Do not make it feel like homework.
- Reporting an outcome costs 0 quota.

## 6. Local Data Model v0.1

Capture should be local-first. Backend sync can come later only after privacy and retention rules are explicit.

```dart
class CoachingOutcomeEvent {
  final String id;
  final String? partnerId;
  final String? conversationId;
  final CoachingOutcomeSource source;
  final String? adviceId;
  final String? adviceType;
  final String suggestedMoveSummary;
  final UserAction userAction;
  final OutcomeSignal outcome;
  final String? outcomeTextPreview;
  final String? userNote;
  final DateTime createdAt;
}

enum CoachingOutcomeSource {
  opener,
  analyze,
  coach,
}

enum UserAction {
  sentAsIs,
  editedAndSent,
  didNotSend,
  askedCoach,
  unknown,
}

enum OutcomeSignal {
  engaged,
  cold,
  noReply,
  negative,
  pending,
  unknown,
}
```

Storage rules:

- Store only short summaries and user-reported outcome signals.
- Do not duplicate full raw transcripts into this event.
- If the underlying message already exists in the conversation, reference `conversationId`.
- If no `partnerId` exists, keep the event global/unbound and do not inject it into partner-specific prompts.

## 7. Strategy Memory Model

Outcome events are raw capture. Strategy memory is the consolidated layer.

v0.1 can capture events only. Prompt injection can wait until the data is clean.

v0.2 can add:

```dart
class PartnerStrategyMemory {
  final String partnerId;
  final List<String> positivePatterns;
  final List<String> negativePatterns;
  final List<String> pacingNotes;
  final List<String> effectiveStyles;
  final List<String> avoidMoves;
  final MemoryConfidence confidence;
  final int evidenceCount;
  final DateTime updatedAt;
}

class UserPatternMemory {
  final List<String> positivePatterns;
  final List<String> recurringBlindSpots;
  final List<String> effectiveStyles;
  final List<String> cautionPatterns;
  final MemoryConfidence confidence;
  final int evidenceCount;
  final DateTime updatedAt;
}

enum MemoryConfidence {
  low,
  medium,
  high,
}
```

Consolidation rule:

```text
Capture cheaply every time.
Consolidate only after enough evidence.
Inject only the smallest useful memory.
```

Recommended thresholds:

| Scope | v0.1 | v0.2 |
| --- | --- | --- |
| Partner | Capture events only | Consolidate after 3+ outcome events for the same partner |
| User | No cross-partner memory | Consolidate after 5+ outcome events across at least 2 partners |

## 8. Prompt Contract

Memory should make the coach sharper, not more overconfident.

### Coach 1:1

Best first place to use strategy memory.

Inject at most:

```text
Partner memory:
- She seems to respond better to playful low-pressure hooks than direct invitations. Confidence: medium.

User pattern:
- User often explains too much when nervous. Keep the next move shorter. Confidence: medium.
```

Rules:

- Max 3 bullets total.
- Include confidence.
- Use soft language when confidence is low.
- If memory conflicts with the current conversation, trust the current conversation.
- If mixed-person risk exists, do not inject partner strategy memory.

### Analyze-chat

Analyze should stay grounded in the current conversation first.

Allowed in later phases:

- Use memory to tune reply style.
- Do not let memory change factual scoring unless evidence is in the current conversation.
- Do not overfit one old outcome.

### Opener

Opener should use only opener-scoped or partner-scoped data that is clearly attached to the current partner.

Rules:

- Do not show A partner's opener draft on B partner.
- Do not inject old partner strategy if the opener was launched without `partnerId`.
- If input is only a screenshot profile, judge from the profile and current images first.

## 9. UX Placement

### Analysis Screen

Add a small outcome card after the main suggestion area:

```text
這步後來怎麼樣？
[她有接] [她冷回] [她沒回] [我沒送出]
```

### Coach 1:1

After a formal answer:

```text
如果你照這個方向試了，回來點一下結果，教練下次會更準。
```

### Partner Detail

Collapsible section:

```text
教練記得的互動模式
```

Example:

```text
她對輕鬆吐槽比較會接球。
太快邀約時容易變冷。
信心：中，來自 3 次回報。
```

### User Profile / Report

Later phase only:

```text
我的常見互動模式
```

This belongs in Report or settings, not the main conversation screen.

## 10. Privacy And Trust

User-facing copy:

```text
這些記憶只用來讓教練下次更準，不會自動替你發訊息。
```

Required controls:

- Clear outcome history for one partner.
- Clear all coaching memory.
- Deleting a partner must delete or unlink partner outcome events.
- If server sync is added later, show clear privacy copy before enabling it.

Do not:

- Store full Coach 1:1 chat as partner memory by default.
- Infer sexual intent, relationship status, or partner personality permanently from one event.
- Merge events across partners without a reliable `partnerId`.

## 11. MVP Build Order

Recommended implementation sequence:

1. Add local `CoachingOutcomeEvent` model and Hive storage.
2. Add unit tests for partner-scoped event isolation.
3. Add Coach 1:1 outcome card after successful formal answer.
4. Add Analyze outcome card after main suggestion.
5. Add read-only Partner Detail section showing recent outcome patterns.
6. Add simple deterministic summaries, no AI consolidation yet.
7. Only after dogfood confirms cleanliness, inject top 1-3 memory bullets into Coach 1:1.

Do not start with AI consolidation. First make capture clean and visible.

## 12. Dogfood QA

Minimum scenarios:

| Scenario | Expected |
| --- | --- |
| User reports `她有接` after a playful suggestion | Next Coach can mention that playful hooks worked with this partner |
| User reports `她冷回` after a direct invite | Next Coach lowers pressure and avoids pushing too fast |
| User taps `我沒送出` | Do not treat the partner as cold |
| User opens B partner after A partner outcomes | B does not see A's memory |
| User deletes partner | Partner outcome events are deleted or safely unlinked |
| Free user reports outcome | No quota deduction |
| Mixed-person warning exists | Partner strategy memory is not injected |

## 13. Open Questions

Before implementation, decide:

- Should v0.1 attach outcome reporting to Coach only, or Coach + Analyze?
- Should user notes be required before creating strategy memory?
- Should the user be able to edit strategy memory text directly?
- How many unresolved `pending` events should be shown before the app stops asking?
- Should strategy memory stay local-only for launch?
- When server sync exists, what is the retention policy?

## 14. Recommendation

Start with the smallest safe loop:

```text
Coach 1:1 formal answer -> outcome chips -> local event -> read-only partner summary.
```

Do not inject memory into prompts in the first PR.

After dogfood proves the capture is clean, add conservative Coach 1:1 prompt injection.

Success metric for the first dogfood phase:

```text
At least 60% of "她有接 / 她冷回" reports should make the next Coach answer feel more context-aware.
```
