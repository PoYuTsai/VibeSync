# 訂閱送 SR 限定翻牌（批 2）Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Starter/Essential 訂閱者獲得終身一次「SR 限定翻牌」券：圖鑑金券入口、保底 SR 的抽卡儀式、Free 看得到鎖定券當升級鉤子。

**Architecture:** 券獨立成表 `practice_sr_draw_tickets`（絕不塞進 `practice_draw_bonuses`——主 claim RPC 對該表 FOR UPDATE＋懶消耗，一人一列假設是它的加固語意，多列會壞鎖與誤消耗）。消耗走新 RPC `claim_practice_sr_ticket_draw`（顯式 claim，與抽卡事件同交易原子），事件表加 `bonus_source` 欄讓主 RPC 的 free_used 計數排除券抽（否則券會偷吃每日免費額度）。Grant 由 server 驗 tier（讀 `subscriptions`，不信 client），冪等 upsert，既有訂閱者首次呼叫自然回溯補發。設計拍板見 `docs/plans/2026-08-08-subscription-sr-draw-and-game-intro-design.md`。

**Tech Stack:** Postgres migration（走 shared-agent-rules 目標式 migration，禁 `supabase db push`）、Deno Edge（practice-chat）、Flutter/Riverpod。

**交付順序鐵則:** migration 先在 production 完成並驗證，才能 push 依賴它的 Edge code 到 main（AGENTS.md）。

---

## 事實基礎（已讀碼確認）

- 抽卡流程：client `drawProfile(requestId, currentProfileId, catalogSize)` → Edge `draw_handler.ts`（`prepare_practice_subscription_usage` 鎖內讀訂閱 → 算 tier 額度 → 全歷史去重 → `selectPracticeDrawProfile`（FNV seed、稀有度加權）→ `claim_practice_profile_draw` RPC 原子扣費）。
- 主 RPC 的 free_used ＝ 本窗 `cost_messages = 0` 事件數（4 個計數位點：step 1 replay、2a 鎖後 replay、step 3、unique_violation replay）。SR 券抽也是 cost=0，**必須**以 `bonus_source IS NULL` 排除，否則偷吃 tier 每日額度。
- `practice_profile_draw_events` CHECK `cost_messages IN (0,5)`；unique (user_id, request_id)＋(user_id, profile_id, reset_window_start_at)（撞號→PROFILE_CONFLICT 換張重抽）。
- 起步贈抽 grant 先例：handler `mode: 'grant_onboarding_draw_bonus'`（upsert ignoreDuplicates→讀回 consumed）；client `grantOnboardingDrawBonus()`。
- SR 池約 20 位（`SR_PROFILE_IDS`）；`selectPracticeDrawProfile` 有 catalogSize 切池＋排除退避，SR filter 須在切池後套用。
- Paywall：翻牌 benefit row 在 `_buildFeatureComparisonTable`；購買成功走 `_showSnackBar('方案已更新…')` → `_leavePaywall`。
- `migration_source_test.ts` 逐 migration 檔 assert SQL 片段——新 migration 要加 guard。
- index_test 的 fake RPC 必須鏡射 SQL 語意（歷史坑）。

## 產品規則（拍板）

- 兩檔同權益、終身一次、重裝/restore/退訂不重發也不回收（granted = granted）。
- 券抽不佔每日免費額度、不扣一般 quota、不驗當下 tier（已送出就有效）。
- SR 池全收藏後券仍可用：降級允許跨窗重複（比照既有 dedup fallback）。
- Free：圖鑑看到鎖定灰券 → paywall；教學卡鈎子文案此批一起換（批 1 刻意保留）。
- 訂閱成功輕慶祝：SnackBar 帶「去翻牌」action，不強制導頁。

---

### Task 1: Migration A — 券表＋事件表 bonus_source 欄

**Files:**
- Create: `supabase/migrations/20260808XXXXXX_practice_sr_draw_tickets.sql`（XXXXXX＝實際 UTC 時分秒）

