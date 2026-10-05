# 新話題提示詞 v2.3（ADR #51）：審查紀錄（2026-10-05）

- 分支 `claude/new-topic-v23`，base `7c5cc523`。程式由 Claude（Anthropic）撰寫。
- Bruce 交辦原話：「實作這v2.3版 開PR」「請Eric做測試 並白話和他說明目前改動的重點」。
- R2：AI 提示詞與 `analyze-chat` 生成路徑，影響 production 全部新話題。
- **主審（關卡）**：待非 Claude 家族（例如 Codex）。
- 下表只是同家族的對抗式預審，照 `docs/shared-agent-rules.md` 不算關卡。

| 輪 | 類型 | 審查 head | 回覆 sha256 | 結論 |
|---|---|---|---|---|
| 預審 1 | Claude 子代理，對抗式、唯讀 | 845b570f | 09a9e3eab6a73c28f53d65b0088b6b53a6156fdb3e753acf17efbe2f4f529567 | APPROVED_WITH_RISK |

回覆 sha256 以下方節錄區塊的內容計算（UTF-8，不含外框）。

## 預審 1 的處理

| 編號 | 處理 |
|---|---|
| P2-1 規格 §6.5 的付費盲測沒跑；評測工具還不能評「v2.3＋沒帶 topicContext」 | **交 Eric 決定**：說「跑」（先改版評測工具，基準取 `7c5cc523`），或明確接受以 iPhone 驗收＋上線 log 當關卡。已寫進 ADR #51「未決」與 PR 說明；評測工具 README 加註。 |
| P2-2 每句要「為什麼現在說」，提示詞卻沒有日期，會猜錯季節 | **已修**：使用者提示詞加「今天（台灣時間）」段（`newTopicTodayLabel`，不進重放指紋），附跨午夜測試。 |
| P3-1 (a) whyItWorks 例句「你們已經會互虧才適合」可能被拿來替沒依據的玩笑找台階 | **不改**：這是規格 D7 已確認的寫法（需要條件時寫出來）。系統提示詞另有互虧依據的硬規則；上線看稽核與 iPhone 實測。 |
| P3-1 (b) 推薦規則認「局面、素材或作戰板」的默契，互虧規則只認素材與作戰板 | **不改**：推薦那句講的是「要靠默契才成立的玩笑」，局面（例如想更靠近＋她很投入）本來就能給默契；互虧口吻仍受互虧規則限制。 |
| P3-1 (c) 自檢③「沒根據的判斷」與「不替她的個性、身分、能力下判斷」看似矛盾 | **不改**：兩條各管一層。人格、身分、能力一律不判斷；小選擇、小習慣要有作戰板根據。③抓的是後者。 |
| P3-1 (d) 兩組「三件事」，紅燈例外沒說是哪組 | **不改**：例外寫在「好的第一則」段內，指同段的三件事；v2 起就是這樣。 |
| P3-2 新角度可能誘發編造用戶經歷 | **已修**：角度段加「也不編用戶在做、在聽或在追什麼」。 |
| P3-3 失敗事件與 ai_logs 只有模式、沒有版本 | **已修**：兩者都帶 `promptVersion`，測試鎖住。 |
| P3-4 過時的註解與文件 | **已修**：`prompt_leak.ts` 註解、評測工具 README 與 `run.ts` 註解；規格 §0.1 補回退方式（revert 整個 PR）與上線該看的 log；CI 補 `tools/new-topic-two-stage-eval/run_test.ts`；ADR #51 補 D9 與日期；ADR #48 註明 #51 仍是提案。 |
| P3-5 測試缺口 | **已修**：基本模式回放不記稽核；基本模式 sentinel 擋下時會 release claim。 |

## 預審 1 回覆（節錄重點）

````text
Pre-review of origin/main..claude/new-topic-v23 (head 845b570f). Read-only.
Claims checked: all five hold (grounding section byte-identical, 6 iron rules, sentinel present; basic mode routes to v2.3 with null topicContext; angles replaced in place; telemetry basic/advanced + promptVersion, audit for basic mode, leak coverage not reduced; billing/payload/index/handler-shell unchanged, computeNewTopicInputHash excludes prompt/angle/version so no 409 across deploy; red-close only with topicContext).
Basic-mode prompt scan: 150 prompts, no enum code, no 「球」, no customer-explanation-guard word; 「我們」 line matches allowsNewTopicSharedFrame(null).
Numbers reproduced: 4,435 vs 4,339 (+96); cap 4,742 incl. directive; basic-mode input +223–339 (before the date line).
Tests: 148 new-topic/customer_explanation/eval + 93 index/ai_logs/prompt_leak_guard pass; deno check passes; no test deleted.
Log consumers: nothing in repo filters on promptVariant / two_stage_v1 / new-topic-two-stage-v1.
P2-1 acceptance gate (§6.5 paid blind eval) skipped; eval tool cannot run basic-mode v2.3.
P2-2 why-now required but no date in prompt; seasonal hooks can be wrong.
P3-1 wording loosening joke basis (a–d). P3-2 new angles invite invented user experiences. P3-3 failure events / ai_logs lack promptVersion. P3-4 stale comments/docs. P3-5 test gaps.
No P0/P1. Same-family pre-review; R2 still needs a non-Claude main review.
VERDICT: APPROVED_WITH_RISK — P2-1 and P2-2 need Eric's explicit risk acceptance or a fix.
````
