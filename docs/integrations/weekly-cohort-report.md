# 每週 cohort 報表（weekly-cohort-report）

> 每週一張表：這週新註冊的人，24 小時內有沒有用到第一次價值（分析、開場、練習）、7 天內有沒有撞到額度、有沒有付費、有沒有退款。之後判斷 onboarding 每一步有沒有效，看的就是這張表（實作規格步驟 8）。
>
> SQL 的真相源是本檔「SQL 範本」與 `tools/weekly-cohort-report/sql.ts`，兩邊一字不差（`sql_test.ts` 會比對）；改一邊就要同一批改另一邊。

## 怎麼跑

工具在 `tools/weekly-cohort-report/`，只讀不寫：每條語句組出來時與送出前都過練習室週報同一道唯讀守門（`tools/practice-weekly-report/sql.ts` 的 `assertReadOnlySql`，定位一樣是防手誤的護欄、不是安全邊界），只呼叫 Supabase Management API 的 `POST /v1/projects/<ref>/database/query`。產出的 markdown 只寫到 repo 以外（見「存檔」）。**第一次真跑要 Eric 另外核准**：會用 Eric 的 Management API token 讀正式資料庫。

```bash
# 先看會送什麼 SQL：不打網路、不需要 token、不落檔
deno run --allow-env tools/weekly-cohort-report/report.ts --dry-run

# 真的跑（要 Eric 核准）
deno run --allow-read --allow-write --allow-env --allow-net=api.supabase.com \
  tools/weekly-cohort-report/report.ts --project-ref=<supabase project ref>

# 測試：本機離線、假的 fetch；cohort_sql_postgres_test.ts 用 PGlite 套真的 migration
deno test --allow-all tools/weekly-cohort-report/
```

| 參數 | 預設 | 說明 |
| --- | --- | --- |
| `--project-ref=` | `SUPABASE_PROJECT_REF` | Supabase 專案 ref，程式裡沒有寫死。 |
| `--week=` | 上一個已經結束的 ISO 週 | 報表裡最新的註冊週，例如 `2026-W43`。還沒結束的週會報錯。 |
| `--weeks=` | `6` | 從 `--week` 往回共幾週（1～12），一週一次查詢。 |
| `--out=` | `~/vibesync-weekly-cohort/<週>.md`（家目錄底下，repo 以外） | 不能指到 repo 裡面（含 `docs/`），指到就報錯並說明原因，沒有逃生口。相對路徑以目前目錄為準，`~` 換成家目錄。 |
| `--dry-run` | 關 | 只印每一週的 SQL。 |

`--k=v` 與 `--k v` 兩種寫法都收；認不得的參數、孤立的字串、缺值一律報錯。token 跟練習室週報一樣：`SUPABASE_ACCESS_TOKEN` 環境變數優先，沒有就讀 `~/.supabase/access-token`；只放進 `Authorization: Bearer`，不進報表、不進輸出。

## 欄位定義

每一欄都是人數（每個人最多算一次），時間窗從每個人自己的註冊時間起算，「24 小時內」「7 天內」都是嚴格小於。

| 報表欄位 | SQL 欄位 | 定義 | 資料來源 | 什麼時候開始有值 |
| --- | --- | --- | --- | --- |
| 註冊週 | — | ISO 週：UTC 週一 00:00 起、下週一 00:00 止（含頭不含尾），台北是週一早上 8 點 | — | — |
| 新帳號 | `new_accounts` | 這週註冊的帳號，排除測試帳號 `vibesync.test@gmail.com` 與 `test_users` 名單 | `public.users.created_at`、`auth.users.email`、`public.test_users` | 一直有 |
| 24h 分析 | `analysis_24h` | 註冊後 24 小時內第一次成功分析 | `ai_logs`：`status = 'success'`、`request_type` 是 `analyze`／`analyze_with_images`／`my_message`，取最早一筆（新版分析每個階段各一列） | 一直有，但只留 30 天 |
| 24h 開場 | `opener_24h` | 註冊後 24 小時內第一次成功生成開場白 | `ai_logs`：`request_type` 是 `opener_generate`（兩段式第二段）或 `opener`（舊版單段） | 一直有，但只留 30 天 |
| 24h 練習 | `practice_24h` | 註冊後 24 小時內第一場有 AI 回覆的練習 | `practice_chat_sessions`：`ai_count > 0` 的最早一場（一般練習對話不寫 `ai_logs`） | 一直有 |
| 7 天撞額度 | `quota_block_7d` | 註冊後 7 天內第一次被告知額度不夠 | `funnel_events`：`quota_block_shown` | 步驟 6 上線後 |
| 7 天額度付費頁 | `quota_paywall_7d` | 註冊後 7 天內因為額度不夠打開付費頁；步驟 6 之前拿來當撞額度的下限 | `funnel_events`：`paywall_opened` 且 `entry = 'quota_exhausted'`（見 `funnel-events-v1.md`） | 這個事件上線後 |
| D7 付費 | `paid_d7` | 註冊後 7 天內第一次正式購買 | `revenue_events`：`INITIAL_PURCHASE` 且 `raw_payload ->> 'environment' = 'PRODUCTION'` | App Store 正式開賣後（TestFlight 的交易是 `SANDBOX`，不算） |
| D30 付費 | `paid_d30` | 同上，30 天內 | 同上 | 同上 |
| 退款（至今） | `refunded` | 到查詢當下為止被退款過的人，不綁時間窗 | `revenue_events`：`CANCELLATION`、`PRODUCTION`、`raw_payload ->> 'cancel_reason' = 'CUSTOMER_SUPPORT'` | 步驟 7 上線、而且正式開賣後 |

