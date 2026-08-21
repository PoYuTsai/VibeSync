# AI 實戰練習室「模擬社群動態（朋友圈）」實作開發報告

2026-08-21 初版（研究 + 架構設計 + 分階段實作計畫）。
2026-08-21 修訂一：P1 全域模型呼叫上限、P2 交付路徑，第 10 節產品項目改為已決策。
2026-08-21 修訂二（第二輪複審）：補 `reserve` 狀態轉移表並修正 `attempts` 起算與 token-null 分支（第 4 節）、縮小記憶承諾為三態契約（第 2、3 節）、feed 補生成加總死線（第 3 節）、長度守門三層對齊（第 5 節）、交付路徑改回「一 PR 一目的、base 指向 `main`」（第 9 節）。

**產品方向已確認，可以據此實作。** production migration 與 Edge 部署仍保持 pending，合併與發佈由 Eric 決定。

需求原文（Eric）：
> 「AI 實戰練習室」chatbot 的「模擬 social Media」。角色圖鑑已抽到的角色會在一個像 WeChat 朋友圈的區塊上傳貼文，
> 貼文內容可以是「純一段文字」或「一段圖片配文字」。這些 chatbot 角色都會記得在朋友圈上傳過的內容。
> 研究 DeepSeek Harness 如何讓這些角色每日新增隨機的貼文。

---

## 1. 現況事實（真相源，全部實地查證）

### 1.1 角色圖鑑

| 事實 | 位置 |
| --- | --- |
| 100 位角色，由 `GIRL_SEEDS` 推導（SR 10／R 30／N 60） | `supabase/functions/practice-chat/practice_persona.ts:908-937` |
| client catalog 是 **generated mirror**，禁止手改 | `lib/features/practice_chat/domain/entities/practice_girl_catalog.dart:1-4`，產生器 `tools/gen-practice-catalog/` |
| 「已抽到誰」唯一真相源＝server `practice_profile_draw_events`，client 不自己存 | `draw_handler.ts:397-421`、`practice_chat_api_service.dart:957-972` |
| 圖鑑畫面與抽卡儀式 | `practice_collection_screen.dart`（1444 行）、`practice_draw_ceremony.dart` |
| 已解鎖 id 的 Riverpod 真相源，換帳號自動失效 | `practice_chat_providers.dart:2792-2837`（`practiceCollectionOwnerProvider` → `practiceCollectionProvider`） |
| 角色照片＝bundled JPEG，`profileId == photoId`，載入失敗有色塊 fallback | `practice_girl_photo.dart`、`assets/images/practice_girls/`（100 張、13 MB） |

### 1.2 DeepSeek Harness（本次研究重點）

`supabase/functions/practice-chat/deepseek.ts`（84 行）就是整個 harness，非常薄：

- OpenAI 相容 `/chat/completions`，模型 `deepseek-v4-flash`，`stream: false`。
- 參數面：`maxTokens` / `temperature` / `jsonMode`（`response_format: json_object`）/ `thinking` / `timeoutMs`（`AbortController`）。
- **`thinking` 預設關掉**（`deepseek.ts:44-52` 有完整實測註記）：V4 預設開 thinking，reasoning tokens 算在 completion 內，會吃掉 380-415 tokens，導致分類器 6/6 `finish_reason=length`、聊天 1/3 回空字串。**新呼叫端一律沿用預設關閉。**
- 錯誤一律轉成穩定機器碼，永不外洩 provider body：`deepseek_http_{status}` / `deepseek_timeout` / `deepseek_empty_content` / `deepseek_max_tokens`。
- 沒有內建重試：重試由呼叫端做（chat 是 `CHAT_GENERATION_ATTEMPTS = 2` 的迴圈，`handler.ts:3981-4027`）。

現有三種呼叫姿勢（新功能直接沿用其一）：

| 用途 | maxTokens | temperature | jsonMode | 出處 |
| --- | --- | --- | --- | --- |
| 聊天可見文字 | 200 | 0.9 | 否 | `handler.ts:139-140, 4008` |
| 溫度／熟悉度分類器 | 450 | 0.2 | **是** | `handler.ts:160-161, 1411-1426` |
| Hint／Debrief | 500／1200 | — | 走 Claude `single_shot.ts`（Sonnet 5 → Haiku 4.5 failover） | `handler.ts:2861, 3613` |

共用逾時 `DEEPSEEK_TIMEOUT_MS = 30000`（`handler.ts:162`）。

### 1.3 「每日隨機」的既有範式（可直接複製）

`life_schedule.ts` 已經解決過同一類問題——她「今天在幹嘛」：

```ts
const seed = [profileId, time.isoDate, time.dayPart, threadId].join("|");
return events[fnv1a(seed) % events.length];   // life_schedule.ts:249-267
```

