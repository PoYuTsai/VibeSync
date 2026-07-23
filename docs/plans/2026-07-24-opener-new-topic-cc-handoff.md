# 給 CC：Opener Free 3＋New Topic 執行／驗收摘要

> 這份文字可以整份貼給 Claude Code（CC）。
> 完整施工規格是 `docs/plans/2026-07-24-opener-new-topic-implementation-plan.md`；本摘要不能取代完整規格。
> 如果摘要與完整規格有落差，以完整規格的「已鎖定產品規格」與「不變量」為準，不要自行改產品決策。

---

## 可直接貼給 CC 的任務

請實作「Opener Free 3＋New Topic 破冰腦力」，完成程式、migration、測試、文件、逐 concern commits、push 與 Codex Review Packet；完成後先停在等待 Eric 路由獨立 Codex review，不要自行部署，也不要在 `APPROVED` 前宣稱 dogfood safe。

### 0. 開工前先做

1. 依 repo 規則先讀：
   - `docs/snapshot.md`
   - `docs/shared-agent-rules.md`
   - `git log --oneline -15`
   - `docs/reviews/ai-arbitration-queue.md` 最新 `OPEN`
   - 最新 handoff
2. 完整讀完：
   - `docs/plans/2026-07-24-opener-new-topic-implementation-plan.md`
3. 確認 `AGENTS.md` 與 `CLAUDE.md` byte-for-byte 相同。
4. 記錄開工前 `BASE_SHA`；Review range 固定用 `BASE_SHA..HEAD`，不要寫 `latest`。
5. 使用／建立 branch：
   - `claude/new-topic-brainstorm-feature-ibh6tz`
6. 先檢查 worktree。既有未提交變更都視為 Eric 的工作，不可覆蓋、清除、順手格式化或混進 commit。
7. 若實際程式與計畫指定 symbol 不同，可以調整落點；若差異會改到 Free／Paid 分界、扣費、資料保留、輸出數量或相容策略，停止並回報 Eric。

### 1. 已拍板規格，不要再重新設計

#### Opener

- 模型仍固定產五種；不要多打一個模型 request。
- 新版 Free 恰好解鎖：
  - `extend`
  - `humor`
  - `tease`
- Free 鎖住：
  - `resonate`
  - `coldRead`
- Starter／Essential 維持五種。
- 成功生成固定扣 3 點。
- 新 App request 帶 `openerContractVersion: 2`。
- 舊 App 沒帶版本時，Free 必須維持 legacy `extend` 一種，避免 Edge 先上線時舊 App 誤判。
- Free v2 成功前，server 必須先確認模型五種都完整；可做一次 repair，仍不完整就回友善 502 且不扣。
- tier filter 後要同步正規化 nested recommendation：
  - `recommendation.pick`
  - `recommendation.reason`
- 推薦不得指向鎖卡或已被 sanitizer 移除的 opener；fallback 時清掉不再相符的理由。
- response 加 server 權威的 access metadata；client 不可只靠「有幾張卡」猜 tier。
- 舊 cache／draft 不做 Hive migration；讀取時依目前權益重新投影，不能憑空補不存在的句子，也不能讓降級 Free 看到鎖定內容。

#### New Topic

- 入口在既有 `/opener` 頁最上方切換：
  - 開場白
  - 新話題
- 用 `IndexedStack` 或等效 state-preserving shell；切換模式不能清除結果或中斷另一模式正在生成的工作。
- 必須選一個 owner-scoped Partner。
- 可用素材是：
  - 對象作戰板
  - 使用者「關於我」
  - 選填情境
- 情境只接受 enum，不做自由輸入：
  - `went_cold`
  - `after_date`
  - `stuck`
  - `warm_up`
- 三類素材只要至少一類有實質內容即可生成；三類全空時 client 不送出，server 也必須在 rate limit、model、claim、charge 前回 422 `NEW_TOPIC_CONTEXT_REQUIRED`。
- Partner 若被 data-quality flag 判定不可用，必須阻擋，不能用 About Me／情境繞過。
- owner-scoped／flag 規則由 Flutter 本地資料層執行；v1 不傳 `partnerId`，server 也沒有本地 Partner 資料可驗。Server 仍獨立檢查 normalized material 不可全空。切換 partnerId 時，即使兩個摘要相同，也必須 rotate requestId。
- 模型成功契約固定恰好五個完整 topic，不是 4–5 個。
- 每個 topic 固定四欄：
  - `direction`
  - `openingLine`
  - `whyItWorks`
  - `nextMove`