## SQL 範本

`:week_start`／`:week_end` 換成 `'2026-10-19 00:00:00+00'::timestamptz` 這種 UTC 時間（含頭不含尾）。手動貼進 SQL Editor 就用下面這段、換掉兩個佔位字；工具會把整條包成 `SELECT * FROM (…) AS weekly_cohort` 再送（唯讀守門只放行 SELECT 開頭），結果一樣。

```sql
with cohort as (               -- 這週註冊的新帳號，排除測試帳號
  select u.id as user_id, u.created_at
  from public.users u
  join auth.users au on au.id = u.id
  where u.created_at >= :week_start
    and u.created_at < :week_end
    and coalesce(au.email, '') <> 'vibesync.test@gmail.com'
    and not exists (select 1 from public.test_users t where t.user_id = u.id)
),
first_analysis as (            -- 新版分析每階段一列，取最早成功的那筆
  select l.user_id, min(l.created_at) as at
  from public.ai_logs l join cohort c on c.user_id = l.user_id
  where l.status = 'success'
    and l.request_type in ('analyze', 'analyze_with_images', 'my_message')
  group by l.user_id
),
first_opener as (              -- 兩段式的第二段，加上舊版單段（舊 App 與伺服器旗標關閉時）
  select l.user_id, min(l.created_at) as at
  from public.ai_logs l join cohort c on c.user_id = l.user_id
  where l.status = 'success'
    and l.request_type in ('opener_generate', 'opener')
  group by l.user_id
),
first_practice as (            -- 一般練習對話不寫 ai_logs，改看伺服器帳本
  select s.user_id, min(s.created_at) as at
  from public.practice_chat_sessions s join cohort c on c.user_id = s.user_id
  where s.ai_count > 0
  group by s.user_id
),
quota_block as (               -- 步驟 6 之後才有
  select f.user_id, min(f.created_at) as at
  from public.funnel_events f join cohort c on c.user_id = f.user_id
  where f.event = 'quota_block_shown'
  group by f.user_id
),
quota_paywall as (             -- 額度不夠打開付費頁：步驟 6 上線前的下限
  select f.user_id, min(f.created_at) as at
  from public.funnel_events f join cohort c on c.user_id = f.user_id
  where f.event = 'paywall_opened'
    and f.properties ->> 'entry' = 'quota_exhausted'
  group by f.user_id
),
first_purchase as (
  select r.user_id, min(r.event_timestamp) as at
  from public.revenue_events r join cohort c on c.user_id = r.user_id
  where r.event_type = 'INITIAL_PURCHASE'
    and r.raw_payload ->> 'environment' = 'PRODUCTION'
  group by r.user_id
),
refunded as (                  -- 步驟 7 之後才有
  select distinct r.user_id
  from public.revenue_events r join cohort c on c.user_id = r.user_id
  where r.event_type = 'CANCELLATION'
    and r.raw_payload ->> 'environment' = 'PRODUCTION'
    and r.raw_payload ->> 'cancel_reason' = 'CUSTOMER_SUPPORT'
)
select
  count(*)                                                              as new_accounts,
  count(*) filter (where fa.at < c.created_at + interval '24 hours')   as analysis_24h,
  count(*) filter (where fo.at < c.created_at + interval '24 hours')   as opener_24h,
  count(*) filter (where fp.at < c.created_at + interval '24 hours')   as practice_24h,
  count(*) filter (where qb.at < c.created_at + interval '7 days')     as quota_block_7d,
  count(*) filter (where qp.at < c.created_at + interval '7 days')     as quota_paywall_7d,
  count(*) filter (where pu.at < c.created_at + interval '7 days')     as paid_d7,
  count(*) filter (where pu.at < c.created_at + interval '30 days')    as paid_d30,
  count(rf.user_id)                                                     as refunded
from cohort c
left join first_analysis fa on fa.user_id = c.user_id
left join first_opener   fo on fo.user_id = c.user_id
left join first_practice fp on fp.user_id = c.user_id
left join quota_block    qb on qb.user_id = c.user_id
left join quota_paywall  qp on qp.user_id = c.user_id
left join first_purchase pu on pu.user_id = c.user_id
left join refunded       rf on rf.user_id = c.user_id
```

