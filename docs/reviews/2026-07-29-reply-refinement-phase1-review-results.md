# 回覆微調 Phase 1 — 跨模型審查結果

日期：2026-07-29
審查標的：分支 `claude/reply-refinement-design-v2`，基準 `main`
審查時的 HEAD：`e5d0687d`（審查後修復推進到 `8881b0ad`）

審查者：

- **Codex（gpt-5.6-sol）** — 對抗式讀碼審查，唯讀 sandbox、ephemeral session。完整 diff（lib/supabase/test，188KB）。
- **GLM-5.2** — 獨立 falsification pass，針對免費額度與 exactly-once 的五條具體主張要求反證。緊湊封包（24KB）。

第一次送 GLM 的完整 diff 封包（192KB）逾時取消，改以緊湊封包重跑成功。兩份審查皆為唯讀，工作樹未被審查者修改。

---

## 總裁決

**通過，附六項已修復。** 沒有任何一條被判定為「方向錯誤、需要重新設計」；六條全是實作層缺口，都已修復並各自附可執行證據。

Codex 提的兩條「不確定項」中，一條回原始碼**證偽**，一條屬於設計階段已拍板的既有立場。

---

## 已修復（六項）

| # | 來源 | 等級 | 問題 | 修復 commit |
|---|---|---|---|---|
| 1 | Codex | BLOCKER | 同一 `requestId` 的**並行**重試會重複吃掉免費次數 | `25826be4` |
| 2 | Codex | BLOCKER | 面板尚未呈現就清掉付費身分，已付結果可能永久失去 replay 身分 | `d77ab113` |
| 3 | Codex | P1 | 送出失敗後仍宣稱「今天還有 N 次免費」，扣費前揭露錯誤 | `93ff7da6` |
| 4 | Codex | P2 | 額度 RPC 故障被記成「拿到了免費授權」，白送次數在 telemetry 上看不出來 | `e5d0687d` |
| 5 | GLM | Minor | `p_request_id` 可為 NULL＝留一條完全沒有去重的靜默路徑 | `8881b0ad` |
| 6 | GLM | Uncertain | `v_today` 在進入函式時求值，鎖上等到跨日會把計數滾回昨天並歸零 | `8881b0ad` |

### 1. 並行同 requestId 重複消耗免費額度

同 `requestId` 的兩個併發請求都會通過 replay preflight（ledger 尚未寫入），各自打模型、各自呼叫額度函式。ledger 只結算一次（`ON CONFLICT DO NOTHING`），免費計數卻被扣兩次。

修復：新增 `refine_free_claims`（PK `(user_id, request_id)`）作為冪等鍵。**順序是全部**：先取 `refine_free_allowance` 的 row lock，再查 claim；重複的 requestId 會在鎖上等到前一筆 claim 已 commit。

證據（本機 PG）：六個並行連線送同一 requestId → `used_count` 由 6 降為 **1**、claim 恰一列；六個並行送不同 requestId 搶最後一格 → 仍**恰好 1 個** granted。

### 2. 先存得回來，才清掉付費身分

面板是可下滑關閉的 route，使用者可能在等待中就關掉它。原本先 `markSuccess` 再寫本機暫存，暫存失敗就等於 requestId 永久消失，下一次只能鑄新的再扣一次。

修復：改成暫存成功才 `markSuccess`；失敗保留 pending，同一份輸入的下一次送出走 replay。

### 6. 日界競態

`v_today` 原本在進入函式時求值。23:59:59 進來的呼叫可能在 row lock 上等到跨日，醒來後把贏家已滾好的 `day_utc` 判成「不對」，把計數滾回昨天並歸零——白送一整輪十次。改成拿到鎖之後再讀一次時鐘。

純跨午夜的重現需要動系統時鐘，未執行；已驗證的是「鎖上等待後醒來會重讀時鐘」這條路徑，並以 contract test 鎖住 `v_today :=` 必須在 `FOR UPDATE` 之後、`IF v_day <> v_today` 之前。

---

## 證偽（不修）

### Codex Uncertain-1：付費 quota preflight 可能被競態繞過

**證偽。** Codex 沒拿到 settlement RPC 的實作，因此無法判斷它是否重新檢查上限。實際上
`settle_optimize_message_request` 在同一交易內呼叫 `increment_usage`，而該函式
（`20260702120000_increment_usage_atomic_quota.sql:57,62`）在 `FOR UPDATE` 下超限會
`RAISE EXCEPTION QUOTA_EXCEEDED_MONTHLY/DAILY`，整筆交易（含 ledger insert）回滾。
上限不可能被超用。

### GLM F1：RPC 故障時單日免費次數可超過 10

**屬實，但這是拍板的設計，不是缺陷。** 額度函式故障時**刻意**選擇不扣費（寧可白送，
也不要使用者同時被吃掉免費額度又被扣錢）。GLM 的實質貢獻是指出送審主張 3 的但書
寫得太窄——問題在主張的措辭，不在程式碼。修復 #4 之後，這種白送在 telemetry 上有
專屬的 `refine_free_allowance_unavailable`，看得出來了。

---

## 已知立場，非本輪新發現

### Codex Uncertain-2：動作保持仍只靠 prompt

設計階段（`2026-07-28-reply-refinement-review-results.md` B-2）已拍板：不自稱「安全鐵律」，
改稱 best-effort policy。輸出守門 `checkOptimizedMessage` 已在 `main` 上線，會掃
`optimizedMessage.optimized`；它擋的是句構明確的脅迫，不是語意層的「把拒絕改成答應」。
語意 verifier 是獨立議題，本案不做。

---

## 驗證證據