特性：**零 DB 狀態、純函式、同一天同一角色恆定、可 deno test**。事件池按 `dayPart` 分層，再疊加週末池 / 興趣池（關鍵字比對 `interestTags`＋`lifestyleTags`）/ 職業池。`acquaintance_origin.ts` 用同一招決定「你們怎麼認識的」。台北牆鐘由 `time_context.ts` 提供（`dawn`→`late_night` 七段、`isWeekend`）。

**這就是「每日隨機貼文」的正解骨架：隨機性由種子決定，DeepSeek 只負責把既定的題材寫成人話。**

### 1.4 記憶怎麼跨場成立

- `public.practice_relationship_threads`（`20260708130000_...sql`）：`memory_summary`（≤1000 字）、`recent_facts` jsonb、`partner_mood`、`invite_stage`…，RLS 開啟且**無 policy → service_role only**，寫入走 `upsert_practice_relationship_thread` RPC。
- prompt 注入一律包防注入封套：`memorySummaryPrompt()`（`prompt.ts:81-89`）用 `<older_memory_untrusted>` 標記，並附 Reality Anchoring 規則（「不能單獨證明共同朋友／行蹤／上次見面」）。
- 練習對話本身仍是 **Hive local-only（最近 5 場）**，server 只存計數不存內容（`20260624074944_practice_chat_sessions.sql` 開頭的隱私拍板）。

### 1.5 可見文字的守門（新產出的貼文必須全部通過）

- `toTraditionalChinese()`（`_shared/traditional_chinese.ts`）——DeepSeek 偶爾吐簡體。
- `rejectVisibleInternalLabelLeak()`／`rejectL4UnsafeVisibleText()`（`visible_text_guard.ts`）。該檔明寫**鐵則：注入內部詞必同步擴可見輸出守門**。
- `scrubRawImageFilenames()` / `containsRawImageFilename()`（`prompt_sanitizer.ts`）——檔名一律換成 `[image concept omitted]`。
- **絕不罐頭**：`generated_only_source_test.ts` 用讀原始碼的方式硬性禁止 `buildFallbackHintResult` 這類 fallback；失敗必須釋放 latch 並回 retryable，不得寫假成功（`20260711150000_practice_ai_no_canned_fallback.sql`）。

### 1.6 節流與排程基礎設施

- per-user 模型限流：`_shared/model_rate_limit.ts` 的 scope 白名單（`practice_turn` 12/min・400/day 等），計數表 `model_call_rate_limits` PK `(user_id, scope)`，超限 `RAISE` → Edge 映 429。
- **pg_cron 已在用**（`keyboard_assist` / `keyboard_reply` 的清理 job，`20260727130000_...sql:215-235`）。
- **pg_net 沒有啟用**：全 repo 零 `net.http_post`。→ 目前 cron 只能跑純 SQL，**不能主動打 Edge Function**。
- CI secrets 只有 `SUPABASE_ACCESS_TOKEN` / `SUPABASE_PROD_URL` / `SUPABASE_PROD_ANON_KEY`，**沒有 service role key**。

---

## 2. 產品定義（本報告採用的規格）

1. 新區塊「動態」：只顯示**這個帳號已抽到**的角色的貼文，倒序時間軸，版面近似 WeChat 朋友圈。
2. 貼文型態兩種：**純文字**、**圖＋文**。
3. 每位角色**每日隨機**新增 0～2 則（多數日子 0 或 1 則）。
4. 角色在 1:1 聊天中**記得自己最近七天內發過的貼文**：使用者提到時能自然承接。
   **超出這個窗口的貼文她不否認、也不硬掰**，用不確定語氣帶過（理由見決策 E）。

---

## 3. 架構決策（含替代方案與理由）

### 決策 A：貼文是**全域內容**，不是 per-user 生成 ★最關鍵

同一則貼文，所有抽到她的使用者看到的一模一樣。

- **隱私鐵則**：若貼文由「她跟某使用者的對話」生成，A 的私人對話會透過貼文外洩給 B。這一條單獨就足以否決 per-user 方案。
- **成本**：per-user＝角色數 × 使用者數；全域＝每天最多 100 位角色 × 2 slot × 3 attempts = **≤600 次模型呼叫/天，與使用者數無關**（見決策 C 與第 4 節）。
- **真實性**：朋友圈本來就是「她發一則，所有好友看到同一則」。

**硬規則（要寫進程式碼註解與測試）：貼文生成的輸入只有 server profile + 日期 + 場景種子，永不包含任何使用者對話、暱稱、hint、debrief、relationship thread。**
延伸限制：貼文內容必須自我完足的生活內容，**不得提及「你」、不得寫成訊息、不得問句拉人回覆**（否則全域內容會對某個使用者說錯話）。

### 決策 B：「每日隨機」＝ 種子決定骨架，模型只負責寫字

三層決策全部由 `fnv1a(seed)` 純函式決定，完全複製 `life_schedule.ts` 的範式：

