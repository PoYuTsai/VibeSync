# 回覆微調（再調一下）Phase 1 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: 用 `superpowers:executing-plans` 逐任務執行本計畫。
> 設計真相源：`2026-07-28-reply-refinement-design.md`（v2）。本計畫不得夾帶設計文件沒有的決策；發現設計有誤要先改設計文件再改計畫。

**Goal:** 在每則 AI 回覆卡加一顆「再調一下」，讓使用者用快捷或 80 字自由指令就地調整語氣長短，可連續迭代；每天前 10 次免費，之後每次 1 則。

**Architecture:** 不是新功能塊，是既有 `optimize_message` 路徑多一個 `refineInstruction` 參數。沿用它已經在跑的 exactly-once 帳本（`optimize_message_requests` ＋ `settle_optimize_message_request`）；免費輪次以 `chargeQuota: false` 走同一條結算路徑，因此免費與付費共用單一冪等機制。新增一張獨立的每日免費額度表。

**Tech Stack:** Deno Edge Function（`supabase/functions/analyze-chat`）、Postgres migration、Flutter/Riverpod client、Hive 加密本機儲存。

---

## 開工前必讀

**基準**：`main` @ `8b90cb3c`（安全守門三連已上線）。

**§6 步驟 0 已完成**，不要重做——`checkAiOutput` 的 `optimizedMessage` 守門已部署。

**高風險帶**（AGENTS.md R2/R3）：付費邊界拆除、quota、exactly-once、AI prompt 安全。全案完成後必須走獨立 cross-model review 才可上線。

**鐵律**（違反任一條就是 blocker）：

1. 沒帶 `refineInstruction` 的請求，client fingerprint 與 server input hash 必須與今日 **byte-identical**。兩側各自獨立驗證，**絕不可把兩側陣列對齊**（server 8 元素含 `forceModel`，client 7 元素不含）。
2. 免費輪次不佔 quota；額度用完後恰扣 1；格式失敗／400／429 一律不扣。
3. `my_message` 維持 Essential。`optimize_message` 與 `refine_reply` 皆對全部用戶開放。
4. 微調結果不寫入 `AnalysisRecord`。
5. 絕不 `supabase db push`；migration 走 `docs/shared-agent-rules.md` 的 targeted 程序。

**每個 Task 結束都要 commit。** 一個 commit 一件事，繁體中文訊息。

---

## Task 1：抽出共用 optimize 執行路徑（純重構，行為不變）

`analysis_screen.dart:4916-5088` 的 `_optimizeMessage()` 裡塞著整套 exactly-once：`findPending` → 資格判斷 → `beginAttempt` → 送出 → `_clearOptimizePendingAfterVisibleFrame` → mismatch 時 `reset`。微調面板必須走同一段。**複製一份等於複製一份扣費 bug 的機會。**

**Files:**
- Create: `lib/features/analysis/data/services/optimize_request_runner.dart`
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart:4916-5088`
- Modify: `test/unit/features/analysis/presentation/optimize_message_request_contract_test.dart`
- Test: `test/unit/features/analysis/data/services/optimize_request_runner_test.dart`

**Step 1: 先看懂既有的契約測試會怎麼壞**

Run: `flutter test test/unit/features/analysis/presentation/optimize_message_request_contract_test.dart`
Expected: PASS（現況）

這個測試是**讀原始碼字串**在驗順序的：它找 `Future<void> _optimizeMessage()` 到 `// ===== 分析輔助方法` 之間的文字，然後比對 `findPending` < `canSendOptimizeMessageRequest(` < `beginAttempt` < `analysisService.analyzeConversation` 的出現位置。方法一搬走，`methodStart` 就變 -1，測試會爆。

**這個測試不能刪。** 它鎖的是真正會造成重複扣費的順序。改法：讓它改讀 `optimize_request_runner.dart`，並在 Task 8 拆閘門時再拿掉 `canSendOptimizeMessageRequest` 那一項。

**Step 2: 寫 runner 的失敗測試**