- 五題中恰好一題為推薦；server 指派穩定 ID `nt_1`～`nt_5`。
- Starter／Essential 收到五題。
- Free 只收到推薦的一題完整內容；另外四題文字不能送到 client，也不能存入 ledger。UI 顯示精簡「還有 4 個」升級 CTA，不渲染四張空鎖卡。
- 成功固定扣 3 點。Free 只要月／日 quota 都至少剩 3，就不能因 tier 先被 paywall 擋；剩 1–2 才是真 quota 不足。
- v1 不新增 Hive 歷史、收藏、結果持久化或跨頁保存。

### 2. AI 脈絡與內容安全

- 不要直接重用現有 `PartnerSummaryBuilder.build()`；另做 `NewTopicPartnerContextBuilder`，現有 opener／analyze 行為不得改變。
- Partner 的有效訊號可包含熱度、興趣、個性、custom note、彙整 notes。
- 姓名、訊息數、日期等 metadata 單獨存在不算實質素材。
- 在 `EffectiveStylePromptBuilder` 新增 `buildForNewTopic()`。
- Prompt 必須明確分隔：
  - 對方作戰板
  - 關於我
  - 目前狀況
- 只有作戰板內容可以被當成「對方的事實」。
- About Me 的興趣只能拿來做自然自我揭露，不可改寫成對方也喜歡、共同興趣或已知事實。
- 不得虛構對方興趣；沒有證據時用開放式、低假設的問題。
- 可見內容不要出現 `DHV`、PUA 技巧名、露骨性暗示、歧視、施壓或情勒。
- 冷掉／被拒／剛約完的情境要尊重節奏，不可硬推第二次邀約。

### 3. New Topic request／response 契約

Client request 僅允許：

```json
{
  "mode": "new_topic",
  "requestId": "UUID",
  "partnerSummary": "optional normalized string",
  "effectiveStyleContext": "optional normalized string",
  "situation": "optional enum",
  "expectedTier": "optional free|starter|essential",
  "revenueCatAppUserId": "optional string"
}
```

以下欄位在 `new_topic` 一律拒絕，不要靜默忽略：

- images
- 非空 messages
- profileInfo
- userDraft
- recognizeOnly
- sessionContext
- conversationSummary
- incompatible response mode

模型內部先產五題：

```json
{
  "topics": [
    {
      "direction": "...",
      "openingLine": "...",
      "whyItWorks": "...",
      "nextMove": "..."
    }
  ],
  "recommendation": {
    "index": 0,
    "reason": "..."
  }
}
```

長度上限：

- `direction`: 80
- `openingLine`: 180
- `whyItWorks`: 400
- `nextMove`: 300
- recommendation reason: 300

任何缺欄、空白、超長、重複、項數不是五、推薦不存在、raw JSON／code fence 修不回，都必須整份失敗；不可丟掉壞題後仍扣 3。

對 client 的成功 response 至少包含：

```json
{
  "topics": [
    {
      "id": "nt_3",
      "direction": "...",
      "openingLine": "...",
      "whyItWorks": "...",
      "nextMove": "..."
    }
  ],
  "recommendation": {
    "topicId": "nt_3",
    "reason": "..."
  },
  "access": {
    "servedTier": "free",
    "limited": true,
    "totalCount": 5,
    "unlockedCount": 1,
    "lockedCount": 4
  },
  "usage": {
    "cost": 3
  }
}
```

Fresh response 與同 requestId replay 必須回資料庫儲存的同一份生成內容與 access；client body 的 `usage.cost` 固定為 3，不對外暴露會隨 transport 改變的 charged／replay flag，因此成功 body 可完全一致。實際有沒有新增扣點只記 server telemetry。

### 4. 24 小時防雙扣與原結果回放

不要重用或硬塞 `opener_request_charges`。新增 additive migration：

`supabase/migrations/20260724120000_new_topic_exactly_once.sql`

實作獨立 `new_topic_requests` ledger，使用目前 repo 最新的：

`preflight → claim → lease → generate → settle → replay`

固定規格：

- server-keyed HMAC；不得使用裸 SHA-256。
- Secret 名稱：`NEW_TOPIC_REPLAY_HMAC_KEY`。
- Base64 至少 32 random bytes。
- Secret 檢查只能在 `new_topic` 分支內；缺 secret 時只有 New Topic fail closed，不能讓 opener／analyze／OCR 一起掛。
- replay window 24 小時。
- lease 約 65 秒。
- ledger 只存已依 tier 投影的最終 response、access 與 recommendation。
- 不存 Partner／About Me／情境原文、prompt、raw provider output、token 或 telemetry。

Table 至少要有：

- `user_id`
- `request_id`
- `input_hash`
- `state` (`pending|done`)
- `owner_token`
- `lease_expires_at`
- `result_json`
- `quota_charged`
- `created_at`
- `updated_at`

RPC：

