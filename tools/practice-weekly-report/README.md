# 練習室週報腳本（Phase 5 WP1）

每週一支唯讀腳本，把練習室 telemetry 從 Supabase 拉成 markdown 放進
`docs/reports/`。上線後四週的週報是 Phase 5 計畫附錄凍結區要不要復活的依據。

**這支腳本絕不寫 DB。** 唯讀有三層保證：

1. `sql.ts` 只組 `SELECT`。
2. 每條語句在組出來時與送出前各過一次 `assertReadOnlySql`——擋掉
   `insert/update/delete/drop/alter/truncate/create/grant/revoke/...`、擋掉 不是
   `SELECT` 開頭的語句、擋掉分號（不准多語句夾帶）。日期參數在進字串 前必須通過
   `^\d{4}-\d{2}-\d{2}$`。
3. 只呼叫 Management API
   的兩個唯讀端點：`POST /v1/projects/<ref>/database/query` （Postgres）與
   `GET /v1/projects/<ref>/analytics/endpoints/logs.all?sql=…` （Logs
   Explorer）。兩條路徑的 SQL 都過同一道 `assertReadOnlySql`。

## 怎麼跑

```bash
# 先看它要送什麼 SQL（不打網路、不需要 token）
deno run --allow-read --allow-env tools/practice-weekly-report/report.ts \
  --dry-run --from=2026-08-29 --to=2026-09-05

# 真的產一份報告
deno run --allow-read --allow-write --allow-env \
  --allow-net=api.supabase.com \
  tools/practice-weekly-report/report.ts \
  --project-ref=<supabase project ref> \
  --payers-starter=0 --payers-essential=0
```

測試：

```bash
deno test --allow-all tools/practice-weekly-report/
deno fmt --check tools/practice-weekly-report/
deno lint tools/practice-weekly-report/
```

### 參數

`--k=v` 與 `--k v`（空格）兩種寫法都收；**認不得的參數、孤立的字串、缺值的
參數一律報錯退出**。第一次實跑就是把 `--out path` 打進只認 `--k=v` 的解析器，
被靜默忽略後寫到預設路徑——所以現在寧可炸掉也不安靜跑錯。

| 參數                  | 預設                                   | 說明                                           |
| --------------------- | -------------------------------------- | ---------------------------------------------- |
| `--project-ref=`      | `SUPABASE_PROJECT_REF` env             | Supabase 專案 ref。腳本裡沒有寫死任何 ref。    |
| `--from=`             | `--to` 往前 7 天                       | ISO 日期，**含**，以 UTC 00:00 為界。          |
| `--to=`               | 今天（UTC）                            | ISO 日期，**不含**。                           |
| `--out=`              | `docs/reports/<to>-practice-weekly.md` | 輸出路徑。                                     |
| `--payers-starter=`   | 無                                     | 手填 Starter 付費人數（見「損益」）。          |
| `--payers-essential=` | 無                                     | 手填 Essential 付費人數。                      |
| `--logs-limit=`       | `10000`                                | function logs 單日查詢列數上限；撞到會印警告。 |
| `--dry-run`           | 關                                     | 只印三條 SQL，不打網路、不落檔。               |

### Token 從哪來

`SUPABASE_ACCESS_TOKEN` 環境變數優先；沒有就讀 `~/.supabase/access-token`
（`supabase login` 會寫在這裡）。兩個都沒有就報錯結束，不會去猜。token 只放進
`Authorization: Bearer`，不進報告、不進 stdout。

## 欄位定義與 SQL 來源

三條查詢（`--dry-run` 可以完整看到）：

- **sessions**：`public.practice_chat_sessions`，`created_at` 落在時間窗內， 按
  `practice_mode` × `ai_count` 分組，取 `count(*)`、`sum(hint_count)`、
  `sum(debrief_count)`、`count(*) FILTER (WHERE charged)`。
- **ai_logs**：`public.ai_logs`，`request_type LIKE 'practice\_%'`，按
  `request_body->>'mode'`、`request_body->>'practiceMode'`、`model`、
  `status`、`fallback_used` 分組，取 `count(*)` 與 `sum(retry_count)`。
- **function logs**（Logs Explorer）：`function_logs` 的 `timestamp`、
  `event_message`，`event_message` 含 `practice_chat_succeeded`，
  `order by timestamp` 加 `limit`。**時間窗不在 SQL 裡**，見下。