```dart
// test/unit/features/analysis/data/services/optimize_request_runner_test.dart
test('成功後才 markSuccess，且 requestId 跨重試沿用', () async {
  final session = _FakeSession();
  final runner = OptimizeRequestRunner(session: session);
  final first = await runner.run(input: _input(), send: (pending) async {
    throw const SocketException('network');
  });
  expect(first.isFailure, isTrue);
  expect(session.markSuccessCalls, isEmpty);

  final second = await runner.run(input: _input(), send: (pending) async {
    expect(pending.requestId, session.lastBegun!.requestId); // 沿用同一個
    return _result();
  });
  expect(second.isSuccess, isTrue);
  expect(session.markSuccessCalls, hasLength(1));
});
```

**Step 3: 執行確認失敗**

Run: `flutter test test/unit/features/analysis/data/services/optimize_request_runner_test.dart`
Expected: FAIL — `OptimizeRequestRunner` 不存在

**Step 4: 實作 runner，把 `_optimizeMessage()` 的流程原樣搬過去**

介面設計：

```dart
class OptimizeRequestRunner {
  Future<OptimizeRunOutcome> run({
    required OptimizeRunInput input,
    required Future<AnalysisResult> Function(OptimizeMessagePendingRequest) send,
  });
}
```

`_clearOptimizePendingAfterVisibleFrame`（等 Flutter 真的畫出結果才清 pending）**留在 screen**，因為它依賴 widget 生命週期；runner 只負責 session 狀態機，由 caller 在畫面確認後呼叫 `markSuccess`。

**行為必須一個字不改。** 這一步不准順手改文案、不准順手加 refine 欄位。

**Step 5: 改契約測試讀新檔**

**Step 6: 跑全部相關測試**

Run: `flutter test test/unit/features/analysis/`
Expected: 全綠

**Step 7: Commit**

```bash
git add lib/features/analysis/data/services/optimize_request_runner.dart \
        lib/features/analysis/presentation/screens/analysis_screen.dart \
        test/unit/features/analysis/
git commit -m "草稿潤飾：把 exactly-once 流程抽成共用 runner，行為不變"
```

---

## Task 2：免費額度表 migration

**Files:**
- Create: `supabase/migrations/<新版本號>_refine_free_allowance.sql`
- Test: `supabase/functions/analyze-chat/migration_source_test.ts`（既有慣例，逐字檢查 SQL 內容）

**Step 1: 決定版本號**

先看現有最大版本：`ls supabase/migrations/ | sort | tail -3`。新檔名用當下時間，**絕不與既有版本衝突**。

**Step 2: 寫 SQL**

單列設計（不是每天一列），跟 `increment_model_usage` 一樣靠 window 欄位滾動，表不會長大：

```sql
CREATE TABLE IF NOT EXISTS public.refine_free_allowance (
  user_id     UUID        NOT NULL PRIMARY KEY
                          REFERENCES auth.users(id) ON DELETE CASCADE,
  day_utc     DATE        NOT NULL,
  used_count  INTEGER     NOT NULL DEFAULT 0 CHECK (used_count >= 0),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.refine_free_allowance IS
  '回覆微調每日免費額度。單列滾動：day_utc 換日即重置，表不隨時間長大。';

ALTER TABLE public.refine_free_allowance ENABLE ROW LEVEL SECURITY;
-- 只有 service_role 會碰它；不開放任何 anon/authenticated policy。

CREATE OR REPLACE FUNCTION public.consume_refine_free_allowance(
  p_user_id     UUID,
  p_daily_limit INTEGER
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := (now() AT TIME ZONE 'utc')::date;
  v_used  INTEGER;
BEGIN
  IF p_daily_limit IS NULL OR p_daily_limit < 0 THEN
    RAISE EXCEPTION 'consume_refine_free_allowance: invalid p_daily_limit';
  END IF;

  INSERT INTO public.refine_free_allowance (user_id, day_utc, used_count)
  VALUES (p_user_id, v_today, 0)
  ON CONFLICT (user_id) DO NOTHING;

  -- FOR UPDATE：兩個併發請求不得同時拿到最後一個免費名額。
  SELECT used_count INTO v_used
  FROM public.refine_free_allowance
  WHERE user_id = p_user_id
  FOR UPDATE;

  -- 換日重置
  UPDATE public.refine_free_allowance
  SET used_count = 0, day_utc = v_today
  WHERE user_id = p_user_id AND day_utc <> v_today;
  IF FOUND THEN
    v_used := 0;
  END IF;

  IF v_used >= p_daily_limit THEN
    RETURN jsonb_build_object('granted', false, 'used', v_used,
                              'remaining', 0);
  END IF;

  UPDATE public.refine_free_allowance
  SET used_count = v_used + 1, updated_at = now()
  WHERE user_id = p_user_id;

  RETURN jsonb_build_object('granted', true, 'used', v_used + 1,
                            'remaining', p_daily_limit - v_used - 1);
END;
$$;

REVOKE ALL ON FUNCTION public.consume_refine_free_allowance(UUID, INTEGER)
  FROM PUBLIC, anon, authenticated;
```