- `claim_new_topic_request`
- `release_new_topic_claim`
- `settle_new_topic_request`
- cleanup／contract marker

最重要的 correctness：

1. 同 user＋requestId＋HMAC 的 done request 在 24h 內直接回 stored result，不打模型、不再扣。
2. 同 requestId 但輸入 HMAC 不同回 409 mismatch。
3. active lease 回 pending/retry，不平行生成。
4. lease 過期可被新 owner 接手。
5. 只有「明確知道尚未開始 settle」的錯誤才可做 owner-bound release。
6. settle transport 結果不確定時絕對不可 release；回 retryable，client 保留相同 requestId 重試。
7. quota increment 與 result persist 必須在同一 DB transaction。
8. handler 永遠回 `settle_new_topic_request` 傳回的 stored result；即使本地候選不同，也要丟棄本地結果。
9. late／stale owner 不得覆蓋 first committed result。
10. cleanup 每小時清除超過 24h 的 rows。
11. table／RPC 權限遵守 RLS 與 service-role-only 寫入。

只用目標式 `apply_migration`；禁止 `supabase db push`。

### 5. 模型、deadline、rate limit

- Primary：Sonnet 5。
- 只有 retryable outage 才依現有 `analyze-chat` chain fallback：
  - Sonnet 5
  - Sonnet 4.6
  - Haiku 4.5
- Schema repair 最多一次，使用剛才成功輸出的同一 model，不得開 model fallback。
- Server request deadline 50 秒；generation deadline 45 秒；保留 5 秒 settlement reserve；Flutter client timeout 70 秒。
- 整個 primary／fallback／repair 共用總 deadline，並替 settlement 保留時間。
- 新增 rate-limit scope：
  - `new_topic`
  - 3/min
  - 30/day
- `MODEL_RATE_LIMITED` 429 永遠不等於 quota paywall。

### 6. Flutter 結構

新增獨立 slice，建議落點：

```text
lib/features/new_topic/
  domain/entities/
  domain/services/
  data/services/
  presentation/providers/
  presentation/widgets/
```

必須有：

- `NewTopicItem`
- `NewTopicRecommendation`
- `NewTopicAccess`
- `NewTopicResult`
- `NewTopicPartnerContextBuilder`
- `NewTopicService`
- `NewTopicRequestSession`
- Riverpod providers／controller
- `NewTopicView`
- `NewTopicCard`

UI／state 規則：

- `?mode=new_topic` 只決定初始 tab；使用者本地切換不要改 route。
- mode、Partner、情境、result、error、request session 的 state 要有清楚 owner。
- 生成中鎖定 Partner／情境。
- 同一 frozen input 的 transport retry 沿用 requestId。
- Partner／情境或生成素材改變才 rotate requestId。
- partnerId 改變時，即使 normalized summary 相同也必須 rotate requestId。
- 已有結果時要換 Partner／情境，先顯示會清除舊結果的確認。
- Free 顯示推薦一張完整卡＋一個「還有 4 個」CTA。
- Paid 顯示五張；推薦 badge 只能有一個。
- 複製只複製 `openingLine`。
- 使用者切到 Opener 再切回來，New Topic 結果必須還在。
- `NewConversationSheet` 入口文案改為能涵蓋兩個模式，例如「開場白／新話題」；本輪不加另一個 Partner 詳情頁 CTA。

### 7. 失敗矩陣必須逐態落測試

|情境|預期|
|---|---|
|非法 request／禁用欄位／超長|400；無 claim、無模型、扣 0|
|三類素材全空|422 `NEW_TOPIC_CONTEXT_REQUIRED`；扣 0|
|同 id 不同 HMAC|409 mismatch；不再扣|
|同 id 正在處理|409 pending＋retry；保留 requestId|
|done replay|200 同一 stored result；扣 0|
|ledger read／claim 不確定|503 fail closed；保留 requestId|
|模型限流|429 `MODEL_RATE_LIMITED`；release、扣 0、不開 paywall|
|真正 quota 不足|429 quota payload＋`quotaNeeded:3`；release、扣 0、開 paywall|
|合法五題|atomic 扣 3＋保存結果＋200|
|invalid，repair 成功|atomic 扣 3＋200|
|invalid，repair 仍失敗|502、release、扣 0|
|provider 全失敗|503、release、扣 0|
|generation deadline，且能證明 settle 尚未開始|504；owner-bound release 成功後扣 0|
|settlement 已送出後 timeout／結果不明|503 `NEW_TOPIC_SETTLEMENT_PENDING`；可能已 commit，絕對不可 release，同 ID retry|
|settlement quota race|transaction rollback；owner-bound release；扣 0|
|settlement transport ambiguous|503 retryable；可能已 commit，絕對不可 release|
|concurrent／late settle|回 first stored result；總扣 3|