```sql
-- 訂閱送 SR 限定翻牌（2026-08-08 拍板，docs/plans/2026-08-08-subscription-sr-draw-and-game-intro-design.md）。
--
-- 為何另開表而非 practice_draw_bonuses 加 source：主 claim RPC 對 bonuses 以
-- user_id 單列 FOR UPDATE＋懶消耗（20260802120000 P1 加固），一人一列是其語意
-- 前提；加第二列會讓 SELECT..INTO 取列不定、懶消耗 UPDATE 誤吃 SR 券。
--
-- 語意：一人一列＝終身一次；grant 冪等（INSERT ON CONFLICT DO NOTHING）；
-- 消耗顯式 claim（券強制 rarity，不能懶標記）。退訂不回收。
CREATE TABLE IF NOT EXISTS public.practice_sr_draw_tickets (
  user_id             UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tier_at_grant       TEXT        NOT NULL CHECK (tier_at_grant IN ('starter', 'essential')),
  granted_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  consumed_at         TIMESTAMPTZ,
  consumed_request_id TEXT        CHECK (consumed_request_id IS NULL OR length(consumed_request_id) BETWEEN 1 AND 64)
);

ALTER TABLE public.practice_sr_draw_tickets ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.practice_sr_draw_tickets IS
  '訂閱一次性 SR 限定翻牌券：一人一列、server 驗 tier 後 grant、顯式 claim 消耗、退訂不回收。';

-- 券抽事件標記：主 RPC free_used 計數（cost=0）必須排除券抽，否則券偷吃每日
-- 免費額度。NULL＝一般抽（含起步贈抽，語意不變）。
ALTER TABLE public.practice_profile_draw_events
  ADD COLUMN IF NOT EXISTS bonus_source TEXT
  CHECK (bonus_source IS NULL OR bonus_source IN ('subscription_sr'));
```

**Steps:**
1. 寫 migration 檔。
2. `migration_source_test.ts` 加 guard（assert 表名、PRIMARY KEY user_id、bonus_source CHECK）——先跑確認 FAIL（檔名還沒對上）再補檔案對名。
3. `cd supabase/functions/practice-chat && deno test migration_source_test.ts` → PASS。
4. Commit：`加：SR 限定翻牌券表＋抽卡事件 bonus_source 欄（migration 未上 prod）`。

### Task 2: Migration B — 主 claim RPC 計數排除券抽

**Files:**
- Create: `supabase/migrations/20260808XXXXXX_claim_draw_exclude_sr_ticket.sql`

CREATE OR REPLACE `claim_practice_profile_draw`，唯一 diff＝4 個 free_used 計數位點加 `AND bonus_source IS NULL`：

```sql
    SELECT count(*) INTO v_free_used
    FROM public.practice_profile_draw_events
    WHERE user_id = p_user_id
      AND reset_window_start_at = p_reset_window_start_at
      AND cost_messages = 0
      AND bonus_source IS NULL;
```

其餘 byte-for-byte 照抄 `20260802120000_claim_draw_bonus_atomic.sql`（含註解），檔頭註明「唯一語意變更＝計數排除 bonus_source='subscription_sr'」。

**Steps:**
1. 寫 migration；`migration_source_test.ts` 加 guard：assert 新檔含 `AND bonus_source IS NULL` 恰好 4 次＋containing `CREATE OR REPLACE FUNCTION public.claim_practice_profile_draw`。
2. index_test 的 fake `claim_practice_profile_draw`（若有計數邏輯）同步鏡射排除——先讓測試表達「券抽不佔 free_used」FAIL，再改 fake PASS。
3. deno test 全綠；commit。

### Task 3: Migration C — 新 RPC claim_practice_sr_ticket_draw

**Files:**
- Create: `supabase/migrations/20260808XXXXXX_claim_sr_ticket_draw_rpc.sql`