| 項目 | 結果 |
|---|---|
| `deno test --allow-all supabase/functions/analyze-chat/` | 789 passed / 0 failed（基準 738） |
| `flutter test` | 2686 passed / 4 skipped / 0 failed |
| `flutter analyze`（全 repo） | No issues found（597.4s） |
| PG smoke S1–S6 | 10 次免費、第 11 次 granted=false、換日歸零、limit 可變、參數守門、limit=0 |
| PG smoke I1–I4 | 同 requestId 連叫五次只花一次、不同 requestId 各扣一次、exhausted 判決黏著、NULL requestId 被 RAISE 擋下、兩參數 overload 已不存在 |
| PG 並行 race | 同 requestId ×6 → used=1；不同 requestId ×6 搶最後一格 → granted 恰 1 |
| 兩側 golden hash | client fingerprint 與 server input hash 皆與 2026-07-28 byte-identical |

**尚未執行**：真機 dogfood（Task 15 Step 3）、生產 migration、push。

---

# 附錄：生產 migration 上線前的 R3 閘門（兩輪）

日期：2026-07-29，上線 SHA `b3b06f25`

`docs/shared-agent-rules.md` 要求 schema/billing/quota migration 視為 R3，
生產操作前須過 opposite-frontier ＋ GLM 挑戰閘門。以下是實際結果。

## 第一輪

- **GLM**：判定五項檢查全數通過、無阻礙問題。
- **Codex**：1 Critical、3 Important、4 Uncertain。

**兩邊在同一條上結論相反，且 GLM 錯了。** Codex 指出 `now()` 就是
`transaction_timestamp()`，整個交易期間凍結，因此前一輪「拿到鎖後重讀日期」的
修法是空的；GLM 卻把同一段判為 Correct。本機實測定案：等鎖 3 秒後 `now()` 差
0 秒、`clock_timestamp()` 差 3 秒。**以實測為準，改用 `clock_timestamp()`。**

這一條也暴露我自己的測試缺陷：上一版契約測試只斷言那行的**位置**，不斷言
**語意**，所以放它過了——正是該檔案自己註解警告過的「Match the statement, not
the words」。新版測試明文禁止 `now()` 出現在該位置。

| 來源 | 等級 | 問題 | 修法 |
|---|---|---|---|
| Codex | Critical | 建 FK 在 `auth.users` 拿 SHARE ROW EXCLUSIVE，等待無上限，排進佇列後續 auth 寫入全部塞後面 | `SET LOCAL lock_timeout = '5s'` 快速失敗 |
| Codex | Important | `now()` 凍結，日界重讀是 no-op | 改 `clock_timestamp()` |
| Codex | Important | 先鎖子列、後因 FK 要父列，與刪帳號順序相反會 40P01 死鎖 | 進場先對 `auth.users` 取 `FOR KEY SHARE` |
| Codex | Important | claims 只在呼叫者自己回來時才清，流失帳號的列永不清理 | 補 cleanup 函式＋pg_cron 每小時（第 23 分） |

## 第二輪

- **Codex**：無 Critical。1 Important（`SET lock_timeout` 會活過 COMMIT 留在
  連線上，pooled runner 會讓下一支 migration 繼承 5 秒上限）→ 改 `SET LOCAL`，
  本機實測交易內 5s、交易後回 0。

四項 Uncertain 全部以證據收斂：

| Uncertain | 結論 |
|---|---|
| `search_path` 劫持 | **證偽**。`anon`/`authenticated`/`service_role` 對 public schema 都沒有 CREATE。 |
| 函式 owner 能否讀 `auth.users` | **成立可用**。生產以真實使用者實跑一次並 ROLLBACK，回 `{granted:true, used:1, remaining:9}`，事後兩表皆 0 列。 |
| `service_role` 能否直接寫表 | **Codex 對、我原本的註解錯**。Supabase default privileges 早已給滿 DML，`GRANT` 只加不減；生產實測收緊前 ACL＝`arwdDxtm`。已補明確 `REVOKE`，收緊後＝`rm`。 |
| claim 保留期是否早於 replay 窗 | **證偽**。Edge preflight 以 `.gte("created_at", cutoff)` 在查詢當下就擋掉超過 7 天的 replay，不依賴 cron 是否已刪。 |

## 生產套用與驗證

單一交易套用（含帳本列），逐項驗證：

| 檢查 | 結果 |
|---|---|
| migration 帳本版本 | `20260729000000`，與檔名一致 |
| 兩張表 RLS | 皆 `true` |
| 函式簽章 | `consume_refine_free_allowance(uuid, integer, uuid)` 唯一一個；舊兩參數 overload 不存在 |
| 函式執行權 | 只有 `postgres` 與 `service_role`；無 anon/authenticated |
| 表權限 | `service_role=rm`（唯讀），寫入僅能經 SECURITY DEFINER 函式 |
| pg_cron | `cleanup-expired-refine-free-claims`，`23 * * * *`，active，全庫恰一筆 |
| `lock_timeout` 殘留 | `0`，未外洩到連線 |
| PostgREST schema cache | 以 anon 呼叫新 RPC 得 `42501 permission denied`（**不是** 404），證明函式已被解析且權限邊界正確 |

## 交付

| 項目 | 結果 |
|---|---|
| `main` | `8b90cb3c..b3b06f25`（fast-forward，無 merge commit） |
| Deploy Edge Function | 首次失敗＝`esm.sh` 回 522（CDN 逾時，非本專案程式碼），重跑一次成功 |
| analyze-chat | version 306、ACTIVE、`verify_jwt: false` |
| Build & Distribute | success（`build-ios` 產出 App Store 簽章驗證 artifact，**不上 TestFlight**） |
| Deploy Web to Vercel | success |
| 可安裝的 TestFlight build | **未做**，`release.yml` 是 Eric 的手動動作 |
