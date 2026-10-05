# 新話題提示詞 v2.3（ADR #51）：審查紀錄（2026-10-05）

- 分支 `claude/new-topic-v23`，base `7c5cc523`。程式由 Claude（Anthropic）撰寫。
- Bruce 交辦原話：「實作這v2.3版 開PR」「請Eric做測試 並白話和他說明目前改動的重點」。
- R2：AI 提示詞與 `analyze-chat` 生成路徑，影響 production 全部新話題。
- **主審（關卡）**：Eric 方的獨立主審。
  - 第 1 輪 BLOCKED，審查範圍 `7c5cc523 → ec6b926e`。
  - 補件後，Eric 方在付費前做了唯讀預檢（head `d8abb6d2`），退回補評測工具四項。預檢不是正式第 2 輪，也不改第 1 輪結論。
  - 付費評測與盲測判分完整後，由同一主審做第 2 輪差異複核。
- 「預審」是同家族的對抗式預審，照 `docs/shared-agent-rules.md` 不算關卡。

| 輪 | 類型 | 審查 head | 回覆 sha256 | 結論 |
|---|---|---|---|---|
| 預審 1 | Claude 子代理，對抗式、唯讀 | 845b570f | 09a9e3eab6a73c28f53d65b0088b6b53a6156fdb3e753acf17efbe2f4f529567 | APPROVED_WITH_RISK |
| 主審 1 | Eric 方獨立主審（[PR #93 留言](https://github.com/PoYuTsai/VibeSync/pull/93#issuecomment-5987751198)） | ec6b926e | 9b80db8a522feff97be14b5cf6d1a8629af82740b2c270770e741f07a0afce36 | BLOCKED |
| 付費前預檢 | Eric 方唯讀預檢（[PR #93 留言](https://github.com/PoYuTsai/VibeSync/pull/93#issuecomment-5988587412)），不算正式第 2 輪 | d8abb6d2 | — | 退回補評測工具（四項 P2） |

- 預審 1 的回覆 sha256 以下方節錄區塊的內容計算（UTF-8，不含外框）。
- 主審 1 的兩個 sha256 照 PR 留言抄錄：
  - 主審原文：`9b80db8a…`。
  - packet manifest：`2963005fb422039bdceb215d4e29b1abe8428c499696f46ce588a39934982510`。

## 主審 1 的補件對照

主審 1 的結論：
- 沒有新增 P0／P1 程式錯誤。
- WSL 本機 244 個相關測試通過，三項必要 CI 全綠。
- 扣費、重播、Free 投影與失敗保護沒有新增回歸。
- P2：原訂的正式品質驗收還沒做。

| 主審要求 | 處理 | 在哪裡 |
|---|---|---|
| 1-1 評測工具測不到 v2.3 基本模式：沒帶 `topicContext` 的案例被拒，legacy 臂走舊提示詞 | **已補**。候選臂呼叫 `planNewTopicPrompt`，跟 handler 是同一個函式，基本與進階都走 production 路由。案例照規格 §6.2 補到 22 組：<br>• 什麼都不選：B1、B2<br>• 只選狀況：B5、B6（B6 剛約完會）<br>• 沒有對象資料：B4<br>• 素材「幫我想」：N1、N2<br>• 有互虧依據：B3、J1<br>• 紅燈收尾：E2、W1 | `cdeb9b92`、`b8340e9b`；`cases.json` v2 |
| 1-2 沒傳 `today`；參數要對齊正式路徑；要免費乾跑與相符性測試 | **已補**。<br>• 「今天」用 `--now` 固定，預設 `2026-10-05T12:00:00+08:00`。<br>• request body 照 `fallback.ts` 第一跳：`claude-sonnet-5`、`max_tokens` 3000、thinking 關閉、system 快取區塊、同一組 header。<br>• `run_test.ts` 攔下實際送出的 body 與 header 來比對。<br>• 乾跑數字見規格 §0.1。 | `b8340e9b` |
| 1-3 基準取 `7c5cc523`、保留當時真實行為；同案例、requestId、重複次數配對 | **已補**。用 `git archive` 取出 `7c5cc523` 的 `supabase/functions`，照當時 handler 路由：沒帶 `topicContext` 走舊版，帶了走進階 v1，角度用舊清單。兩臂同案例、同 requestId、同重複次數。 | `b8340e9b` |
| 2-1 乾跑、呼叫數與費用上限；付費前要 Eric 當次核准 | **乾跑完成，等 Eric 說「跑」**。<br>• 88 次呼叫。<br>• 估一般 US$2.38、最壞 US$3.97。<br>• 上限 `--max-calls=88 --budget-usd=4.5`。 | PR 留言 |
| 2-2 可核對的證據：head、模型／參數、提示詞與案例 sha256、原始結果、usage／成本、盲測與解盲、逐項門檻；基本／進階分開；推薦題單列 | **工具已能產出；證據要付費評測跑完才有**。<br>• `manifest.json`、`system-prompts.json`、`prompts.json`<br>• `records.json`：含 usage 與快取<br>• `summary.md`：全部／基本／進階分開<br>• `blind_ab.md`<br>• `blind_star.md`：推薦題單列<br>• `explanations_blind.md`、`reveal-map.json`<br>• `acceptance.md`：`tally.ts` 產出 | `tools/new-topic-two-stage-eval/README.md` |
| 2-3 六個 production 稽核計數另案的範圍；不能拿既有 log 當自然度的證明 | **範圍寫清楚**。<br>• 六個字面計數已在評測的 `summary.md`，對應 §6.5 第 5、6 項。<br>• 進 production 稽核仍另案。<br>• 自然度、願意直接傳、有趣只看盲測。<br>• 既有 log 只用來上線後監看。 | 規格 §0.1、ADR #51 |
| 3-1 ADR #51、規格 §0.1、PR 寫進產品裁決、驗收方式與理由；主審狀態更新成本輪結果 | **已補**。<br>• ADR #51「產品裁決」三點：共用 v2.3、基本模式不建議約她、保留盲測當關卡。<br>• 規格 §0.1：已做／另案、評測工具與 §6.1 的差異、乾跑數字。<br>• 本紀錄與 PR 說明。 | 本 commit、PR 說明 |
| 3-2 要改驗收門檻須另列 | **不改門檻**。<br>• 沒跑的項目不標通過。<br>• 盲測多一欄「★ 尷尬」與一份 `blind_star.md`，是為了判定原訂的第 2 項與 Free 只看推薦題，不是新門檻。 | 規格 §0.1 |
| 3-3 推同一張 PR、最終 head 的必要 CI 通過、準備好再標 Ready、下一手換回 `next:eric-ai`、附補件對照 | 推同一張 PR，補件對照貼在 PR 留言。<br>• 付費評測還沒跑，所以維持 Draft。<br>• 下一手換成 `next:eric-ai`，請 Eric 決定要不要「跑」。<br>• 跑完：Bruce 做盲測，`tally.ts` 判門檻，結果補進 PR，再標 Ready 交第 2 輪。 | PR #93 |

主審 1 對三個產品建議的處理：
- 都由 Bruce＋Claude Code 裁決採用，理由寫在 ADR #51「產品裁決」。
- 基本模式不建議約她（D9）：`summary.md` 計算 B1–B6 的邀約字眼；其中 B6（剛約完會）最容易出現。

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

## 付費前預檢的處理

預檢結論：基本／進階路由、固定基準、固定日期、主呼叫參數與三項產品決策都已補齊；248 項本機 Deno 測試與三項必要 CI 全過。付費前要先補下面四項 P2，並附免費反例測試。

| 預檢要求 | 處理 | 反例測試 |
|---|---|---|
| 1 資料不完整不能寫成全部通過：`tally.ts` 只走解盲表、沒有「不有趣」紀錄就當指定案例有趣；只有 B1 一對成功時仍得到「全部通過」 | **已修**（`cc7f5694`）。<br>• `completenessProblems` 交叉核對 manifest、records、解盲表與三份盲測，要對得上 22 組 × 2 次 × 兩臂。<br>• 下列情況都列出來：沒跑完、只跑部分案例或一臂、不是 2 次、案例檔換過、工作樹不乾淨、呼叫數不是 88、模型沒回、組別缺少／重複／多出、甲乙不是一邊一臂。<br>• 有任何一項：`acceptance.md` 整份標「未完成」、每一項都不給 ✓／✗，指令以失敗結束。<br>• B3、J1、E3 兩次都要有候選評分而且有趣，缺一組也不算過。<br>• `summary.md` 也加「正式驗收資格」。 | 預檢反例（88 筆只有 B1 一對成功）得到「未完成」；原本「缺案例算過」的測試改成鎖住「沒有評分」；另測完整時才可能「全部通過」，以及各種不完整 |
| 2 預留漏算快取寫入價：預留用一般 input 單價，實付用快取寫入價，預算等於預留時會超額 | **已修**（`cc7f5694`）。<br>• 預估與預留的 input 一律用最高的快取寫入價（$2.5/M），output 用 `max_tokens` 全滿。<br>• 單價從模型查同一組，查不到就失敗。<br>• 每字 token 數用實測校正，只升不降。<br>• README 寫明預算是依估計守門、不是嚴格上限；每次的預留與「實付是否超過預留」都記下，`summary.md` 列次數。<br>• 重新乾跑：88 次，一般 US$2.71、最壞 US$4.30（原本 US$2.38／US$3.97）。 | 預檢反例（一般 100、快取寫入 7,898、output 全滿）在新預留之內、超過舊預留；usage 各種分法都不超過預留；校正與守門 |
| 3 只壞在解釋欄時，五句開場句從盲測消失 | **已修**（`cc7f5694`），照規格 §6.1。<br>• 「開場句可評」與「可交付」分開。<br>• 只壞在解釋欄：五句與 ★（主呼叫的推薦）照樣進盲測與開場句指標，可交付率照實不算，解釋那份標「沒有可評的解釋」。<br>• ★ 解釋的兩項（標題手法字、夾英文）只算可交付。<br>• 不另打修格式呼叫。 | 預檢反例（五句不同、只有標題重複 → `topic_duplicate`）：五句與 ★ 都在盲測、可交付 0、開場句可評 1 |
| 4 零對零通過與門檻不一致 | **裁決保留並寫明**（ADR #51 產品裁決 4）。<br>• 基準已是 0 時，嚴格小於做不到，等於替兩版都沒有的問題擋上線。<br>• 剩餘風險：這種情況下這一項看不出改善，改看盲測第 2 項。<br>• 已同步規格 §6.5 第 5 項、§0.1、ADR #51、`summary.md` 與 `acceptance.md` 的標題。 | 四種組合：0／0 過、0／1 不過、2／2 不過、2／1 過 |

變異檢查：第 1–3 項改回原本的行為、第 4 項拿掉例外，對應的測試都會失敗；把「B3／J1／E3 缺評分」改回算過，測試也會失敗。

另外順手修了 `run.ts` 裡我自己寫的一處 `deno lint` 警告（`typeof` 比對變數）。