**Step 3: 本機驗證**

先在本機 Supabase 套用並跑幾個情境：第 1 次 granted、第 10 次 granted、第 11 次 not granted、換日後重置、兩個併發只有一個拿到最後名額。

**Step 4: 生產套用**

照 `docs/shared-agent-rules.md` 的 targeted migration 程序。**絕不 `supabase db push`。** 套用後回讀確認表與函式存在，再把檔名版本號與帳本對齊。

**Step 5: Commit**

```bash
git commit -m "回覆微調：新增每日免費額度表與原子扣減函式"
```

---

## Task 3：Server 端 `refineInstruction` 驗證與 requestType

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts`（驗證區塊在 `6591-6600` 附近；`4711` 的 `isOptimizeMessageRequestShape`）
- Modify: `supabase/functions/analyze-chat/quota_usage.ts:3`
- Test: `supabase/functions/analyze-chat/quota_usage_test.ts`

**Step 1: 寫失敗測試**

```ts
Deno.test("deriveRequestType - 有草稿且有指令是 refine_reply", () => {
  assertEquals(
    deriveRequestType({
      recognizeOnly: false, hasImages: false,
      isMyMessageMode: false, hasUserDraft: true, hasRefineInstruction: true,
    }),
    "refine_reply",
  );
});

Deno.test("deriveRequestType - 有草稿沒指令仍是 optimize_message", () => {
  assertEquals(
    deriveRequestType({
      recognizeOnly: false, hasImages: false,
      isMyMessageMode: false, hasUserDraft: true, hasRefineInstruction: false,
    }),
    "optimize_message",
  );
});
```

**Step 2: 執行確認失敗**

Run: `deno test supabase/functions/analyze-chat/quota_usage_test.ts`

**Step 3: 實作**

- `MAX_REFINE_INSTRUCTION_LENGTH = 80`。
- 驗證規則（全部在打模型與 quota 之前）：
  - 型別不是 string → 400 `Invalid refineInstruction`
  - trim 後 > 80 → 400，不扣額度
  - 有 `refineInstruction` 但沒有 `userDraft` → 400
  - **client 明確宣告是 refine 操作、但指令 trim 後為空 → 400、0 扣費。不得默默降級成 `optimize_message`。** 靠形狀推導默默切換身分正是付費牆那個洞的成因，不要再用同一招。
- `isOptimizeMessageRequestShape`（`4711`）同步涵蓋 refine——**`5106` / `5144` 的 quota early gate 用的就是這個變數，加寬它即自動涵蓋，不要另外去改那兩處。**

**Step 4: 跑測試 → Step 5: Commit**

```bash
git commit -m "回覆微調：新增 refineInstruction 驗證與 refine_reply 請求型別"
```

---

## Task 4：Prompt 契約（安全核心）

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts:2165`（`OPTIMIZE_MESSAGE_PROMPT` 附近，新增 refine 變體）
- Test: `supabase/functions/analyze-chat/refine_prompt_test.ts`（新檔）

