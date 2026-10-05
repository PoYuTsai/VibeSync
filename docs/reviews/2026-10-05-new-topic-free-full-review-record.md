# 新話題對所有方案開放完整五題（ADR #52）：審查紀錄（2026-10-05）

- 分支 `claude/new-topic-free-full`，base `7c5cc523`。程式由 Claude（Anthropic）撰寫。
- Bruce 交辦原話：「開放免費用戶跟付費用戶一樣能用Token使用「新話題」的所有功能 請Eric做測試 並白話和他說明目前改動的重點」。
- R2／R3：付費、額度與權益投影。
- **主審（關卡）**：待 Eric 方、非 Claude 家族的獨立主審。
- 「預審」是同家族的對抗式預審，照 `docs/shared-agent-rules.md` 不算關卡。

| 輪 | 類型 | 審查 head | 回覆 sha256 | 結論 |
|---|---|---|---|---|
| 預審 1 | Claude 子代理，對抗式、唯讀 | 8cee74bf | f82e8007559ebfa7fe9dd9124c59cd4d52a36b4f5dbf318f56e563e130941c13 | APPROVED |

回覆 sha256 以下方回覆區塊的內容計算（UTF-8，不含外框）。

## 預審 1 的處理

| 編號 | 處理 |
|---|---|
| P3-1 測試說「照常扣 3 則」卻沒證明：settle mock 不管 `p_charge_quota` 都回 `charged: true`，`usage.cost` 又是常數 | **已修**。<br>• harness 記下送給 settle 的參數，mock 照 `p_charge_quota` 決定 `charged`。<br>• Free 測試直接驗 `p_charge_quota=true`、落帳投影是 `starter`、五題；方案矩陣也驗。<br>• 變異檢查：把 handler 改成「Free 不扣」，兩個測試會失敗。 |
| P3-1 附帶：第 5 步額度 429 與串流模式的 Free 投影沒有 handler 測試 | **不在這次範圍**。這兩條路徑這個 PR 沒動，也是改版前就有的缺口。 |
| P3-2 `docs/pricing-final.md` 第 89、107 行仍寫 Free 只看一題 | **已修**：兩處註明「由 ADR #52 取代（提案中）」。 |
| P3-3 ADR #52 只寫「每天最多 5 次」，實際卡住的是月額度 | **已修**：寫明「與分析等功能共用；只用新話題的話，每月最多 10 次、每天最多 5 次」。 |
| P3-4 `new_topic_replay_hit` 沒有 `subscriptionTier`；`subscriptionTier` 其實是有效方案 | **已修**。<br>• 兩處回放 log 都加 `subscriptionTier`，測試驗查帳回放與 claim 回放兩條路。<br>• ADR 改寫成「記當次的有效方案，測試帳號記 `essential`」。 |
| P3-5 與 `claude/new-topic-v23`（PR #93）的 ADR 文字會衝突 | **合併時處理**。程式沒有重疊；兩邊都在 ADR #50 後面加新 ADR，後合併的那張要解 `docs/decisions.md` 的衝突，已寫在 PR 說明。 |
| P3-6 App 的 `NewTopicAccess.servedTier` 之後可能被誤當成訂閱方案 | **另案**：寫進 ADR #52「未決」，清升級卡時一起加註解。 |

## 預審 1 回覆

````text
Read-only pre-review of `origin/main..claude/new-topic-free-full` (commits f6948df8 and 8cee74bf) in the worktree. I edited, committed and pushed nothing. I made a temporary mutation copy under `scratchpad/review-free/` and deleted it afterwards.

**Result: no P0, P1 or P2 findings. The core claims hold.**

**What I verified**
- **Charging is unchanged and does not depend on tier.**
  - `chargeQuota: !deps.accountIsTest` (new_topic_handler.ts:804) has no tier input. Settle runs once per claim, and a row that is already `done` returns `charged:false` (settle RPC in migration 20260724120000).
  - The step-5 quota gate (429 plus release, with RevenueCat refresh, handler.ts:463-507) and the settle quota-race path (:871-900) are untouched.
  - The generic month/day gates still skip new_topic.
  - The `PAID_TIER_SYNC_PENDING` gate (analyze_chat_handler.ts:515-545) runs before the handler and is unchanged.
  - Test accounts still get effectiveTier "essential", so they get the essential projection and are not charged.
- **Replay and hash.**
  - `computeNewTopicInputHash` does not include tier (new_topic_billing.ts:52-77). A retry across the deploy hashes the same way, so there is no new 409.
  - Old free one-topic rows still pass the TS validator (new_topic_payload.ts:610-627), the DB CHECK and the shipped Flutter parser.
  - New starter rows (limited false, 5 unlocked, 0 locked, 5 topics) pass the CHECK (20260724180000…sql:135-143) and `validate_new_topic_result`.
- **Stream mode and legacy mode both go through `completeNewTopicRequest`.** Step 10 is the only call site of `buildNewTopicLedgerResult`.
- **Old app builds handle the new response.**
  - `NewTopicResult.tryParse` accepts the starter shape (new_topic_result.dart:156-185).
  - The upsell card shows only when `access.isFree` is true (new_topic_view.dart:1177).
  - The client never stores results, never derives the user's tier from `servedTier`, and has no analytics on it.
  - No paywall copy promises the one-topic/five-topic split. Nothing in admin-dashboard, SQL or tools reads new-topic `servedTier`.
  - The logger passes metadata through unfiltered.