```sql
-- SR 限定翻牌消耗 RPC：券列 FOR UPDATE → 冪等 replay → 寫事件（cost=0,
-- bonus_source='subscription_sr'）→ 標 consumed，同交易原子。
-- 鎖序：只鎖 tickets（本 RPC 專屬表）＋事件 unique 防撞，不碰 subscriptions/
-- bonuses 鎖 → 與主 RPC（subscriptions→bonuses）無死鎖環。
-- 錯誤碼：PRACTICE_SR_TICKET_NOT_AVAILABLE（無券/已用）、
-- PRACTICE_DRAW_PROFILE_CONFLICT（同窗同 profile 撞號，Edge 換張重抽）。
CREATE OR REPLACE FUNCTION public.claim_practice_sr_ticket_draw(
  p_user_id               UUID,
  p_request_id            TEXT,
  p_profile_id            TEXT,
  p_reset_window_start_at TIMESTAMPTZ,
  p_tier                  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.practice_profile_draw_events;
  v_ticket   public.practice_sr_draw_tickets;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'claim_practice_sr_ticket_draw: p_user_id is required';
  END IF;
  IF p_request_id IS NULL OR length(p_request_id) = 0 OR length(p_request_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_sr_ticket_draw: invalid p_request_id';
  END IF;
  IF p_profile_id IS NULL OR length(p_profile_id) = 0 OR length(p_profile_id) > 64 THEN
    RAISE EXCEPTION 'claim_practice_sr_ticket_draw: invalid p_profile_id';
  END IF;
  IF p_reset_window_start_at IS NULL THEN
    RAISE EXCEPTION 'claim_practice_sr_ticket_draw: p_reset_window_start_at is required';
  END IF;

  -- 冪等 replay（鎖前）：同 requestId 已抽過 → 回放，不碰券。
  SELECT * INTO v_existing
  FROM public.practice_profile_draw_events
  WHERE user_id = p_user_id AND request_id = p_request_id;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'profile_id', v_existing.profile_id,
      'idempotent_replay', TRUE
    );
  END IF;

  -- 鎖券列；無券或已用 → NOT_AVAILABLE（fail-closed）。
  SELECT * INTO v_ticket
  FROM public.practice_sr_draw_tickets
  WHERE user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND OR v_ticket.consumed_at IS NOT NULL THEN
    RAISE EXCEPTION 'PRACTICE_SR_TICKET_NOT_AVAILABLE';
  END IF;

  -- 鎖後二次 replay：併發同 requestId 的後到者從券鎖醒來時，先到者事件可能已
  -- commit（比照主 RPC 2a）。
  SELECT * INTO v_existing
  FROM public.practice_profile_draw_events
  WHERE user_id = p_user_id AND request_id = p_request_id;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'profile_id', v_existing.profile_id,
      'idempotent_replay', TRUE
    );
  END IF;

  BEGIN
    INSERT INTO public.practice_profile_draw_events (
      user_id, request_id, profile_id, tier_at_draw,
      reset_window_start_at, cost_messages, bonus_source
    ) VALUES (
      p_user_id, p_request_id, p_profile_id, COALESCE(p_tier, 'free'),
      p_reset_window_start_at, 0, 'subscription_sr'
    );
  EXCEPTION WHEN unique_violation THEN
    SELECT * INTO v_existing
    FROM public.practice_profile_draw_events
    WHERE user_id = p_user_id AND request_id = p_request_id;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'profile_id', v_existing.profile_id,
        'idempotent_replay', TRUE
      );
    END IF;
    RAISE EXCEPTION 'PRACTICE_DRAW_PROFILE_CONFLICT';
  END;

  UPDATE public.practice_sr_draw_tickets
  SET consumed_at = now(), consumed_request_id = p_request_id
  WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'profile_id', p_profile_id,
    'idempotent_replay', FALSE
  );
END;
$$;

REVOKE ALL ON FUNCTION public.claim_practice_sr_ticket_draw(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_practice_sr_ticket_draw(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.claim_practice_sr_ticket_draw(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.claim_practice_sr_ticket_draw(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT) TO service_role;

NOTIFY pgrst, 'reload schema';
```

**Steps:** migration_source_test guard（錯誤碼、FOR UPDATE、service_role grant）→ deno test → commit。

### Task 4: Edge — validate srTicket 旗標

**Files:**
- Modify: `supabase/functions/practice-chat/validate.ts`（PracticeDrawRequest + validateDrawRequest）
- Test: `supabase/functions/practice-chat/validate_test.ts`（沿用該檔既有 draw 驗證測試組）

TDD：先加測試——`srTicket: true` 通過並保留；`srTicket: "yes"`/`1` 被忽略（不 throw 400，比照 catalogSize 舊契約寬容原則→ 非 boolean 一律當 undefined）；缺席＝undefined。再實作：

```ts
export interface PracticeDrawRequest {
  requestId: string;
  currentProfileId?: string;
  visiblePracticeThreadId?: string;
  catalogSize?: number;
  srTicket?: boolean;
}
// validateDrawRequest 內：
const srTicket = raw.srTicket === true ? true : undefined;
```