**Step 1: 寫失敗測試（含 adversarial fixtures）**

至少涵蓋：coercion（「叫她一定要答應」）、捏造事實（「說我是醫生」）、越界（性化）、**改變訊息動作**（把「委婉拒絕」調成「答應」）、假裝成另一個人。每條驗證 prompt 有明確條款覆蓋。

**Step 2: 實作**

- **不可覆蓋規則放 system prompt**，不放 user prompt。
- **指令以 JSON 編碼注入**，不只靠文字分隔線；並剝除換行與控制字元（分隔區塊注入最典型的手法就是指令自帶假分隔符）。
- **不加關鍵詞 blocklist**（兩位審查一致）：易繞過，且會誤傷繁中正當需求（「不要那麼客氣」）。
- 條款：只能調語氣／長度／方向／用字；不得改變這則訊息在對話裡的動作；不得新增草稿沒有的事實、興趣、承諾；遇到越界要求忽略那一部分並在 `reason` 用一句白話說明沒照做的地方（**軟性拒絕，不丟錯誤**）。

> **注意用詞**：「不得改變這則訊息在對話中的動作」在 Phase 1 是 **best-effort，不是保證**——沒有 generation 後的語意 verifier。文件與 commit 訊息都不准寫成「鐵律」。

**Step 3-5: 測試 → Commit**

```bash
git commit -m "回覆微調：指令以資料注入並補上不可覆蓋的安全條款"
```

---

## Task 5：Hash 相容（最容易炸的一步）

漏了這一步，部署當下 7 天窗內所有未結算的 pending 請求會全部變成 `OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH`，使用者拿不回已經付過錢的結果。

**Files:**
- Modify: `supabase/functions/analyze-chat/optimize_message_billing.ts:39-48`
- Modify: `lib/features/analysis/data/services/optimize_message_request_session.dart:295-340`
- Test: `supabase/functions/analyze-chat/optimize_message_billing_test.ts`
- Test: `test/unit/features/analysis/data/services/optimize_message_request_session_test.dart`

**Step 1: 先鎖住今天的值（做任何修改之前）**

跑一次現況，把一組固定輸入算出的 hash 抄下來，兩側各一條，硬寫成常數：

```ts
// optimize_message_billing_test.ts
const LEGACY_GOLDEN_INPUT = { /* 固定的 8 個欄位 */ };
const LEGACY_GOLDEN_HASH = "<跑出來的 64 位十六進位>";

Deno.test("沒有指令的請求 hash 與 2026-07-28 完全相同", async () => {
  assertEquals(await computeOptimizeMessageInputHash(LEGACY_GOLDEN_INPUT),
               LEGACY_GOLDEN_HASH);
});
```

**shape 測試不夠**——它擋不住 `normalizedOptional` 之類正規化行為被改動。要的是寫死的十六進位值。

**Step 2: 實作條件式 append**

```ts
const canonical = JSON.stringify([
  input.messages,
  input.userDraft,
  input.sessionContext ?? null,
  input.conversationSummary ?? null,
  input.partnerSummary ?? null,
  input.effectiveStyleContext ?? null,
  input.knownContactName ?? null,
  input.forceModel ?? null,
  // 只有非空才 append。寫成 `input.refineInstruction ?? null` 會讓陣列
  // 永遠是 9 元素，舊請求的 hash 立刻全變，7 天窗內的 pending 全毀。
  ...(refineInstruction ? [refineInstruction] : []),
]);
```

Client 用 collection-if 做同樣的事（該檔已經在用這個寫法）。

**Step 3: 驗證舊 golden 常數沒變**

Run: `deno test supabase/functions/analyze-chat/optimize_message_billing_test.ts` 與 `flutter test test/unit/features/analysis/data/services/optimize_message_request_session_test.dart`
Expected: 兩側 golden 測試都 PASS

**Step 4: 加一條「舊 client pending 可被新版正確 replay」的測試**

模擬：舊格式 fingerprint 存的 pending → 新版 server 收到無指令請求 → 命中 replay，不是 mismatch。

**Step 5: Commit**