- **Tests.**
  - New-topic suites: 90/90 pass. The full CI "Edge contract tests" list: 1841 passed, 0 failed. `deno fmt --check` and `deno lint` are clean.
  - Mutation checks: both projection tests fail against the origin/main handler. The old-free replay test fails if the validator's `free` branch is removed. So the projection tests are real, not empty.

**Findings (all P3)**

**P3-1: The test claims "照常扣 3 則" but does not prove it.** new_topic_handler_test.ts:305-325 (especially :316 and :324), harness :110-118.
- The settle mock returns `charged: settleCharged` (default true) whatever `p_charge_quota` was sent.
- `usage: {cost: 3}` is a constant on every success body, replays included (handler.ts:272-279), so it proves nothing about charging either.
- Evidence: I changed handler.ts:804 to `chargeQuota: !deps.accountIsTest && newTopicSubscriptionTier !== "free"` and all 29 handler tests still passed. A regression that stops charging Free users would ship green.
- Fix: record the settle params in `run()` and assert `p_charge_quota === true`, `p_result_json.access.servedTier === "starter"` and `p_result_json.topics.length === 5`. Have the mock return `charged: params.p_charge_quota`.
- Older gaps, optional: no handler test for the step-5 quota 429 (the harness hardcodes limits 100/30 and usage 0), and no stream-mode handler test for the Free projection.

**P3-2: The pricing doc contradicts the change.** docs/pricing-final.md:89 (the feature-comparison row "只看最推薦 1 題（另 4 題升級解鎖）") and the :107 footnote.
- ADR #31 and #48 were annotated, but this pricing table was not. After merge it would say Free sees one topic while production serves five.
- Fix: in this PR, annotate the row and footnote with "由 ADR #52 取代（提案中）".

**P3-3: ADR #52's quota math leaves out the binding limit.** docs/decisions.md:1253 says "月 30 則、日 15 則，等於每天最多 5 次新話題".
- The numbers are correct (analyze_chat_handler.ts:162-172, _shared/quota.ts:18-28, app_constants.dart:23/28).
- But the monthly cap is what actually binds: at most 10 new-topic runs per month, shared with analysis, opener, coach and practice.
- Fix: state "每月最多 10 次、每天最多 5 次" so Eric sees the real ceiling for this pricing decision.

**P3-4: Telemetry gaps against ADR #52 decision 3.** new_topic_handler.ts:329-334 and :375-380.
- `new_topic_replay_hit` logs `servedTier` from the stored row, which is "starter" for Free rows written after the change. It has no `subscriptionTier`, even though decisions.md:1255 tells analysts to use `subscriptionTier`.
- `subscriptionTier` records the effective tier, not the real plan the ADR describes. Test accounts log "essential" because of analyze_chat_handler.ts:481 (`effectiveTier = accountIsTest ? "essential" : sub.tier`).
- Fix: add `subscriptionTier: normalizeSubscriptionTier(quota().effectiveTier)` to both replay-hit logs, and reword the ADR to say it records the effective tier (test accounts log essential).

**P3-5: Merge coordination with the sibling branch.**
- ADR #52 skips #51, which exists only on the open branch `origin/claude/new-topic-v23`.
- Both branches add a new ADR right after ADR #50 (decisions.md @@ -1243,0), so whichever lands second will get a text conflict.
- The code changes do not overlap. v23 touches handler lines 55-70, 170-191, 562-618 and 835-841, and test lines 3-14, 271-293 and 700+. This PR touches handler lines 49, 772-778 and 822, and test lines 55, 185, 202 and 289+.
- Fix: rebase whichever branch lands second.

**P3-6: Latent misreading of `servedTier` (no current impact).** new_topic_result.dart:41-47.
- `NewTopicAccess.servedTier` and `isFree` now describe the shape of the result, not the user's subscription.
- Nothing reads them today except the count check and the upsell card. Any future use as an entitlement check would treat Free users as Starter.
- Suggest adding a doc comment in the ADR #52 follow-up cleanup PR.

**Process note (not a code finding):** this is an R2/R3 payment and entitlement change, and ADR #52 is marked 提案. Merging still needs Eric's explicit product decision and a main review by a model family that wrote none of the code. This pre-review is not that gate.

**結論（繁中）**
程式面沒有 P0–P2。

- 免費用戶每次一樣扣 3 則，現在拿得到完整五題。
- 額度關卡、429、限流與重放雜湊都沒變。
- 改版前寫入的一題結果，24 小時內照常回放，不會變成 409 或 503。
- 新寫入的 starter 五題結果過得了資料庫 CHECK。
- 舊版 App 不用更新就看得到五題，也不會出現升級卡。

建議合併前補三件事：
1. 測試要驗 settle 有帶 `p_charge_quota=true`。現在的「有扣費」斷言是 mock 自己回的。
2. 同步 `docs/pricing-final.md` 第 89、107 行。
3. ADR #52 寫明免費用戶每月最多 10 次。

Eric 要決定的是採不採納 ADR #52 這個付費決定。合併並部署後，請用免費帳號在 iPhone 生成一次新話題，確認看到五張卡、沒有升級卡，而且額度少 3 則。

VERDICT: APPROVED
````