```
seed = `${profileId}|${isoDate}|moment|${slot}`

第 1 層 今天發不發？  → postPropensity(persona, lifestyleTags) → 種子擲骰
第 2 層 幾點發？      → dayPart（配合她的職業作息，護理師不會上班時間發）
第 3 層 發什麼題材？  → themeId 從（基礎池 ∪ 週末池 ∪ 興趣池 ∪ 職業池）挑
                     → wantsImage（純文字 or 圖＋文）
                     → imageId 候選（allowlist）
```

只有最後「把 theme 寫成她的口氣」交給 DeepSeek。

- **為什麼不讓模型自由發想**：可重現、可審核、成本可預測、圖片必須落在 allowlist；且完全符合本專案「server 是唯一真相源、client 只送 id」的既有安全邊界。
- **為什麼不用純靜態模板**：違反 no-canned 鐵則，而且 100 位角色共用模板一天就被看穿。
- **同一天重跑得到同一則**：生成失敗可安全重試，不會產生第二則不同內容的貼文。

### 決策 C：觸發時機——**有界懶生成**（P1），排程預熱列 P4 選配

| 方案 | 內容 | 判定 |
| --- | --- | --- |
| C1 pg_cron + pg_net | DB 排程直接打 Edge | ✗ 需啟用 pg_net + 把 service key 放進 DB Vault＝**憑證操作，需 Eric 當次授權** |
| C2 GitHub Actions `schedule` | CI 每日打 batch endpoint | ✗ P1 不做：需要新增 CI secret（service role key 或共享密鑰），安全等級升高 |
| **C3 有界懶生成** | 讀 feed 時補生成缺的貼文，單次請求最多 K 則 | ✓ **採用**：零新基礎設施、零新憑證、零 pg_net |

C3 之所以在這個產品成立，正是因為決策 A：**貼文全域共用**。今天只要有任何一位使用者開過動態，那位角色今天的貼文就已存在，之後所有人都是純讀取。以 TestFlight dogfood 的使用者量，實際 DeepSeek 呼叫量趨近「每天 ≤200 次」。

防重複生成與防慢請求：

- `INSERT ... ON CONFLICT DO NOTHING` 原子搶生成權（`unique(profile_id, post_date, slot)`），沒搶到的請求直接讀既有資料，**多人同時開不會重複打模型**。
- 單次請求最多補 **K = 3** 則（優先補「使用者最近聊過 / 最新解鎖」的角色），其餘留給下一次請求或 client 背景補位請求。
- **補生成有總死線，不是 K × 單次逾時**（複審 2026-08-21 P2）：
  - `MOMENT_FILL_DEADLINE_MS = 8000`，從進入 handler 起算。
  - K 則**平行**送出（`Promise.allSettled`），不是循序；每一則的 `timeoutMs` 取 `min(20000, 剩餘死線)`。
  - 死線到就不等：已完成的照常回，未完成的這次就是沒有——**列仍在 DB，token 由下一次請求或租約逾時接手**，不浪費 attempts。
  - 所以 feed 最壞回應時間是 **8 秒，與 K 無關**。原文只寫 K=3、單次 20 秒，循序最壞會到 60 秒。
- 缺貼文時 feed 顯示既有內容即可，**不塞罐頭、不報錯**（沿用 no-canned 鐵則）。

**全域模型呼叫上限**：`unique(profile_id, post_date, slot)`（slot ∈ {0,1}）×「每個 slot 最多 3 次認領」→ **全站每日模型呼叫硬上界 600 次**，與使用者數、重新整理次數完全無關。

> 這一段在第一版是錯的（2026-08-21 複審 P1）。原本寫「schema 自帶 200 次上限」，但當時的設計是失敗即刪佔位列，`unique` 就只能限制成功存下來的貼文數，限制不了模型呼叫。現在改成保留列 + `attempts` 計數（見第 4 節），上限才真正由 schema 與 RPC 共同強制，不是口頭承諾。

per-user 面另掛既有 `model_call_rate_limits` 的新 scope `practice_moment`（建議 6/min・60/day），擋單一帳號放大。

### 決策 D：圖片來源——**bundled 場景圖 allowlist**

沒有圖像生成能力，且不能產生像真實人物的新圖。三選項：

| 方案 | 判定 |
| --- | --- |
| D1 重用她本人的人像 | ✓ 零新資產，適合「自拍／今天的我」類貼文 |
| **D2 共用生活場景圖庫 + allowlist id** | ✓ **主力**：咖啡、海邊、貓、甜點、展覽、健身、夜景、書桌… |
| D3 Supabase Storage / CDN | ✗ P1 不做：多一層基礎設施＋審核＋離線失效 |

實作 = D1 + D2 混合。**模型只能回傳 allowlist 內的 `imageId`，client 自己 map 到 bundled asset**——與現行 `photoId` 完全同一套安全模型；渲染沿用 `PracticeGirlPhoto` 的 `errorBuilder` fallback 慣例。