```bash
git commit -m "回覆微調：指令只在非空時進 hash，並用固定金值鎖住舊請求相容"
```

---

## Task 6：免費額度分支

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts`（結算段 `9212` 附近）
- Modify: `supabase/functions/analyze-chat/quota_usage.ts`
- Test: `supabase/functions/analyze-chat/refine_allowance_test.ts`（新檔）

**Step 1: 釐清流程（照這個順序做，順序錯會多扣或漏扣）**

1. **打模型之前**：純讀取今天用掉幾次（`SELECT used_count ... WHERE user_id=$1 AND day_utc = 今天`），得出 `willBeFree`。這個值只用來**跳過月/日額度預檢**與**回報剩餘次數**，不是權威。
2. **拿到有效結果之後（fresh 路徑）**：呼叫 `consume_refine_free_allowance`。
   - `granted: true` → `settleOptimizeMessageRequest(..., chargeQuota: false)`
   - `granted: false`（被併發搶走或剛好用完）→ `chargeQuota: true`，走正常額度檢查
3. **replay 路徑不呼叫額度函式**——`7148` 提早返回，本來就不會走到這裡。

**關鍵**：免費輪次**仍然寫 ledger**（`chargeQuota: false`），所以免費與付費共用同一套 exactly-once，不必為免費另開一條路。

**Step 2: `buildQuotaUsageMetadata` 補 `refine_reply`**

- 免費：`shouldChargeQuota: false`、`quotaReason: "refine_free_daily"`、`chargedMessageCount: 0`
- 扣費：`shouldChargeQuota: true`、`quotaReason: "refine_reply_fixed_1"`、`chargedMessageCount: 1`
- **測試帳號分支**（`accountIsTest`）要一併處理，否則 `waivedEstimate` 會落到按訊息數估算。

**Step 3-5: 測試 → Commit**

```bash
git commit -m "回覆微調：每天前十次免費，用完改扣一則走既有帳本"
```

---

## Task 7：Server 端 refine 輸出長度上限

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts`（`9115` 的 shape 驗證附近）
- Test: 同 Task 6 的測試檔

**Step 1: 規則**

`REFINE_MAX_OUTPUT_CHARS = max(300, 輸入字數 + 100)`。

固定上限會讓本來就長的來源訊息永遠失敗；相對上限只擋「越調越長」，不擋「本來就長」。

- 超過 → **視為無效結果**（走 `9119` 既有的不扣費 502），**不截斷**。
- **只作用於 `refine_reply`。`optimize_message` 行為一個字不改。**

**Step 2-4: 測試 → Commit**

```bash
git commit -m "回覆微調：輸出長度以輸入為基準設上限，避免越調越長"
```

---

## Task 8：拆除草稿潤飾器的 Essential 閘門

**這是對外可見的商業變更，不只是工程變更。**