| 報告欄位           | 定義                                                          | 來源                              |
| ------------------ | ------------------------------------------------------------- | --------------------------------- |
| 場次               | 時間窗內建立的 session 列數，按 `practice_mode` 拆            | `practice_chat_sessions`          |
| 已結算場次         | `charged = true` 的場次（扣費或測試帳號豁免）                 | `practice_chat_sessions.charged`  |
| 回合分佈           | `ai_count` 直方圖，固定印 1–20 桶                             | `practice_chat_sessions.ai_count` |
| 0 回合／溢位       | `ai_count = 0`／`> 20` 的場次，單獨列出不混進直方圖           | 同上                              |
| 提示次數、檢討張數 | 場次帳本上的累計計數                                          | `hint_count`、`debrief_count`     |
| 生成呼叫數         | `ai_logs` 列數 ＋ `retry_count`（同列內重試也是真的打了模型） | `ai_logs`                         |
| fallback 比率      | `fallback_used = true` 的呼叫數 ÷ 總呼叫數                    | `ai_logs.fallback_used`           |
| 估算成本           | 呼叫數 × 單次估價（見下）                                     | `ai_logs` ＋ `pricing.ts`         |
| 每場成本           | （提示檢討 ＋ 聊天）成本 ÷ 場次                               | 上面兩者 ＋ logs                  |

### 成本怎麼估（以及為什麼是估的）

`ai_logs.input_tokens`／`output_tokens` 在 practice-chat 的寫入端是**寫死的
0**（`supabase/functions/practice-chat/telemetry.ts` 的 `buildPracticeAiLogRow`
隱私邊界），`cost_usd` 從來沒被填過。DB 裡拿不到真 usage，所以成本＝「呼叫次數 ×
單次 token 側寫 × 牌價」：

- 側寫來自計畫 §2 D14：輸入 9k token（其中 8.1k 命中 cache），提示輸出 ~400
  tokens、檢討 ~1,200 tokens。
- 牌價一律 `import` 自 `tools/practice-agency-eval/pricing.ts`
  （`estimateCostUsd`／`HAIKU_4_5_PRICING`／`SONNET_5_PRICING`），這支腳本
  不自己抄任何單價。
- 算出來的單次金額與 D14 表格逐格相同：Sonnet 提示 `$0.0074`、檢討
  `$0.0154`、Haiku 提示 `$0.0037`。

DeepSeek 的提示／檢討列印「未估」而不是 `$0`，並在下面單獨報未估呼叫數——那是
對帳時的分母缺口。`pricing.ts` 的 `DEEPSEEK_CHAT_USD_PER_CALL` **只適用於聊天
輪**（短 prompt、高快取命中的觀測值），提示與檢討的 prompt 長度與輸出長度都差
一個量級，套上去只會低估到沒有意義，所以這一段刻意不套。

驗收（計畫 WP1）：成本欄要能跟 Anthropic console 當週總帳對得起來、誤差 <
10%。對不上時該修的是**寫入端**（讓 `ai_logs` 落真 usage），不是在這裡調 係數。

### 損益

RevenueCat 的付費人數不在 Supabase，第一版由 Eric 手填
`--payers-starter=N --payers-essential=N`；沒給就印「未提供付費人數」，只出成本。

- 月營收 ＝ Starter 人數 × NT$590 ＋ Essential 人數 × NT$1290。
- 本週成本 ＝（提示＋檢討估算 ＋ 聊天輪 logs 實 usage）× 32（D14 匯率）。
  **聊天成本來自 function logs**，涵蓋範圍不足一整週（保留期切掉、或某天被
  限流標成未取得）時，成本與佔比都會偏低——涵蓋範圍印在聊天段最上面。
- 外推月成本 ＝ 本週成本 × 52 ÷ 12（營收是月費、成本是週觀測，要同口徑）。
- 成本佔營收 ＝ 外推月成本 ÷ 月營收。

## 第二個來源：Edge Function logs

這七個欄位**不在任何資料表裡**，只在 `logInfo("practice_chat_succeeded", …)` 的
console 輸出（`handler.ts` 5095–5330 一帶）：agency 介入率、`chatModel`
分佈、`chatModelCalls`、
`chatModelFallback`、聊天成本（`chatModelUsage`）、`checkOutStructuralFail`、
`checkOutRewriteInjected` × fail、`readOnlyReply`。所以第三條查詢走 Logs
Explorer 把它們撈回來。