Bundle 預算：現況 `assets/images/practice_girls` 13 MB / 100 張（約 130 KB/張）。**P1 建議 20 張 WebP 場景圖，控制在 2-3 MB**；需在 `pubspec.yaml:94-102` 新增 `assets/images/practice_moments/` 並補 `docs/licenses` 授權紀錄。

### 決策 E：記憶怎麼成立——貼文是**server 權威事實**，不是 untrusted memory

因為貼文全域且由 server 生成落庫，它比 `memorySummary` 可信一級：

- `prompt.ts` 新增 `herRecentMomentsPrompt()`，`buildChatMessages()` 增一個 optional 欄位；handler 讀她最近 7 天、最多 3 則 ready 貼文注入。
- 仍然包防注入封套（比照 `memorySummary` 慣例），並加**現實錨定**：貼文只證明「她自己做過什麼」，**不能證明對方在場、不能當成共同回憶**。
- 使用者提到**注入窗口內**真實存在的貼文 → 自然承接。
- 使用者捏造貼文 → 自然疑惑，**但不得斷言「我沒發過」**。

> **承諾範圍已縮小（2026-08-21 複審 P1）。** 第一版寫「存在就承接、捏造才否認」，那做不到：prompt 只注入最近 7 天／最多 3 則，第 8 天的真貼文她一樣看不到，照「捏造就否認」的規則會**否認自己真的發過的東西**——那比忘記更傷人設。
>
> 正確的契約是三態，不是兩態：
>
> | 使用者提到的貼文 | 她看得到嗎 | 該有的反應 |
> | --- | --- | --- |
> | 七天內、確實存在 | 看得到 | 自然承接，可延伸聊 |
> | 七天外、確實存在 | **看不到** | 不確定語氣（「有喔？我忘了」「哪一篇啊」），**不否認** |
> | 完全捏造 | 看不到 | 同上——不承認也不斷言否認，可要細節 |
>
> 「七天外的真貼文」與「捏造」在她眼中無法區分，所以兩者共用同一種安全反應。這不是妥協，是唯一誠實的實作：模型不該對自己看不到的事下斷言。
>
> 若日後要做到全歷史可判真，需在生成端加一次查詢（把使用者訊息裡疑似指涉貼文的片段拿去比對 `practice_moment_posts` 全歷史），那是額外的 DB round-trip 與一組比對規則，屬另案，不在首版。
- 長度控制：每則裁到 60 字，直接用既有 `compactCompleteSentenceEvidence()`（`prompt.ts:91-115`）。
- **鐵則連動**：新注入的內部標籤（`herMoments` / `momentTheme` / `momentDayPart`…）必須同步加進 `visible_text_guard.ts` 的 `INTERNAL_VISIBLE_LABELS`，否則模型會原樣抄進可見回覆而沒人攔。

---

## 4. 資料模型（migration 草案）

新檔 `supabase/migrations/2026MMDDHHMMSS_practice_moment_posts.sql`（純加法）：

```sql
CREATE TABLE IF NOT EXISTS public.practice_moment_posts (
  profile_id       TEXT        NOT NULL,          -- Edge 以 allowlist 驗證
  post_date        DATE        NOT NULL,          -- 台北日
  slot             SMALLINT    NOT NULL CHECK (slot BETWEEN 0 AND 1),
  day_part         TEXT        NOT NULL,
  theme_id         TEXT        NOT NULL,
  status           TEXT        NOT NULL CHECK (status IN ('reserved','ready','exhausted')),
  -- 已消耗的模型呼叫次數。認領時就 +1（不是失敗時才 +1）：worker 中途死掉
  -- 也算用掉一次，否則 crash loop 仍然無界。這一欄是全域成本上限的來源。
  attempts         SMALLINT    NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
  body             TEXT        CHECK (body IS NULL OR char_length(body) BETWEEN 1 AND 220),
  image_id         TEXT,                          -- NULL = 純文字貼文
  generation_token TEXT,                          -- token-fenced latch（比照 debrief）
  reserved_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  model            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (profile_id, post_date, slot),
  CONSTRAINT practice_moment_ready_has_body
    CHECK (status <> 'ready' OR (body IS NOT NULL AND char_length(btrim(body)) > 0))
);

ALTER TABLE public.practice_moment_posts ENABLE ROW LEVEL SECURITY;  -- 無 policy = service_role only
CREATE INDEX IF NOT EXISTS practice_moment_posts_date_idx
  ON public.practice_moment_posts (post_date DESC, profile_id);
```

RPC（全部 `SECURITY DEFINER` + `REVOKE ... FROM PUBLIC, anon, authenticated` + `GRANT ... TO service_role`，比照現有慣例，結尾 `NOTIFY pgrst, 'reload schema'`）：

