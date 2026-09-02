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

## 3c 進度（2026-09-03）

- 已交付（telemetry-only）：`_shared/social/candidate_guard.ts` 十五碼 violation 清單
  （replyMode↔卡數、決策↔action、variants action／balls 漂移、來源球不在盤點／略球／併球
  獨占／接球未覆蓋、五卡來源不一致、placeholder、問句／新話題／距離預算、聯想無路徑、
  no-send 藏卡），每道證據不足就不算檢查過（`checked`）；phase0 adapter 從 client 真正
  拿到的結果組輸入，隨 `stream_phase0_observability.candidateGuard` 出；evaluate.ts 每案
  印 guard 碼、彙總計數，不是 gate。輸出只有 code／style／sourceIndex／branchId。
- 現況限制：現行 v2 send 決策沒帶 action／selectedBallIds／newTopicCount／semanticDistance，
  那幾道在 production 會是「未檢查」；等 decision contract 補欄位自然接上。
- 待 Eric 決定（3c 後半）：§15.3 selected-candidate repair-first 的降級策略——哪些碼
  要進 repair（候選：skipped_ball_used／placeholder／no_send_with_cards）、bounded retry
  幾次、失敗降級 do_not_send／need_context 的條件；先看 dogfood 一週的 candidateGuard 分佈。

## 3d 進度（2026-09-03）

- 已交付（預設關閉）：`_shared/social/semantic_critic.ts` 共用引擎（嚴格 parser、usage
  解析、詞彙參數化）＋ Analyze 22 碼 rubric（Coach 九碼改回覆卡語境＋§15.2 十三碼＋繁中
  句型＋Alpha Guard 判準）；Coach `semantic_critic.ts` 改薄委派，prompt 字面與行為不變
  （86 測試綠）。`analyze-chat/critic_shadow.ts`：只審選中卡、跑在 `analysis.done` 之後的
  `EdgeRuntime.waitUntil` 背景，永不改結果、永不 throw；出 `stream_semantic_critic`
  （verdict／violations／token／延遲／trigger）＋ `ai_logs` 成本列（requestType
  `analyze_semantic_critic`）。離線評測 `tools/analyze-v2-blackbox/run_critic.ts`。
- Eric 2026-09-03 定案：模型用 Sonnet 5（約每次 1 美分，主分析約 +10–15%）；先跑離線
  評測再開影子。
- 離線評測首輪（2026-09-03，Sonnet 5，共 30 案、實花約 0.13 美元）：rewrite 9（36%／25%）、
  invalid 0、延遲 1.2–4.4s。抓對的：編造照片地點（unsupported_fact）、直接問題沒回答
  （goal／ball_mismatch ×2 案 ×2 輪）、連續兩問、答案沒放前面；誤判 1（零問句標
  question_density）；漏抓 1（run12 同樣的編造地點放行）。guard 違規只覆蓋 critic 發現的
  1/5，`risk` 觸發會漏掉大半 → 影子建議開 `always`（每個 send 約 0.5 美分）。
- 待 Eric 決定（開關是一行 commit：`ANALYZE_CRITIC_SHADOW`）：
  1. ~~模型~~（已定 Sonnet 5）。
  2. 觸發：`risk`（3c guard 違規、決策 beta flags、四張同開頭才審）或 `always`
     （每個 send 的選中卡都審，先建影子基線）。
  3. 先跑離線評測（run12／run13 共約 30 案，Haiku 幾分錢、Sonnet 約 0.3 美元）看
     critic 判得準不準，再開 production 影子；critic 不擋人，擋的設計等 3c 後半一起定。

## 3a 細節

- 語料：`corpus.ts` 每案 `{ id, family, messages, expect }`，`expect` 先只放能確定性判定的：可接受 `messageDecision` 集合、send 時是否預期計畫、`questionBudget` 上限。其餘（stage／action／balls／atoms）等 3c／3e 再加。
- gates（每案）：decision ∈ expect；no-send → 零 reply_option 且 done 無 replies；send → 五 style 各一次；plan observed（統計率，非單案硬 gate）；`sameOpeningCount = 0`；`questionBudgetExceeded ≠ true`；`branchExceedsCap = false`；attribution `invalidCount = 0`；client 無計畫本文；`elapsedMs ≤ 60000`；`output_tokens ≤ 6500`。
- 輸出：逐案表＋彙總 JSON；任一硬 gate 失敗 exit 1，讓 CI 之後能對「已存 artifact」跑（不打網路）。