### 8. 逐 concern commits

一件事一顆，使用繁體中文 commit message：

1. `開場救星免費版解鎖延展幽默微調侃三種`
   - Opener contract v2
   - backend entitlement／repair／recommendation
   - Flutter access／cache／handoff／UI
   - 對應測試
2. `新增新話題後端契約與原結果重播帳本`
   - migration
   - prompt／payload／billing
   - new mode integration
   - rate-limit scope
   - Deno／SQL tests
3. `新增新話題脈絡建構與前端資料層`
   - entities
   - Partner／About Me builders
   - service／request session／providers
   - unit tests
4. `開場救星加入新話題切換與結果介面`
   - route／IndexedStack
   - Partner／情境／cards／paywall
   - widget tests
5. `更新新話題定價決策與審查文件`
   - pricing
   - superseding ADR
   - 過時 README 文案
   - Review Packet／測試證據

每顆 commit 前：

- 檢查 staged file list。
- 不得混入 Practice、OCR、Coach 或其他人的髒檔。
- commit author 遵守 repo／Vercel 規則。
- push 到 `origin/claude/new-topic-brainstorm-feature-ibh6tz`。

### 9. 最低測試要求

Backend：

```text
deno test supabase/functions/analyze-chat/new_topic_*_test.ts
deno test supabase/functions/_shared/model_rate_limit_test.ts
deno test supabase/functions/analyze-chat/
deno check supabase/functions/analyze-chat/index.ts
```

Flutter：

```text
flutter analyze
flutter test <所有新增／更新的 targeted test files>
flutter test
```

SQL／真 PostgreSQL transaction smoke 至少驗證：

- concurrent claim 只有一個 owner。
- fresh settle usage 恰好 `+3`。
- replay usage 不變且 body 完全一致。
- lease takeover 後舊 owner不可覆寫。
- quota race 的 counter／result 同成同敗。
- invalid／extra-key result 無法入帳。
- anon／authenticated 無 ledger SELECT／EXECUTE。
- cron／cleanup／contract marker 存在。

不能用 targeted tests green 代替 full regression green；報告時分開列。

### 10. Review 與部署閘門

實作、測試、commit、push 後，準備 Review Packet：

- branch
- `BASE_SHA`
- `HEAD_SHA`
- exact range `BASE_SHA..HEAD`
- commit list
- changed files
- migration 名稱
- secret 名稱（只能寫名稱，不能寫值）
- targeted Deno／Flutter 結果
- full Deno／Flutter 結果
- 尚未執行的 live steps
- risk focus
- open concerns

接著停止，交 Eric 路由獨立 Codex task。CC 不在同一 workflow 自己觸發 Codex。

只有收到 `APPROVED` 才能進部署：

1. 目標式 `apply_migration`。
2. 驗證 RPC／RLS／cron／contract marker。
3. 設 `NEW_TOPIC_REPLAY_HMAC_KEY`，不得讀回或印出。
4. 部署單一：

```text
supabase functions deploy analyze-chat --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg
```

5. 禁止 `db push`。
6. 禁止 deploy `--all`。
7. 先做舊 App／Opener v1 smoke，再做 v2 與 New Topic。
8. 後端 smoke green 後才建立 TestFlight build。
9. Eric／Bruce dogfood 目檢：
   - 真的有用作戰板。
   - 沒把 About Me 興趣硬說成對方興趣。
   - openingLine 自然可直接送。
   - 冷場不硬推。
   - `whyItWorks` 不像推銷或 PUA 教材。
   - `nextMove` 可執行且不情勒。

### 11. 完成時請用這個格式回報

```text
狀態：
- IMPLEMENTED / BLOCKED

Branch：
- ...

Range：
- BASE_SHA..HEAD_SHA

Commits：
- <sha> <message>

實際 changed files：
- ...

Migration：
- ...

測試：
- Targeted Deno：PASS/FAIL；命令與摘要
- Full Deno：PASS/FAIL；命令與摘要
- Deno check：PASS/FAIL
- Flutter analyze：PASS/FAIL
- Targeted Flutter：PASS/FAIL；命令與摘要
- Full Flutter：PASS/FAIL；命令與摘要
- PostgreSQL transaction smoke：PASS/FAIL/NOT RUN

高風險自查：
- Free Opener v1/v2/paid：
- New Topic Free/paid：
- exact-once replay：
- 429/paywall：
- prompt grounding：
- opener/analyze/OCR regression：

未執行：
- deploy / live smoke / TestFlight（如實列出）

Open concerns：
- none / ...

Review Packet：
- <path>
```

不要只回「完成」或貼長測試 log；要提供可重現的命令、結果摘要、exact SHAs 與尚未做的步驟。