| RPC | 職責 |
| --- | --- |
| `reserve_practice_moment_slot(...)` | 依下方狀態轉移表判定，回傳 `{ claimed, token }` |
| `commit_practice_moment_post(profile_id, post_date, slot, token, body, image_id, model)` | 只有持 token 者能改 `ready`；不匹配回 false |
| `release_practice_moment_slot(profile_id, post_date, slot, token)` | 生成失敗時清 token；`attempts` 已達上限就一併轉 `exhausted`。**絕不刪列、絕不寫罐頭** |
| `list_practice_moment_posts(profile_ids TEXT[], since DATE)` | 只回 `ready` |

### `reserve` 狀態轉移表（複審 2026-08-21 P1 要求明確化）

`MAX_MOMENT_ATTEMPTS = 3`。所有判定在同一交易內，先 `INSERT ... ON CONFLICT DO NOTHING`，未插入則 `SELECT ... FOR UPDATE` 鎖列再走下表。

| 進入時的列狀態 | 動作 | 結果 |
| --- | --- | --- |
| 不存在（INSERT 成功） | 寫入 `status='reserved'`、**`attempts = 1`**、`generation_token = :token`、`reserved_at = now()` | ✅ 放行（這是第 1 次） |
| `ready` | 不動 | ❌ 拒絕，不呼叫模型 |
| `exhausted` | 不動 | ❌ 拒絕，不呼叫模型 |
| `reserved` 且 `generation_token IS NOT NULL` 且 `reserved_at > now() - 2min` | 不動 | ❌ 拒絕（別人正在跑，租約still有效） |
| `reserved` 且（`generation_token IS NULL` **或** 租約已逾時）且 `attempts < 3` | `attempts + 1`、換發 token、`reserved_at = now()` | ✅ 放行 |
| `reserved` 且（token 為 NULL 或租約逾時）且 `attempts >= 3` | 轉 `status='exhausted'`、清 token | ❌ 拒絕 |

兩個容易寫錯、複審點名的地方：

1. **首次 INSERT 必須明寫 `attempts = 1`，不能靠 `DEFAULT 0`。** 用預設值 0 的話，第一次認領不計數，之後還能再遞增三次 → 每 slot 實際跑 4 次、全站每日 800 次，上限就不是 600。
2. **`generation_token IS NULL` 必須是獨立的放行分支。** `release` 的用途就是「我失敗了，別人不必等租約逾時就能接手」；若 `reserve` 只看租約時間，被 release 的列會被自己的新鮮 `reserved_at` 擋住兩分鐘，等於 release 沒有作用。

`attempts` 的 CHECK 上界與 `MAX_MOMENT_ATTEMPTS` 必須一起改；migration source test 要斷言這兩個數字相同。

**向後相容**：純新增表與函式，舊版 client / 舊版 Edge 完全不碰它 → 可安全先套 migration 再上 Edge（符合 shared-agent-rules 的「migration 先於依賴它的 Edge 碼」）。

---

## 5. Edge 實作（`practice-chat` 新增 mode，純加法 dispatch）

沿用 `draw_handler.ts` 的先例：**自包含、回傳 `{ body, status }`、可用 mock client 單元測試、與 chat/debrief 路徑 byte-for-byte 隔離**。

### 新檔案

| 檔案 | 內容 | 依賴 |
| --- | --- | --- |
| `moments_schedule.ts` | `momentPlanFor({ profile, time })` → `{ slots: [{slot, dayPart, themeId, wantsImage, imageCandidates}] }`；主題池（基礎／週末／興趣／職業）＋ `fnv1a` 選擇 | **零依賴純函式** |
| `moments_image_catalog.ts` | 場景圖 allowlist：`imageId` + 主題標籤 | 零依賴 |
| `moments_prompt.ts` | `buildMomentMessages()` | prompt_sanitizer |
| `moments_validate.ts` | JSON 解析 + 長度／語言／allowlist／守門 | visible_text_guard 等 |
| `moments_handler.ts` | `handlePracticeMoments()`：讀已解鎖 → 讀既有貼文 → 算今日計畫 → 補生成 ≤K 則 → 回 feed | 上列全部 |
| 對應 `*_test.ts` | 每檔一份 deno test | — |

### handler.ts 改動（極小）

```ts
if (isPlainObject(rawBody) && rawBody.mode === "practice_moments") {
  const result = await handlePracticeMoments({ supabase, userId: user.id, now: new Date(), deps });
  return jsonResponse(result.body, result.status);
}
```
插在既有 `practice_collection` 分支旁（`handler.ts:1877`）。

### DeepSeek 呼叫參數（本次研究結論）