**一行 log 的格式**（`supabase/functions/practice-chat/logger.ts`）：

```js
console.log(JSON.stringify({ level: "info", event, ...data }));
```

沒有前綴、沒有多行——`event_message` 整行就是一個 JSON 物件。parser 逐列
`JSON.parse`，不是物件或 `event !== "practice_chat_succeeded"` 就跳過，並分別
計數（`其他事件 N 列、無法解析 N 列` 會印在報告上）；壞行不會讓報告掛掉，也
不會被無聲吃掉。

**分母**：`conversationAgency` 與 `chatModel` 這兩個 key 在旗標關著時
**整組不存在**（handler.ts 的旗標等價保證）。所以比率的分母是「這一輪真的帶
了那個 key」的輪數，不是全部輪數；沒有任何一輪帶那個 key 時印 `—` 而不是 0%。

**聊天成本**：`chatModelUsage` 是真 usage（所有成功 Claude 呼叫的四格累加），
所以這一段吃 `HAIKU_4_5_PRICING` 真牌價，不是側寫估算；DeepSeek 那幾次用
`DEEPSEEK_CHAT_USD_PER_CALL`（餘額差反推的每次觀測單價）。

### 時間窗與逐日拉（2026-09-05 對 production 實跑後修正）

兩件事實跑才知道：

1. **時間窗只能走 query string**：
   `?sql=…&iso_timestamp_start=2026-09-04T00:00:00Z&iso_timestamp_end=2026-09-06T00:00:00Z`。
   寫進 SQL 的 `WHERE timestamp >= '…'`（字串或 `timestamp '…'` literal 都一樣）
   會讓結果變成 **0 筆**。所以 SQL 只留 `event_message LIKE`＋`order`＋`limit`。
2. **範圍太大會回空**：同一條 SQL 帶 2 天窗回 11 筆、帶 7 天窗回 0 筆。所以
   `--from`～`--to` 會切成**一天一段**，每段一次 GET，之間 `sleep` 500ms。

`--dry-run` 會把 SQL、段數、每一段的 `iso_timestamp_start`／`iso_timestamp_end`
全部印出來。

**已知未確認**：`iso_timestamp_end` 到底是 inclusive 還是 exclusive 沒有實測過。
所以相鄰兩段可能各自把邊界上那一列拉回來一次。腳本以
`(timestamp, event_message)` 去重，重複列不會讓比率的分子分母各多一次；真要
確認邊界語意，拿同一列的 timestamp 各跑一次 end 剛好等於它的窗即可。

### 限流

端點回 HTTP 429，或 body 是
`{"message":"ThrottlerException: Too Many Requests"}` 時，退避重試 **1s → 2s →
4s**（最多 3 次）。三次都不過就把那一天記成「未取得」
印在報告的涵蓋範圍段（`**未取得 N 天**：…`），**不讓整份報告失敗**——少一天資料
要看得見，但不該把整週的統計丟掉。其他 HTTP 錯誤照樣往上丟。

回傳 body 是 `{"result":[…]}`，每列的 `timestamp` 是**微秒整數** （例
`1788558109700000`），涵蓋範圍會換算成 ISO 再印。

### 保留期（會咬人的地方）

Supabase function logs **通常只保留 7 天**，而且時間窗超出保留期時端點會回 **0
筆、不報錯**。所以：

- 報告一定會印「涵蓋範圍：最早 ～ 最晚 timestamp、端點回了幾列」。涵蓋範圍 比
  `--from`／`--to` 窄，就是被保留期切掉了。
- **週報要每 7 天內跑一次**，否則聊天那一段是空的，而且空得無聲無息。
- 截斷是**逐日**判斷：某一天回滿 `--logs-limit` 就代表那天被切掉尾巴，報告會
  逐日列出（`**N 天撞到單日列數上限**：…`），stderr 也會警告。整週總列數超過
  limit 不算截斷——limit 是每次呼叫的上限。

## `--out` 的去處

報告含 production 使用量，一個手滑的路徑就可能把它寫進會被 commit 的地方。 所以
`--out` 預設只准寫進 `docs/reports/`；要寫別處（例如 scratchpad）加
`--allow-out-anywhere`。路徑含 `..` 一律擋，逃生口也擋不掉。

## 不 commit 報告

`docs/reports/` 只放 `.gitkeep`。真實報告含 production 使用量，跑出來自己
看，不進 repo。
