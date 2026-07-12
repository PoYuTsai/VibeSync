# 練習室 typed-facts-v1 重構交接（Codex → CC 接手）

> 2026-07-12。分支 `codex/no-canned-practice-ai`。
> 目的：記錄 Codex 這批未 commit 重構的意圖、CC 接手時的狀態、以及 **CC 動了哪些檔、為什麼**，供 Codex 回審。

## 背景（Eric 原始需求）

1. beginner hint / game hint / debrief 三者品質不一致，要收斂。
2. 絕不再出爛 fallback 罐頭回應。
3. game hint 要真的高手。
4. 早期只補中文 regex 分析不是通用解：例如對方說「喜歡去某國旅行」，hint 點下去只會附和。

## Codex 已落地的架構（CC 未更動其設計）

- **雙模型生成**：DeepSeek 主生成，Claude 為 hint/debrief 的 **failover 生成器**（非驗證器）。chat 回覆只有 DeepSeek 同模型重試。
- **無罐頭契約**：`generated_only_source_test.ts` 硬性禁止 runtime 存在任何 `buildFallback*` / `*_fallback_used`；違反 fact grounding → reject → 重試 → 換 Claude → 全掛只回 `*_retryable`，絕不降級。
- **typed-facts-v1 品質層**（本批新增，無獨立設計稿，規格藏在測試裡）：
  - `hint_fact_ledger.ts`：從逐字稿抽 owner/domain/relation/anchor 事實 claim，**雙用**＝(a) 當 evidence 餵進 prompt、(b) 事後 `assertHintFactClaimsSupported` 逐欄比對模型輸出，捏造細節即 throw。
  - migration `20260712120000_practice_hint_quality_schema_version.sql`：legacy snapshot 版本閘，pre-version 快照可安全失效、不重扣費/重計次。
  - `HINT_QUALITY_SCHEMA_VERSION` / `DEBRIEF_QUALITY_SCHEMA_VERSION` = `"typed-facts-v1"`。

**注意**：Eric 記憶中「加第二個模型做驗證」並未落地——驗證始終是 regex fact ledger，Claude 只是 failover 生成器。是否要再加 LLM 驗證器：CC 建議**先不做**，等真實 dogfood 漏網案例再開新案（避免每次 hint 多一次模型呼叫的延遲/成本）。

## CC 接手時的狀態

Codex 中斷在一半：**它自己新加的規格測試有 7 個是紅的**（`deno test` 831 passed / 7 failed）。程式本體無 TODO、無切一半的函式，缺的是把 prompt/守門修到滿足新測試。

## CC 做了什麼（三處，全部只為讓 Codex 自己的新測試轉綠，未推翻任何設計）

### 1. `prompt.ts` — debrief+hint prompt 預算超標 32 字
- **根因**：Codex 新加 `maxDebriefWithHint > 5700` 界線（`prompt_test.ts:578`），但實際輸出 5732，且 20 個 SR 女角全擠在 5730~5732。
- **修法**：移除 `hintAssistedTurns` footer 開頭那段**沒有任何測試斷言的「列格式圖例」**（`列=[turnIndex,...]；"=o"...`）；保留其中 load-bearing 的 `decision＝server權威不可改寫` 指令（併入 footer 尾）。並把緊湊列的 `"=o"` 哨符改成自描述的 `"=origHint"`，這樣拿掉圖例後模型仍讀得懂。
- **效果**：max 5732 → 5618（margin 82，不 flaky）。零欄位/指令刪除。

### 2. `prompt.ts` — debrief 逐字稿把圖片佔位符砍斷
- **根因**：Codex 新的 `clippedDebriefTurn` 把每則 turn 砍到 16 字，但 `[image concept omitted]`（24 字）被砍成 `[image concept …`，測試 `prompt_test.ts:1085` 找不到完整佔位符。
- **修法**：`clippedDebriefTurn` 偵測到含 `IMAGE_CONCEPT_PLACEHOLDER` 時，effectiveLimit 至少為佔位符長度，佔位符不得中途截斷。對不含圖檔名的 turn（含 bounded 測試那批）行為完全不變。

### 3. `practice_visible_quality.ts` — echo 守門誤判「被否定的告白」
- **根因**：`GENERIC_ECHO_TAIL` 把任何以「記住/收到/懂了」結尾的句子當空泛附和。beginner failover 的 warmUp「…店名真的**沒記住**」結尾是**被否定**的誠實告白（沒記住店名），被誤判為 echo → `hint_quality_invalid_substantive_move` → beginner 整條掛掉（`index_test.ts:4747`）。**這正是 Eric「regex 不是通用解」的活例。**
- **修法**：`GENERIC_ECHO_TAIL` 前加否定 lookbehind `(?<![沒不未別])`——被否定的告白不算附和。這是**收緊誤判**、不是放寬守門，方向與 no-canned 一致。`practice_visible_quality_test.ts` 9/9 仍綠。

## 驗證證據

- practice-chat Deno 全套：**838 passed / 0 failed**（`--no-check`，見下）。
- Flutter practice_chat unit + widget：**536 passed / All tests passed**。
- practice_visible_quality_test.ts：9/9。

## 待辦 / 給 Codex 回審的點

1. **已知既有型別警告**（非本批引入）：`handler.ts:429` `timeoutHandle: number` 被 `setTimeout` 的 `Timeout` 型別打到，故全套用 `--no-check` 跑。HEAD/main 就有此警告、部署一直正常（Deno runtime 不受影響）。要清另開案。
2. 本批 **尚未 commit → 未雙審 → 未部署**。它動到 quota/計費 RPC 與 response schema（高風險），前一次 generated-only APPROVED **不涵蓋** typed-facts-v1，需重新雙審。
3. 部署順序沿用 `docs/reviews/2026-07-11-practice-generated-only-codex-review.md` 的 PENDING 流程：Edge-first → 舊 worker drain → 目標式 migration up → smoke。
4. CC 的三處修改請 Codex 特別看：(3) echo 否定 lookbehind 是否有反例（例如「不錯」這種「不」開頭卻是稱讚的詞——已確認 `不錯` 不在 ECHO_TAIL 詞表，只在 PRAISE 表，不受影響）。