```ts
await deps.callDeepSeek({
  apiKey,
  messages: buildMomentMessages({ girl, theme, dayPart, isoDate, imageCandidates }),
  maxTokens: 200,          // 貼文 20-60 字；比照 CHAT_MAX_TOKENS
  temperature: 0.95,       // 略高於聊天 0.9：100 位角色要看得出差異
  jsonMode: true,          // { "text": "...", "imageId": "..." | null }
  // thinking 不傳 → 沿用 deepseek.ts 預設 disabled（理由見 deepseek.ts:44-52）
  timeoutMs: 20000,        // 低於 chat 的 30s：背景補位不該拖住 feed
});
```

- 重試：**單次請求內不重試**（打一次就好，失敗即 release）。跨請求的重試由 `attempts` 控制，全域上限 3 次；第 3 次仍失敗 → slot 轉 `exhausted`，那位角色今天這一則就留白，隔天是新的 `post_date` 自然重來。
  這裡刻意不沿用 chat 的 `CHAT_GENERATION_ATTEMPTS = 2`：chat 是使用者正在等的前景請求，值得當場多試一次；貼文是背景補位，當場重試只會拖慢 feed，而且 `attempts` 已經提供跨請求的重試，兩層疊加會讓成本上限變成 200 × 3 × 2 = 1200。
- **為什麼是 DeepSeek 而不是 Claude `single_shot`**：貼文是「她的口語」，必須跟聊天同一把聲音、同一個模型；`single_shot.ts` 是給結構化教練產出（hint/debrief）的 forcedTool 契約，貴且形狀不符。
- **為什麼開 jsonMode**：要同時拿回 `text` 與 `imageId`，且 `imageId` 必須落在 allowlist——結構化輸出才驗得動。這正是既有分類器路徑（`handler.ts:1411-1426`）的用法。

### prompt 骨架（`moments_prompt.ts`）

system 段的硬約束（每一條都要有對應測試）：
1. 你是 {displayName}，{age} 歲，{professionLabel}，在 {city}。這是你自己的社群動態，不是傳訊息給誰。
2. **繁體中文**，20-60 字，第一人稱，生活感，語氣符合你的個性 {personalityTags}。
3. **絕對不可以**提到任何特定的人、對象、「你」、任何對話內容；不可以問問題拉人回覆；不可以像廣告或文案。
4. 不得出現真實品牌、真實店名、真實地址（沿用 `professionPrompt` 的既有禁令）。
5. 若 `wantsImage`，從候選 `imageId` 挑一個最貼題材的；否則 `imageId: null`。
6. 掛 `PROMPT_LEAK_DEFENSE_DIRECTIVE`（`_shared/prompt_leak_guard.ts`，現行所有 prompt 都掛）。

user 段只餵 server 事實：`themeId` 的中文題材描述、`dayPart`、是否週末、她的 `interestTags`／`lifestyleTags`／`professionPrompt`、候選 imageId 清單。**不餵任何使用者資料。**

### 驗證管線（`moments_validate.ts`，失敗一律 release 不落盤）

```
JSON.parse → text 必為字串
→ 長度 18..66 字（產品規格 20-60 的 ±10% 容差，見下）
→ toTraditionalChinese()
→ containsRawImageFilename() 命中即拒
→ rejectVisibleInternalLabelLeak()
→ rejectL4UnsafeVisibleText()
→ 禁詞掃描（「你」「妳」等第二人稱、問號結尾）→ 命中即拒
→ imageId ∈ allowlist ∩ 本 slot 候選（否則降級為純文字貼文）
```

**長度是三層，數字必須對得起來（複審 2026-08-21 P2）**：第一版 prompt 寫「硬限制 20-60 字」，驗證卻收 1-220，等於完全沒守。現在：

| 層 | 範圍 | 角色 |
| --- | --- | --- |
| prompt 指示 | 20-60 字 | 告訴模型要寫多長 |
| `moments_validate` | **18-66 字** | 真正的產品守門。留 ±10% 容差是因為打回一則就吃掉一次 attempts；為了 61 字丟掉一則好貼文不划算 |
| DB `CHECK` | 1-220 字 | 縱深防禦，擋的是程式碼繞過驗證直接寫入，不是產品規格 |

容差刻意寫死在常數並附測試；若上線後發現打回率偏高，**要調的是 prompt 的引導方式，不是偷偷放寬驗證**。

---

## 6. Flutter 實作

| 層 | 檔案 | 說明 |
| --- | --- | --- |
| domain | `practice_moment_post.dart` | `profileId` / `postDate` / `dayPart` / `body` / `imageId?`；Hive adapter（沿用 `practice_message.g.dart` 慣例） |
| domain | `practice_moment_image_catalog.dart` | **generated mirror**，比照 `practice_girl_catalog.dart` 由 `tools/gen-practice-catalog` 產出並加 sync test |
| data | `practice_chat_api_service.dart` | 新增 `fetchPracticeMoments()`（`mode: 'practice_moments'`）；失敗丟例外**絕不退回空集合假裝沒貼文**（沿用 `fetchPracticeCollection` 既有原則） |
| data | `practice_moments_repository.dart` | Hive box `practice_moments`，TTL 24h，離線可看昨天的 |
| data | `practice_chat_providers.dart` | `practiceMomentsProvider`（AsyncNotifier），owner 綁 `practiceCollectionOwnerProvider` → 換／刪帳號自動清空 |
| ui | `practice_moments_screen.dart` | 朋友圈版面：頭像＋名字＋相對時間＋文字＋可選圖；下拉重整 |
| ui | `practice_moment_card.dart` | 單則卡片；圖片走 `Image.asset` + `errorBuilder` fallback |
| route | `lib/app/routes.dart` | `/practice-moments`，入口放 `/practice-collection` 頭部（`_CollectionHeader` 下方一列） |

