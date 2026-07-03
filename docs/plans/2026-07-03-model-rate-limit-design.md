# 全面模型呼叫 per-user 限流設計（2026-07-03，Eric 拍板）

> 目標：一案收掉「成本濫用」整類問題，達可上架程度。
> 收斂項：opener P2-2 並發 storm 燒模型成本、練習室翻牌手動重試不冪等（併案 client 修）。
> 模式：照抄 OCR recognizeOnly 限流（migration `20260702130000` + `ocr_rate_limit.ts`）。

## 拍板紀錄

1. 範圍＝**全包**：opener、analyze、coach-chat、coach-follow-up、practice turn、practice hint 六面限流＋翻牌 client requestId 持久化併案。
2. 上限＝差異化預設組（見下表），權威在 Edge 常數，SQL 不寫死。測試帳號（accountIsTest）一律 bypass。
3. 架構＝**一張通用表＋一顆通用 RPC（user_id＋scope 複合鍵）**；既有 `ocr_rate_limits` 已上線**不動**，註記未來可併。

## 事實基礎（Explore 2026-07-03）

- 翻牌**不打模型**（純 server 選牌），`claim_practice_profile_draw` RPC 已冪等（`p_request_id`＋`idempotent_replay`）；雙扣根因＝client `practice_chat_providers.dart:574` 每次點擊生新 UUID 不持久化。
- hint 已有完整冪等（`20260703150000`＋client `practice_pending_hint_store.dart` pending id 持久化）＝翻牌修復的複製範本。
- opener P2-2 race＝preflight 非原子讀（index.ts:4954-4960）與扣費 RPC（:5256）之間，模型呼叫在 :5112——分鐘限流直接封頂燒錢上界。
- practice chat turn 與 coach-chat 目前**零分鐘級限流**。

## Server 側

### Migration（版本接 20260703160000 之後）

- 表 `model_call_rate_limits`：PK `(user_id, scope)`、`scope TEXT CHECK (char_length BETWEEN 1 AND 32)`、`minute_window_start` / `minute_count` / `day_window_start` / `day_count` / `updated_at`（照抄 ocr_rate_limits）。RLS 開啟零 policy，僅 service_role＋SECURITY DEFINER RPC。
- RPC `increment_model_usage(p_user_id UUID, p_scope TEXT, p_minute_limit INT, p_daily_limit INT) RETURNS VOID`：INSERT ON CONFLICT DO NOTHING → SELECT FOR UPDATE → 分鐘窗 60s／日窗 UTC 翻轉重置 → 超限 `RAISE 'MODEL_RATE_LIMITED_MINUTE'` / `'MODEL_RATE_LIMITED_DAILY'`。計 attempt 不計 success（超限 RAISE 整 TX rollback）。
- GRANT 僅 service_role；結尾 `NOTIFY pgrst, 'reload schema'`。

### Edge gate（六點，共用 shared helper `model_rate_limit.ts`）

| scope | 位置不變量 | 分/日 |
|---|---|---|
| `opener` | analyze-chat opener 模式：requestId preflight **之後**、quota gate 之前；**已知 dedup replay 跳過限流**（不打模型，且不得封死 cap 邊緣重試） | 3 / 30 |
| `analyze` | analyze-chat 分析本體，模型呼叫前（stream＋legacy 同點） | 6 / 60 |
| `coach_chat` | coach-chat 模型呼叫前 | 10 / 300 |
| `coach_follow_up` | coach-follow-up 模型呼叫前 | 6 / 60 |
| `practice_turn` | practice-chat chat 模式：續聊 402／session cap 409／quota 429 三 gate 之後、模型前 | 12 / 400 |
| `practice_hint` | practice-chat hint 模式：**hint replay preflight 之後**（replay 回放不打模型不計限流） | 4 / 40 |

每點行為同 OCR：accountIsTest bypass；infra 錯誤 fail-open 只 logError 放行；超限回 429：

```json
{ "error": "Model rate limited", "code": "MODEL_RATE_LIMITED",
  "message": "<分鐘：…太頻繁請稍等一分鐘｜每日：…已達上限，明天早上 8 點恢復>",
  "retryable": false }
```

**鐵則：絕不帶 monthlyLimit/dailyLimit/remaining 鍵**（client `_quotaExceptionFrom429` 靠那些鍵分流 paywall，帶了會誤導升級 CTA）。

## Client 側

### 429 映射（四面）

各 service 429 處理補 `code == 'MODEL_RATE_LIMITED'` 分支 → wait 動作＋優先 server 繁中文案（fallback「請稍等一下再試」），照 `analysis_service.dart:1032` OCR 寫法：

1. analyze＋opener（analysis_service 429 路徑；opener 呼叫路徑另確認）
2. coach-chat service
3. coach-follow-up 呼叫點
4. practice providers（turn＋hint；hint 補 code 分支）

### 翻牌 requestId 持久化（併案）

複製 hint pending store 模式：draw 前查 settings box pending draw requestId，有→沿用、無→生新 UUID 並持久化；**成功或 4xx 才 rotate**。server 不動（RPC 已冪等）。

## 測試（TDD）

- SQL：migration MCP 套用＋帳本對齊（絕不 db push）＋prod SQL 實測：分鐘窗滿/60s 重置、日窗 UTC 翻轉、**scope 隔離**（同 user 兩 scope 互不影響）、超限 RAISE、測完還原資料。
- Deno：每 gate 點——test 帳號 bypass、fail-open、429 形狀（無 quota 鍵）、順序不變量（opener dedup replay 跳限流、hint replay 跳限流、practice turn 在三 gate 後）。
- Flutter：四面 429 映射＋draw requestId 持久化/rotate（成功 rotate、5xx/斷網不 rotate、4xx rotate）。

## 部署順序

1. migration MCP 套用（fail-open 保證順序錯也不擋人，但仍先套）。
2. push → main CI 自動重佈**全部** Edge Functions。
3. client 改動等新 TF build。
4. 高風險區（quota/429）：**Codex 雙審 APPROVED 才宣稱 dogfood/上架 safe**。

## 實作分批

- Batch A（server）：migration＋shared helper＋六 gate 點＋Deno 測試 → 獨立可審可部署。
- Batch B（client）：四面 429 映射＋翻牌 requestId 持久化＋Flutter 測試 → 需新 TF build。

## 已接受殘餘

- fail-open：DB 限流 infra 故障時不限流（與 OCR 同取捨，保核心可用性）。
- 既有 `ocr_rate_limits` 與新通用表並存；未來如要合併另開案。
- 日窗上限與既有 quota 疊床＝刻意（quota 管商業額度、日窗當 quota 失效/繞過時的防刷 backstop）。