### 跟實作規格附錄 B 不一樣的地方

- 測試帳號多排除 `public.test_users` 名單：後台的「正式用戶」就是扣掉這張表（`admin-dashboard` 的 overview、users、activity），規格說「各表都沒有測試旗標」不對。名單是空的就跟規格一樣。
- 開場多算 `request_type = 'opener'`：伺服器旗標 `OPENER_TWO_STAGE_ENABLED` 關掉時，App 會退回舊版單段開場，舊版 App 也只送單段；只算 `opener_generate` 會少算。兩段式第一段 `opener_analyze` 不回開場白，不算。
- 多一欄「7 天額度付費頁」：規格步驟 8 寫了步驟 6 之前用 `paywall_opened`（`entry = quota_exhausted`）當撞額度的下限，附錄 B 的 SQL 沒有這一欄。
- 結尾沒有分號：唯讀守門不收分號。

## 讀法

- 只看趨勢，不比小數點。上線前大多是 0 或個位數，這是正常的。
- 一份週報列最近 6 週（`--weeks`），每格先看時間窗走完沒有：
  - 「（未滿 24 小時）」「（未滿 7 天）」「（未滿 30 天）」：這週最晚註冊的人還沒走完那個時間窗，數字還會變，看之後的週報。
  - 「（紀錄已清）」：24h 分析與 24h 開場來自 `ai_logs`，只留 30 天（`20260902160000_retention_cleanup_schedules.sql`）。查詢時已經過了這週週一 30 天，最早那幾天的紀錄可能刪了，數字會偏低。
- 所以同一週要分次讀：24h 分析與 24h 開場要讀這週結束隔天起、23 天內的週報（再晚就是「紀錄已清」）；7 天欄與 D7 讀結束滿 7 天後的週報；D30 讀結束滿 30 天後的週報（每週跑一次的話，是這一週出現的第 6 份）。
- 舊的週重跑，數字可能變小：刪帳號會連同那個人的 `users`、`ai_logs`、`practice_chat_sessions`、`funnel_events`、`revenue_events` 一起刪（`delete-account`）。以當時的存檔為準。
- `ai_logs` 一列是一次模型呼叫，不是一次使用者看到的結果：「24h 分析」嚴格說是「24 小時內有一次成功的分析模型呼叫」，呼叫成功但結果最後沒送到使用者的少數情況也會算進去。
- 付費只算正式環境；TestFlight 的交易是 `SANDBOX`，不算。退款的查法見 `docs/subscription-revenue-observability.md`「退款怎麼查」。

## 上線初期不要解讀的數字

照實作規格附錄 C，加上這張表自己的兩條：

- 兩組之間的付費率差：付費率 2% 想測出翻倍到 4%，每組約要 1,141 人；只提升 20%（2.4%）每組約要 21,109 人。
- onboarding 各頁流失率：補送只看得到後來有登入的人。
- TestFlight 的任何交易：TestFlight 內購不扣錢、續訂加速。
- Android：RevenueCat 尚未設定 Android，不放進付費分母。
- 幾十人的資料上做交叉切分。
- 步驟 6 上線前的「7 天撞額度」、步驟 7 上線前的「退款」：還沒有資料，0 不代表沒發生。
- 「7 天額度付費頁」不等於撞額度的人數：撞到額度但沒打開付費頁的人不在裡面，只能當下限。

## 存檔

- **週報不 commit 進 repo**（Eric 2026-10-27「照預設」）：repo 是公開的，週報有註冊、付費、退款人數。週報裡的數字也不要貼進 repo 的其他文件、commit 訊息或 PR。
- 工具先把 markdown 寫到 repo 以外的本機路徑（預設 `~/vibesync-weekly-cohort/<週>.md`，例如 `2026-W43.md`），再存進 Dev Brain 的 VibeSync 週報筆記，由 agent 經 Brain Publisher 收錄。工具自己不 commit，也不直接寫進 Dev Brain。
- 每週跑一次，建議每週二（UTC）之後跑，上一週的 24 小時欄就都走完了。
- 一定要每週跑：`ai_logs` 30 天後就刪，晚了 24h 分析、24h 開場就補不回來。
