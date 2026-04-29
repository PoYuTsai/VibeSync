# Memory Coach Spec 3 Draft: Partner Data Quality Guard

> Status: rough draft, not ready for implementation
> Date: 2026-04-30
> Depends on: Partner Entity A2 + dogfood findings
> Parent roadmap: `docs/plans/2026-04-30-vibesync-memory-coach-roadmap.md`

## 1. Goal

Protect partner memory from being polluted when conversations from different people are placed under the same Partner card.

This is a trust-boundary feature. It protects Layer 2 memory before Layer 4 coaching relies on it too heavily.

## 2. Problem

Partner traits and partnerSummary are aggregated from all conversations under one Partner.

If the user accidentally puts conversations from different people into the same Partner card:

- Partner traits become mixed.
- Long-term memory becomes unreliable.
- Future AI advice can become wrong.
- Coach Action Cards may recommend the wrong next step.

## 3. Product Principle

Do not blame the user.

Use language like:

```text
這張對象卡裡的幾段紀錄看起來可能不是同一個人，要整理一下嗎？
```

Avoid:

```text
你放錯了
資料錯誤
AI 判定不是同一人
```

## 4. Detection Ideas

Potential signals:

- Different extracted partner names / nicknames across conversations.
- Conflicting notes or traits.
- Different platform transitions that do not look connected.
- Large contradiction in message style or identity clues.
- User manually reassigns a conversation away from a partner.

Important: These are weak signals. The app should not claim certainty.

## 5. Guard Behavior

If confidence is low:

- Show a non-blocking warning in PartnerDetail.
- Let user inspect suspicious interaction records.
- Offer quick actions:
  - Move this record to another partner.
  - Create a new partner from this record.
  - Ignore for now.

If data quality is questionable:

- Consider lowering confidence of partner aggregate memory.
- Consider not injecting polluted aggregate into AI prompt, or adding a caveat.

Do not silently delete or auto-split records.

## 6. UI Draft

PartnerDetail banner:

```text
這張對象卡可能混到不同人的紀錄
為了讓特質和建議更準，建議整理一下
[查看]
```

Record-level hint:

```text
這段互動看起來可能屬於另一個對象
[移到其他對象] [另存成新對象]
```

## 7. Non-Goals

- Do not build full identity resolution.
- Do not claim the AI can prove whether two screenshots are the same person.
- Do not block users from saving.
- Do not use photos to diagnose personality.
- Do not auto-merge or auto-split.

## 8. Open Questions For Brainstorm

1. What signals are reliable enough for v1?
2. Should the guard run client-side, server-side, or both?
3. Should suspicious partnerSummary be excluded from prompt injection?
4. What is the lowest-friction recovery flow?
5. How do we explain uncertainty without making users distrust the app?
6. Should this ship before Coach Action Loop v1?

