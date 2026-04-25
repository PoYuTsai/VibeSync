# AI Arbitration Queue

> Purpose: a shared handoff + review + debate queue for Daisy, Claude, and Codex.
> Use this instead of free-form bot-to-bot chat.

## When To Use

Use this file when:

- Claude and Codex need a live handoff between work rounds
- Claude finished a DC / mobile-driven bugfix or partial feature and Codex may later review or continue it
- Codex finished a hardening / review pass and wants Claude to sanity-check product or UX impact
- Claude wants Codex to review a concrete bug, risk, or architecture tradeoff
- Codex wants Claude to sanity-check UI, product, or copy direction
- Daisy wants one place to see the current disagreement, evidence, and next action

Do not use this file for:

- ordinary commit summaries
- bug history
- ADRs that are already settled
- every tiny commit as a separate entry

Those still belong in `git log`, `docs/bug-log.md`, or `docs/decisions.md`.

## Ground Rules

1. One queue item = one decision or one concrete blocker.
2. One task keeps one live item. Update the existing item instead of appending a new one for every small round.
3. Newest open item goes on top.
4. Each side gets at most 2 rounds before escalating to Daisy.
5. Every claim about "safe", "faster", or "better" must cite evidence:
   - file path
   - commit hash
   - test result
   - benchmark
   - official doc
6. Product taste, UX preference, and business priority are Daisy-final.
7. No free-form bot loop:
   - Claude writes one structured position
   - Codex replies with one structured position
   - if still split, mark `Status: WAITING_ON_DAISY`
8. If the work is only a handoff and not a disagreement, still record:
   - latest commit
   - changed files or scope
   - tests run
   - open risks
   - next ask for the other agent
9. Keep only open items plus a few recently closed items. Once the durable record exists elsewhere, prune old closed entries.

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
Request-Type: handoff | review | arbitration
Raised-By: Claude | Codex | Daisy
Owner: Claude | Codex | Daisy
Scope: bug | review | architecture | product | copy | ops
Branch/Commit: `commit-hash` or `working-tree`

Question:
- What exact decision or blocker needs arbitration?

Context:
- Short factual setup only.

Changed:
- What changed in this round?

Evidence:
- [path-or-doc](../path.md) or `commit-hash`
- Test / runtime observation

Open-Risks:
- Pending

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
- If Claude is operating through Discord / mobile-driven sessions, update this file at the end of each meaningful round that Codex may later need to continue or review.
- If Codex finishes a pass and wants Claude to sanity-check it later, update the same item instead of opening a parallel summary.
- If Daisy asks for a recommendation, end with a single recommended path.
- If the issue becomes a lasting rule, move the final outcome into:
  - `docs/decisions.md` for ADR-level decisions
  - `docs/bug-log.md` for recurring bug traps
  - `AGENTS.md` only for short-lived operating rules
- This file is a live queue, not a changelog.

---

## Live Queue

## [2026-04-25] Partner Entity Refactor — Design Spec Review
Status: IN_REVIEW
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: architecture
Branch/Commit: `working-tree`（design 即將 commit）

Question:
- 9-10 天 / Big Bang refactor 的 design spec 是否設計合理？是否有架構級瑕疵 / 風險未防護？

Context:
- Bruce 2026-04-25 測試期發現「同對方多段對話特質碎裂」（`Conversation` 無 partnerId）
- Eric 拍板 Phase A 全面重構（不延後到送審後），接受 ~2 週送審延誤
- Brainstorm 5 個關鍵決策已鎖定：IA 2 層 / Migration B / Aggregation A Union / AI Context C Hybrid / Report D
- Phasing：A1 (1.5 天 Schema+Migration) → 驗證 → A2 (7-8 天 UI+AI summary+Merge UI)

Changed:
- 寫了 `docs/plans/2026-04-25-partner-entity-design.md` 完整 design（6 sections + Phasing + Codex Review Request）
- 加 ADR-15 到 `docs/decisions.md`
- CLAUDE.md / AGENTS.md 「📚 Docs 指路」加入新 design 與 ADR 編號更新
- 取代 `memory/reference_testing_phase_feature_queue.md` Item #2（escape hatch button）

Evidence:
- [Design doc](../plans/2026-04-25-partner-entity-design.md)
- ADR-15 in `docs/decisions.md`
- Brainstorm 對話完整保留在 Discord channel `1488034916481368147` 2026-04-25 09:00–09:35 區段

Open-Risks（請 Codex 優先掃）:
1. Hive `typeId=5` 全 repo 真沒衝突？(`grep -rn 'typeId:' lib/`)
2. `Conversation @HiveField(15)` 真沒被舊版佔用？
3. Migration race conditions（強關 App / 切帳戶 / OOM）graceful 是否真 graceful
4. Riverpod auto-invalidate 鏈會不會 thrash UI（每次 Conversation 改動 N Partner provider invalidate？）
5. Partner summary token worst-case（30 段對話）會不會爆 prompt（**Free Haiku tier 特別注意**）
6. 9-10 天估算 sanity check（哪些子任務低估 / 高估？）
7. 測試 coverage gap（特別 integration test 範圍夠嗎？）

Claude-Position:
- Spec 大方向對：IA / Migration B / Union / Hybrid context 都是合理設計
- 技術風險集中在實作細節（Hive schema / Migration / Riverpod 連動），不是整體方向
- 推薦 A1 / A2 切分隔離 migration blast radius

Codex-Position:
- 待 review

Verdict:
- Pending（等 Codex review）

Daisy-Decision:
- Eric 已拍板 Phase A 全面重構（2026-04-25 09:35），等 Codex spec review verdict 後決定下一步動作

Action-Items:
- [ ] Codex 執行 spec review（範圍全 design doc，特別 Section 1/3/5/6）
- [ ] Verdict 寫進本 item Codex-Position 欄
- [ ] 🟢 PASS → Status: APPROVED，開新 Claude session 寫 A1 implementation plan（用 `superpowers:writing-plans`）
- [ ] 🟠 architectural alternative → 標 `Verdict: Daisy-Decision-Needed`
- [ ] 🔴 Critical flaw → 開 `docs/reviews/2026-04-25_partner-entity-design_codex-review.md` 列問題，spec 修完再 review

Close-Condition:
- Codex 給 verdict + 必要 spec 修訂完成 + A1 implementation plan 開始才能標 CLOSED