空／錯狀態：
- 尚未解鎖任何角色 → 引導去翻牌（複用既有 CTA 樣式）。
- 已解鎖但今天還沒有貼文 → 「大家今天還沒發文」＋顯示更早的貼文，**不是錯誤畫面**。
- 載入失敗 → 明確重試按鈕。

---

## 7. 隱私、安全、App Review

1. **跨帳號外洩面＝0**：決策 A 的硬規則保證貼文不含任何使用者資料。建議寫一個讀原始碼的測試（比照 `generated_only_source_test.ts`）硬性禁止 `moments_prompt.ts` import 任何 turns／thread／memory 型別。
2. **內容是 app 生成，不是 UGC**：P1 **不做**留言／按讚，畫面上不出現任何使用者可發布的欄位——這一刀讓 App Review 的 UGC（1.2 使用者生成內容）條款不適用。
3. **AI 揭露**：動態頁需比照練習室既有的 AI 揭露慣例標示「AI 模擬練習內容」（實作前確認現行揭露文案位置，與 `ai_data_sharing_consent.dart` 對齊）。
4. **圖片授權**：新增場景圖必須是自有或可商用授權，登錄 `docs/licenses`；**不得生成像真實人物的新圖**。
5. **成年設定**：貼文可見文字走與 chat 完全同一組 L4 守門，沒有第二套標準。
6. **額度**：建議**讀取動態完全免費、不扣 quota**——貼文全域生成，邊際成本趨近 0，也符合「Free 用戶核心可用到額度真的耗盡為止」的既有產品原則。成本上界由 schema 的 unique 約束保護。

---

## 8. 成本量級

每則貼文約 600 prompt tokens + 120 completion tokens（`maxTokens: 200` 封頂）。

- **最壞情況**（每個 slot 都用滿 3 次認領才放棄）：100 角色 × 2 slot × 3 attempts = 600 次模型呼叫 → **約 43 萬 tokens/天**。這是真正的天花板，由 schema 與 RPC 強制。
- **成功路徑上界**（每個 slot 一次就成功）：200 次呼叫 → **約 14.4 萬 tokens/天**。
- **實際預期**：發文率經 PR 1 實測為 0.661 則/角色/天 → 每天約 66 次呼叫 → **約 4.8 萬 tokens/天**。
- 最壞情況與實際預期差 9 倍，但最壞情況只在 provider 全面故障時才會發生——而那時候呼叫本來就會失敗、不產生 completion tokens。真正要盯的是**持續性的守門失敗**（例如 prompt 改壞導致大量候選被 `moments_validate` 打回），那會讓 attempts 天天燒滿。上線第一週要看 `exhausted` 列的比例，超過 5% 就是 prompt 或守門有問題。
- 這個量級與**使用者數無關**（決策 A）。以 `deepseek-v4-flash` 的定位屬極低成本，但**具體金額請以實際帳單為準**——repo 內 `docs/api-cost-management.md` 目前沒有 DeepSeek 的單價紀錄，我不憑印象填數字。
- 建議上線後在 `ai_logs` 用既有 `buildPracticeAiLogRow()`（`telemetry.ts:264`）打 `mode: "moment"` 標記，第一週對帳。

---

## 9. 分階段實作計畫（每階段可獨立驗證、可獨立回滾）

| 階段 | 內容 | 風險 | 驗證 |
| --- | --- | --- | --- |
| **P0** | `moments_schedule.ts` + 主題池 + `moments_image_catalog.ts` + 測試 | 零（純函式、無 DB、無模型、無 UI） | `deno test --allow-read supabase/functions/practice-chat/moments_schedule_test.ts` |
| **P1** | migration（表 + 4 個 RPC）+ `moments_prompt/validate/handler` + `mode` dispatch + 測試 | 中（新表、新模型呼叫） | `deno fmt --check`；`deno test --allow-env --allow-read supabase/functions/practice-chat/`（全套現況 850+ 應維持全綠）；migration source test |
| **P2** | 場景圖資產 + Flutter feed（model/service/provider/screen/route） | 低（新畫面，不動既有路徑） | `flutter analyze`；`flutter test`；新增 widget test |
| **P3** | 記憶注入：`herRecentMomentsPrompt()` + `visible_text_guard` 標籤同步 + `prompt_test` | 中（動到 chat prompt＝高風險區） | `prompt_test.ts` / `index_test.ts` 全套；離線重放檢查她不會把標籤抄進可見回覆 |
| **P4（選配）** | 排程預熱、按讚/留言、推播 | 高（憑證／UGC／額度） | 需 Eric 另案拍板 |

