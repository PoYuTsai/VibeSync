# AI Arbitration Queue

> Purpose: a shared handoff + debate queue for Daisy, Claude, and Codex.
> Use this instead of free-form bot-to-bot chat.

## When To Use

Use this file when:

- Claude wants Codex to review a concrete bug, risk, or architecture tradeoff
- Codex wants Claude to sanity-check UI, product, or copy direction
- Daisy wants one place to see the current disagreement, evidence, and next action

Do not use this file for:

- ordinary commit summaries
- bug history
- ADRs that are already settled

Those still belong in `git log`, `docs/bug-log.md`, or `docs/decisions.md`.

## Ground Rules

1. One queue item = one decision or one concrete blocker.
2. Newest open item goes on top.
3. Each side gets at most 2 rounds before escalating to Daisy.
4. Every claim about "safe", "faster", or "better" must cite evidence:
   - file path
   - commit hash
   - test result
   - benchmark
   - official doc
5. Product taste, UX preference, and business priority are Daisy-final.
6. No free-form bot loop:
   - Claude writes one structured position
   - Codex replies with one structured position
   - if still split, mark `Status: WAITING_ON_DAISY`
7. Close the item once the action lands or Daisy explicitly rejects it.

## Status Values

- `OPEN`
- `IN_REVIEW`
- `WAITING_ON_DAISY`
- `CLOSED`

## Queue Template

Copy this block for each new item:

```md
## [YYYY-MM-DD] Short Title
Status: OPEN
Raised-By: Claude | Codex | Daisy
Owner: Claude | Codex | Daisy
Scope: bug | review | architecture | product | copy | ops

Question:
- What exact decision or blocker needs arbitration?

Context:
- Short factual setup only.

Evidence:
- [path-or-doc](../path.md) or `commit-hash`
- Test / runtime observation

Claude-Position:
- Pending

Codex-Position:
- Pending

Verdict:
- Pending

Daisy-Decision:
- Pending

Action-Items:
- Pending

Close-Condition:
- What must happen before this item becomes CLOSED?
```

## Working Norms

- Claude should lead UI / Flutter / copy / product framing items.
- Codex should lead bugs / performance / architecture / code review items.
- If Daisy asks for a recommendation, end with a single recommended path.
- If the issue becomes a lasting rule, move the final outcome into:
  - `docs/decisions.md` for ADR-level decisions
  - `docs/bug-log.md` for recurring bug traps
  - `AGENTS.md` only for short-lived operating rules

---

## Live Queue

No open items.