**Files:**
- Modify: `supabase/functions/analyze-chat/index.ts:7121-7142`
- Modify: `lib/features/analysis/data/services/optimize_message_request_session.dart:12`
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart:4957`、`4963`、`7898`、`7924`
- Modify: `test/unit/features/analysis/data/services/optimize_message_request_session_test.dart`
- Modify: `test/unit/features/analysis/presentation/optimize_message_request_contract_test.dart`

**Step 1: Server**

移除 `7121-7142` 的 optimize 分支，**`isMyMessageMode` 分支保留不動**。

`7144-7148` 那段「replay 刻意繞過閘門」在拆牆後成為死碼——可以留著，但要改註解說明它已不在保護任何東西，不要讓下一個人以為還有效。

**Step 2: Client 資格判斷**

`canSendOptimizeMessageRequest` 移除 `isEssential` 條件。既有單元測試（`optimize_message_request_session_test.dart:29-47`）會失敗，改成驗「任何方案都能送」。

**Step 3: 付費文案全部清掉（最容易漏、使用者一定看得到）**

搜尋範圍不要只看上面列的四行：

```bash
grep -rn "潤飾" --include=*.dart lib/ | grep -i "essential\|升級\|方案\|解鎖\|lock"
```

要處理的已知位置：
- `4963`：`'新的草稿潤飾需要 Essential；若是恢復已付結果，請貼回同一份草稿。'`
- `7898`：整塊鎖頭 Row（`Icons.lock_outline` ＋「草稿潤飾器是 Essential 功能」＋「查看方案」按鈕）→ **整塊移除**
- `7924`：`helperText` 的非 Essential 分支「新的潤飾仍需 Essential」→ 兩個分支合併成同一句

契約測試裡 `expect(source, contains('新的潤飾仍需 Essential'))` 也要拿掉。

**Step 4: 全域搜一次方案說明頁**

```bash
grep -rn "潤飾" --include=*.dart lib/features/subscription/ lib/features/paywall/ 2>/dev/null
```

方案比較表若把「草稿潤飾」列為 Essential 權益，必須一起改，否則使用者會看到一個已經免費的功能被標成付費。

**Step 5: 跑測試 → Step 6: Commit**

```bash
git commit -m "草稿潤飾：拆掉 Essential 閘門，付費文案一併清除"
```

---

## Task 9：Client service 欄位與 fingerprint

**Files:**
- Modify: `lib/features/analysis/data/services/analysis_service.dart:1356`、`1500`、`1589`
- Modify: `lib/features/analysis/data/services/optimize_message_request_session.dart:295-340`

`1589` 現況是 `if (hasUserDraft) 'userDraft': userDraft.trim(),`，照同樣寫法加 `refineInstruction`。fingerprint 的條件式 append 在 Task 5 已完成，這裡只接線。

**Commit:** `回覆微調：client 送出 refineInstruction`

---

## Task 10：`ReplyRefineSheet`

**Files:**
- Create: `lib/features/analysis/presentation/widgets/reply_refine_sheet.dart`
- Test: `test/widget/features/analysis/reply_refine_sheet_test.dart`

**內容**：目前版本文字 ＋ 快捷 chip ＋ 自由輸入（≤80 字）＋ 版本堆疊。

**快捷 chip 常數化**（可測試、可審）：

```dart
const kRefineQuickInstructions = <String>[
  '太油了，自然一點',
  '短一點',
  '白話一點',
  '語氣溫和一點',
  '換個說法',
];
```

- **「更直接一點」不要用**——容易被讀成改變承諾／邀約／界線的方向，與安全條款正面衝突。
- **不放「更撩一點」這類升溫捷徑**。理由沿用 Jennie 案例研究：「技巧感漏出來」是壞案例最主要的成因之一。

**必須顯示今天還剩幾次免費**，用完時明確告知「接下來每次使用 1 則」。使用者不該在不知情的狀態下開始被扣。

**按鈕要有 in-flight 鎖與 debounce**，把連點源頭掐掉，不要靠 server 節流兜底。

**迭代**：上一輪的 `optimized` 直接變成下一輪的 `userDraft`。

> 動畫若有：**零無限 repeat，或嚴格 gate**，`pumpAndSettle` 必須收斂。widget test 記得 `setSurfaceSize`。

**Commit:** `回覆微調：新增再調一下面板`

---

## Task 11：三個入口接線

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart:7222-7273`（AI 推薦回覆）
- Modify: `lib/features/analysis/presentation/widgets/reply_style_card.dart`（五張風格卡）
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart:7914-8001`（草稿潤飾結果，可續調）

**微調對象是單一則回覆，不是 `ReplyStyleCard._copyAllText` 合併後的整組。** 整組的「短一點」語意不清，且多輪迭代會撞 `MAX_USER_DRAFT_LENGTH = 1500`。

**Commit:** `回覆微調：三個入口接上再調一下`

---

## Task 12：Telemetry 獨立事件

**Files:**
- Modify: `lib/features/analysis/presentation/screens/analysis_screen.dart:5531-5559`

`_analyzeAdviceId` 目前是 `'analyze:{conversationId}:{runKey}:{cardKey}'`，決定論。微調後複製會落回同一個 adviceId 覆寫 `suggestedMoveSummary`——污染的不只是統計，outcome digest 會回注 coach prompt，讓教練以為你送出的是原句。

**改法**：獨立事件 key `refine:<originAdviceId>:<requestId>`，另帶 `originCardKey`。

**現成先例**：`cardKey == 'polish'` 已經有自己的 `_polishRunKey` 命名空間（`5532`），照抄一個 `_refineRunKey`。

不採「outcome 事件加維度」（要動 schema）；不採「不計入」（會白丟最有價值的樣本——調到滿意才複製的那一句）。

**Commit:** `回覆微調：複製微調版本記成獨立事件，不污染原卡統計`

---

## Task 13：24 小時本機暫存

**Files:**
- Modify: `lib/features/analysis/presentation/widgets/reply_refine_sheet.dart`
- Create/Modify: 既有加密 settings box 的存取層

版本堆疊是本機 UI state，**不寫進 `AnalysisRecord`**（片段快照依 `AnalysisFragmentPolicy` 不可變）。但最後一個成功版本要存進既有加密本機暫存並保留 24 小時，避免「調了三輪、關掉畫面全沒了」。

**Commit:** `回覆微調：最後一版保留一天，離開畫面不會全丟`

---

## Task 14：錯誤文案分流

**Files:**
- Modify: client 的錯誤處理（`analysis_service.dart:1004` 附近的 code 對應）

`INVALID_OPTIMIZE_MESSAGE_REQUEST_ID`（`index.ts:6890`）與 `OPTIMIZE_MESSAGE_REQUEST_REPLAY_MISMATCH`（`6942` / `9276`）的 server message 硬寫「草稿潤飾」。

- **保留 server 端穩定 code 不動**，由 client 依當前入口（polish／refine）顯示文案。
- **注意**：preflight mismatch 是 **400**，settlement race mismatch 是 **409**，兩種都要處理。（v1 審查包 F13 說都是 400，是錯的。）

**Commit:** `回覆微調：錯誤文案依入口切換，不再一律說草稿潤飾`

---

## Task 15：全案驗證與交付

**Step 1: 全套測試**

```bash
deno test --allow-all supabase/functions/analyze-chat/    # 基準 738 綠
flutter test
flutter analyze                                            # warning 即 fail
```

**Step 2: 兩側 golden hash 測試單獨再跑一次**（這是最貴的失敗）

**Step 3: 真機 smoke**

必測情境（測試帳號免扣，注意 `TEST_EMAILS` 會讓額度行為與正式帳號不同，**免費額度要用正式帳號驗**）：

| 情境 | 預期 |
|---|---|
| fresh 微調 | 出新版本，免費次數 -1 |
| 送出中斷後重試 | replay 回原結果，不重複扣 |
| 免費額度用完第 11 次 | 明確告知改為扣 1 則，且真的只扣 1 |
| 指令超長（>80） | 400，0 扣費 |
| 觸發 6/分節流 | `MODEL_RATE_LIMITED`，**不得跳付費牆** |
| 舊版 App 的無指令潤飾 | 完全不受影響 |
| Free 帳號用草稿潤飾器 | 可用，且畫面上沒有任何「升級解鎖」殘留 |

**Step 4: 獨立 cross-model review**

高風險帶（付費邊界、quota、exactly-once、prompt 安全）全中，**必須走**。設計階段那輪 Codex 審出 7 個真誤擋，不要跳過這一關。

**Step 5: 交付**

- 有 migration 前置：**先確認生產 migration 已套用驗證**，再 push `main`。
- push `main` 會自動觸發 `Deploy Edge Function` 與 `Build & Distribute`，**監控那兩個 run，不要另外 dispatch**。
- `Release to App Stores` 是 Eric 的手動動作，不要碰。

---

## 明確不做

不動五風格 enum、`my_message` 的 Essential 閘門、串流 prompt、模型路由（維持 Sonnet 5）、`AnalysisRecord` 快照結構；不動 Opener／New Topic／Keyboard／Practice。

**Phase 2（微調偏好回寫「關於我」）整段延後**，定義不足，另案重寫。