指令依 `.agent/environment.json`：Flutter 走 WSL（`analyze` / `test`），Deno 測試依 `flutter-ci.yml:41-51` 的既有形式。

### 交付路徑（依 `AGENTS.md` 兩人協作流程；取代原本的 umbrella 集成分支規劃）

**一個 PR 一個目的，base 是 `main`。** 每個 PR 都要能獨立測試、獨立合併、獨立回退。

- 依賴未落地的 PR 時，**可以暫時**把 base 指向那個 Draft parent；**parent 一落地就要 retarget 回 `main` 並跑正常 CI**，這是共享規則明訂的臨時措施，不是常態架構。
- 第一版把四個實作 PR 都規劃成合進 umbrella 集成分支，而那條分支已知不跑 CI——等於用一個永久結構換來零守門。**已作廢**（複審 2026-08-21）。
- 例行 PR **不跑** `Build & Distribute`；那是給「直接推 `main`」的單人流程設計的守門。
- 真機驗收綁功能完整度，不綁每個 PR：PR 1 / PR 2 在真機上沒有可見行為。
- 合進 `main`、`Release to App Stores` 由 Eric 收尾；agent 不觸發、不合併。
- 交棒用**唯一一個** `next:*` 標籤（`next:eric-ai` / `next:bruce` / `next:discuss`），與 Draft/Ready 無關；完成一輪就在同一個動作換掉舊標籤。

實際順序：

| PR | base | 何時 retarget |
| --- | --- | --- |
| 設計稿（本 PR） | `main` | — |
| 排程純函式 | 暫時指向設計稿 PR | 設計稿落地後改回 `main`，跑正式 PR CI |
| 後端／前端／記憶 | `main` | — |

> 附帶結論：`flutter-ci.yml` 的 `pull_request.branches: [main]` 只認 base 為 `main` 的 PR。回到「一 PR 一目的、base 指向 `main`」之後，**這個限制不再是問題**——只有暫時掛在 Draft parent 底下的那段期間沒有 CI，而那段期間本來就短。先前提議改 CI 觸發條件的事因此撤回，不必為了 umbrella 架構去動共享 workflow。

---

## 10. 產品決策（2026-08-21 群組討論已確認）

以下七項在 2026-08-21 的群組討論中確認產品方向，**不再是待拍板**。實作以本表為準；日後要改請直接改這張表並註記日期。

| # | 決策 | 內容 | 狀態 |
| --- | --- | --- | --- |
| 1 | 貼文可見範圍 | **全域共用**——同一角色同一天的貼文，所有抽到她的人看到同一則。per-user 生成會讓使用者的私人對話外洩給其他人，且成本隨使用者數成長 | ✅ 已決策 |
| 2 | 場景圖預算 | 首版 20 張 WebP，控制在 2-3 MB | ✅ 已決策 |
| 3 | 按讚／留言 | **首版不做**——會一次打開額度、內容審核與 App Review UGC 三個面 | ✅ 已決策 |
| 4 | 額度 | 看動態**不扣額度**。貼文全域生成，多一人看的邊際成本趨近 0；也符合 Free 用戶核心功能可用到額度真的耗盡的既有原則 | ✅ 已決策 |
| 5 | 每角色每日則數 | 0-2 則。PR 1 實測平均 0.661 則／角色／天 | ✅ 已決策 |
| 6 | 排程預熱 | **首版不做**。需要 pg_net 或新 CI secret，屬憑證操作；使用者量上來再另案處理 | ✅ 已決策 |
| 7 | 入口位置 | 獨立路由 `/practice-moments`，入口卡片放在角色圖鑑頭部 | ✅ 已決策 |

### 仍然待決（與產品方向無關，是流程／基礎設施）

| 項目 | 卡在哪 |
| --- | --- |
| PR 3 的真機驗收路徑 | branch build 連正式後端，但 `AGENTS.md` 禁止從非 `main` 分支部署正式 Edge。PR 3 開始前要決定走法 |

---

## 11. 刻意不做

- 不做圖像生成、不做上傳外部圖片。
- 不做「貼文引用使用者對話」的個人化貼文（隱私鐵則）。
- 不做罐頭貼文 fallback（no-canned 鐵則）。
- 不動 chat／hint／debrief 的既有路徑（`draw_handler` 先例：純加法 dispatch，既有路徑 byte-for-byte 不變）。
- 不在 P1 引入 pg_net、新 CI secret、新 Edge Function。
