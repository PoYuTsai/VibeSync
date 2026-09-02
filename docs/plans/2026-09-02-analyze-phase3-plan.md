# Analyze Phase 3：語意審核與評測——切片計畫（2026-09-02）

規格 §15（Guardrail 與 Semantic Critic）、§19（語料與 release gates）、§21 Phase 3、§22.2。
Phase 2b 已上 main（`03b8f585`，Eric 接受 APPROVED_WITH_RISK）。Codex 留下的待辦一併排入。

## 切片（依序，每刀獨立可審可退）

| 刀 | 內容 | runtime 風險 | 需 Eric 決定 |
|---|---|---|---|
| **3a 評測器** | `tools/analyze-v2-blackbox/evaluate.ts`：讀黑箱 artifact，對照語料期望值與 §19.3 可確定性判定的 gates 打分（no-send 零卡、五 key 完整唯一、計畫存在率、同開頭、問句／新話題／距離預算、歸因 invalid、外洩、延遲、token）；語料抽成 `corpus.ts` 帶期望值；artifact 補強綁定（tree／dirty、實送 prompt hash、request 模型）。 | 無（工具） | 無 |
| **3b 五句雷同** | 先用 prompt 強化＋3a 度量迭代；若 prompt 到不了 0%，再議 selected-candidate repair（第二次小模型呼叫，+成本+延遲）。 | prompt（v2） | repair 呼叫要不要開 |
| **3c candidate_guard** | `_shared/social/candidate_guard.ts`：§15.2 第一層 hard gates 統一成 violation 清單（action／ball／replyMode／provenance／預算），先進 telemetry；selected candidate repair-first 路徑設計（§15.3）。 | Edge（analyze-chat） | repair-first 的降級策略 |
| **3d critic 泛化** | Coach `semantic_critic` 搬 `_shared`，加 Analyze 專屬 violations 與繁中句型；只跑選中候選＋高風險＋flags 命中；AI 成本遙測（critic 呼叫數／token）。 | Edge＋AI 成本 | critic 觸發條件與成本上限 |
| **3e 語料 128** | §19.2 十四類；我出草稿（含期望值），Eric 審；人工大頭。 | 無 | 每案期望值 |

完成定義（規格 §21）：release gates 自動化；每次 prompt／model／selector 變更有 decision diff。

## 3a 細節

- 語料：`corpus.ts` 每案 `{ id, family, messages, expect }`，`expect` 先只放能確定性判定的：可接受 `messageDecision` 集合、send 時是否預期計畫、`questionBudget` 上限。其餘（stage／action／balls／atoms）等 3c／3e 再加。
- gates（每案）：decision ∈ expect；no-send → 零 reply_option 且 done 無 replies；send → 五 style 各一次；plan observed（統計率，非單案硬 gate）；`sameOpeningCount = 0`；`questionBudgetExceeded ≠ true`；`branchExceedsCap = false`；attribution `invalidCount = 0`；client 無計畫本文；`elapsedMs ≤ 60000`；`output_tokens ≤ 6500`。
- 輸出：逐案表＋彙總 JSON；任一硬 gate 失敗 exit 1，讓 CI 之後能對「已存 artifact」跑（不打網路）。