### Task 5: Edge — SR 限定選牌

**Files:**
- Modify: `supabase/functions/practice-chat/practice_persona.ts`（selectPracticeDrawProfile / hasEligibleDrawCandidate 加 `rarityFilter?: "sr"`）
- Test: `supabase/functions/practice-chat/practice_persona_test.ts`

TDD 測試先行：
1. `rarityFilter: 'sr'` 時任意 seed 選出的 profile rarity 皆為 sr。
2. 排除掉部分 SR 後仍只出未排除的 SR。
3. 全 SR 被排除 → 退避仍回 SR 層（只避 current），絕不出 R/N、絕不 throw。
4. `hasEligibleDrawCandidate` 帶 filter 的判定一致。
5. 無 filter 行為 byte-for-byte 不變（既有測試全綠即證）。

實作：切池（resolveDrawPoolSize）後先 `base.filter(g => g.rarity === 'sr')` 再走既有排除／退避；`pickWeightedByRarity` 拿到純 SR 池時自然全出 SR（空層退避已涵蓋），不需改。

### Task 6: Edge — draw_handler 券抽分支＋handler grant mode

**Files:**
- Modify: `supabase/functions/practice-chat/draw_handler.ts`
- Modify: `supabase/functions/practice-chat/handler.ts`（`mode: 'ensure_subscription_sr_ticket'`）
- Modify: `supabase/functions/practice-chat/index_test.ts`（fake：tickets 表＋新 RPC，鏡射 SQL 語意含鎖後 replay 與 NOT_AVAILABLE）
- Test: `supabase/functions/practice-chat/draw_handler_test.ts`

**draw_handler**（`request.srTicket === true` 分支，在 step 2 之後）：
- 跳過 allowance/paidExtra 判定；沿用 step 3 的去重集合＋fallback。
- 選牌帶 `rarityFilter: 'sr'`（SR 全收藏→比照既有 fallback 用 windowExcluded）。
- 呼叫 `claim_practice_sr_ticket_draw`；`PRACTICE_DRAW_PROFILE_CONFLICT` → 換張重抽（同迴圈）；`PRACTICE_SR_TICKET_NOT_AVAILABLE` → `{ status: 409, body: { error: 'sr_ticket_not_available' } }`。
- 回應沿用既有 body 形狀：cost=0；free 三欄以「不影響」值回（freeAllowance＝tier 額度、freeUsed/Remaining 不需精確——client 券抽路徑不用它們更新每日額度 UI；註解寫明）。附 `srTicket: true` 於 draw 物件。

**handler grant mode**（比照 `grant_onboarding_draw_bonus`，但 server 驗 tier）：
```ts
if (isPlainObject(rawBody) && rawBody.mode === "ensure_subscription_sr_ticket") {
  // server 驗 tier（不信 client）：free → eligible:false 不 grant。
  // premium → 冪等 grant＋回 status。既有訂閱者首次呼叫自然回溯補發。
  // 讀 subscriptions.tier → normalizeTier；
  // tier !== 'free' → upsert { user_id, tier_at_grant: tier } onConflict user_id ignoreDuplicates
  // → select granted_at, consumed_at → { eligible, granted: true, consumed }
  // tier === 'free' → { eligible: false, granted: false, consumed: false }
}
```

**TDD 順序：** draw_handler_test 先寫（mock client）：券抽成功／NOT_AVAILABLE 409／撞號重抽／冪等 replay 回原 profile／SR-only；handler grant mode 走 index_test（free 拒發、premium 發、重呼冪等、consumed 正確）。每綠一組 commit。

### Task 7: Client — API service

**Files:**
- Modify: `lib/features/practice_chat/data/services/practice_chat_api_service.dart`
- Test: `test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart`（沿用既有 harness）

1. `drawProfile` 加 `bool srTicket = false` → body 帶 `if (srTicket) 'srTicket': true`；409 `sr_ticket_not_available` → 丟新例外 `PracticeSrTicketUnavailableException`。
2. `ensureSubscriptionSrTicket()` → `({bool eligible, bool granted, bool consumed})` record；非 200 丟例外（呼叫端 best-effort）。

### Task 8: Client — 券狀態 provider＋抽卡路徑

**Files:**
- Modify: `lib/features/practice_chat/data/providers/practice_chat_providers.dart`
- Test: `test/unit/features/practice_chat/providers/`（比照既有 controller 測試 harness）

1. `srTicketStatusProvider`：AsyncNotifier；`refresh()` 呼叫 ensure API（premium 才打、free 直接標 eligible:false 不打——省一次冷啟動請求；訂閱狀態轉 premium 時由呼叫端 refresh）。快取於記憶體即可（server 為真相源，圖鑑每次進入 refresh）。
2. `drawNewPracticeGirl({bool srTicket = false})`：srTicket 路徑成功後 invalidate `srTicketStatusProvider`；402/429 分支不適用券抽（server 不會回），`PracticeSrTicketUnavailableException` → errorMessage「這張券已經用過了」＋refresh 狀態。

### Task 9: Client — 圖鑑券卡 UI 三態＋儀式

**Files:**
- Modify: `lib/features/practice_chat/presentation/screens/practice_collection_screen.dart`
- Test: `test/widget/features/practice_chat/practice_collection_sr_ticket_test.dart`（新檔，沿用 collection 測試 harness）

三態（放每日翻牌鈕旁）：
- premium＋未用：金色「SR 限定翻牌 ×1」券卡（`ValueKey('collection-sr-ticket')`，鑲金邊＋auto_awesome icon；動畫沿用 `_drawPulse` 節奏），點擊→直接走抽卡儀式（`drawNewPracticeGirl(srTicket: true)`，儀式本身就是慶祝，不加確認框——券固定 SR 沒有「值不值」的猶豫）。
- free：同卡灰階＋鎖頭（`ValueKey('collection-sr-ticket-locked')`）＋「訂閱解鎖」，點擊→`context.push('/paywall')`。
- premium＋已用（或狀態載入中/失敗）：不顯示（載入失敗 fail-quiet，券是 bonus 不是主流程）。

Widget 測試：三態渲染、金券點擊觸發 srTicket 抽、灰券導 paywall。

### Task 10: Client — Paywall 權益行＋成功輕慶祝

**Files:**
- Modify: `lib/features/subscription/presentation/screens/paywall_screen.dart`
- Test: 既有 paywall widget 測試檔補 assert

1. `_buildFeatureComparisonTable` 翻牌 row 下加一行：`_buildComparisonRow('SR 限定翻牌', '—', '送 1 次', '送 1 次')`（解 Game 鎖的白紙黑字）。
2. 購買成功：`_showSnackBar` 文案改「方案已更新，目前方案：$purchasedTier。🎴 已解鎖 SR 限定翻牌 ×1，到練習室圖鑑翻開。」；成功後 best-effort `ensureSubscriptionSrTicket()`（吞例外——圖鑑進入時會再 ensure，此處只為縮短金券出現延遲）。

### Task 11: Client — Game 教學卡 Free 鈎子文案升級（批 1 保留項）

**Files:**
- Modify: `lib/features/practice_chat/presentation/widgets/practice_game_intro_sheet.dart`（`_IntroUpgradeHook`）
- Test: `test/widget/features/practice_chat/practice_game_intro_test.dart` 補文案 assert

標題改「訂閱直接解鎖 Game」；內文改「訂閱就送一次 SR 限定翻牌，馬上開一位 SR 對象進 Game；之後每天還能翻牌認識新對象、和同一位連續多局。」（機制此批已上線，承諾成立）。

### Task 12: 驗證與交付

1. `deno test`（practice-chat 全部）＋`flutter analyze`＋`flutter test --concurrency=1` 全綠。
2. WSL PG16 真併發 smoke（比照 08-02）：同 user 兩併發券抽同 requestId／不同 requestId——恰一次消耗；券抽與每日抽併發——free_used 不被券抽污染。
3. **Codex 雙審**（quota/訂閱高風險區鐵則）：migration 三檔＋draw_handler/handler diff 為主。審修完才進 4。
4. Targeted migration 上 production（shared-agent-rules 程序）＋Management API 驗表/RPC 存在。
5. Push main（自動 Edge deploy＋Build & Distribute）；監控 exact-SHA。
6. 收尾報告：Eric 真機驗（sandbox Premium 可驗回溯補發＋金券＋保底 SR 儀式；Free 態需另一帳號）。
