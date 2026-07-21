# 教練統一案 Phase B 實作計畫（後端加欄位、行為不變）

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> 真相源設計文件：`docs/plans/2026-07-21-coach-unification-design.md`（D-1~D-6 已拍板）。
> 分支：`claude/coach-question-followup-integration-5twkr6`

**Goal:** coach-chat 看得懂三個新選填欄位（`requestId`/`scope`/`lifecyclePhase`）＋ prompt 支援三情境 framing，沒人送新欄位時行為與今日 byte-for-byte 相同。

**Architecture:** 純加性擴充 `RequestSchema`（`.strict()` 只擋未知 key，選填欄位缺席不影響 parse 結果）；prompt 情境段落走既有 `section()` 條件式注入（缺席回 `null` 被 `.filter(Boolean)` 濾掉 → join 結果逐字不變）；`generation.ts` 整包傳 `request` 給 `buildCoachChatPrompt`，僅 telemetry 加旗標。`validate.ts`/`index.ts` 的 request 路徑走 `RequestSchema.parse`，無需改動。

**Tech Stack:** Deno + zod v3.22.4（Edge Function）、Deno.test + std asserts。

**鐵律（來自設計文件 §3/§8）：**
- 部署順序：Edge 先容忍新欄位、App 後送（Phase E 才送）。本 Phase 可先部署、對現況零影響。
- Phase B 觸 Edge-schema → **Codex APPROVED 才可稱 dogfood safe**。
- 絕不 `git add pubspec.lock`（目前 working tree 有它的髒改動，commit 時逐檔 add）。
- 一 commit 一 concern、繁中 commit message、完成即 push。

**已驗證讀碼事實（2026-07-21 subagent，寫碼前不必重查）：**
- `coach-chat/schemas.ts:1` import zod；`:68-97` RequestSchema，`.strict()` 在 `:85` 之後接 `.superRefine`；選填慣例 `.nullable().optional()`；`:156-158` `z.infer` 匯出型別（新欄位自動帶入 `CoachChatRequest`）。
- `coach-chat/validate.ts:11-22` `validateRequest` 是 index.ts 的唯一入口（先擋 `images` 再 `RequestSchema.parse`）→ 新欄位自動生效，**本檔不改**。
- `coach-chat/index.ts:289` 呼叫 `validateRequest`；`conversationId`/`partnerId` 在 index.ts 完全未被解引用；rate-limit scope 是寫死字串 `"coach_chat"`（`:363`）→ **index.ts 不改**。
- `coach-chat/prompts.ts:7` `buildCoachChatPrompt(input: CoachChatRequest)`；`:8-23` `context` 陣列 → `.filter(Boolean).join("\n\n")`；`:124-127` `section(title, value)` helper（空值回 `null`）。**情境段落必須走 context 陣列，絕不改 `SYSTEM_PROMPT_BASE`（`:51-122` 無條件常數，改了就破 byte-identical）。**
- `coach-chat/generation.ts:118` `const basePrompt = buildCoachChatPrompt(request);`（整包傳）；`:107-114` `coach_chat_invoked` telemetry 用布林旗標慣例（`hasSummary` 等）。
- 測試風格：`Deno.test("...", () => {...})` ＋共用 `baseRequest` fixture spread（`validate_test.ts:13-24`）；prompts 測試用 `assertStringIncludes`（`prompts_test.ts:16-28`）；asserts import 自 `https://deno.land/std@0.168.0/testing/asserts.ts`。
- requestId 格式對齊 keyboard-reply exactly-once 範本（ADR #22）：UUID（`keyboard-reply/contract.ts:14-18` `UUID_PATTERN`）→ 本 Phase 用 `z.string().uuid()`。
- coach-follow-up 是 legacy shim，**任何檔案都不動**（它的 `phase`/`answers` 與本案新欄位不同名不同域）。

**測試指令（全計畫通用）：**
```bash
deno test --allow-read --allow-env supabase/functions/coach-chat/validate_test.ts
deno test --allow-read --allow-env supabase/functions/coach-chat/prompts_test.ts
# 全套（收尾用）：
deno test --allow-read --allow-env supabase/functions/coach-chat
```

---

## Task 0: 拍 byte-identity 基準快照

改碼前先留存現況 prompt 輸出，收尾時 diff 證明逐字不變。

**Step 1: 寫 dump 腳本（scratchpad，不進 repo）**

寫到 scratchpad 目錄 `dump_prompt.ts`：

```ts
import { buildCoachChatPrompt } from "../../supabase/functions/coach-chat/prompts.ts";
import { validateRequest } from "../../supabase/functions/coach-chat/validate.ts";

const baseRequest = {
  conversationId: "c1",
  userQuestion: "她這句話是真的有興趣嗎？",
  recentMessages: [{ sender: "partner", text: "你感覺是個很有故事的人" }],
  dataQualityFlagged: false,
};
console.log(buildCoachChatPrompt(validateRequest(baseRequest)));
```

（import 路徑依腳本實際存放位置調整為指向 repo 的絕對路徑更穩。）

**Step 2: 產出 before 快照**

```bash
deno run --allow-read <scratchpad>/dump_prompt.ts > <scratchpad>/prompt_before.txt
```

Expected: 檔案有內容（現況 system prompt 全文）。

---

## Task 1: `lifecyclePhase` 選填欄位（schema）

**Files:**
- Modify: `supabase/functions/coach-chat/schemas.ts`（enum 加在檔案上方 `CoachChatModeEnum` 附近；欄位加在 `dataQualityFlagged` 之後、`.strict()` 之前）
- Test: `supabase/functions/coach-chat/validate_test.ts`

**Step 1: 寫失敗測試**

在 `validate_test.ts` 加（確認檔頂已 import `assertThrows`，沒有就補）：

```ts
Deno.test("validateRequest accepts optional lifecyclePhase", () => {
  const parsed = validateRequest({ ...baseRequest, lifecyclePhase: "chatStalled" });
  assertEquals(parsed.lifecyclePhase, "chatStalled");
});

Deno.test("validateRequest rejects unknown lifecyclePhase value", () => {
  assertThrows(() => validateRequest({ ...baseRequest, lifecyclePhase: "preDateReminder" }));
});
```

（`preDateReminder` 是 coach-follow-up 舊 enum 值，刻意選它證明兩域不互通。）

**Step 2: 跑測試確認失敗**

Run: `deno test --allow-read --allow-env supabase/functions/coach-chat/validate_test.ts`
Expected: FAIL — `.strict()` 拒絕未知 key `lifecyclePhase`。

**Step 3: 實作 schema**

`schemas.ts` 上方（`CoachChatModeEnum` 附近）加：

```ts
export const LifecyclePhaseEnum = z.enum([
  "chatStalled",
  "prepareInvite",
  "postDate",
]);
export type LifecyclePhase = z.infer<typeof LifecyclePhaseEnum>;
```

`RequestSchema` 的 `dataQualityFlagged` 之後加：

```ts
  lifecyclePhase: LifecyclePhaseEnum.nullable().optional(),
```

**Step 4: 跑測試確認通過**

Run: 同 Step 2。Expected: PASS（含既有全部測試）。

**Step 5: Commit**

```bash
git add supabase/functions/coach-chat/schemas.ts supabase/functions/coach-chat/validate_test.ts
git commit -m "教練統一 Phase B：coach-chat 加 lifecyclePhase 選填欄位（三情境 enum）" && git push
```

---

## Task 2: `requestId` 選填欄位（UUID，對齊 ADR #22 範本）

**Files:**
- Modify: `supabase/functions/coach-chat/schemas.ts`
- Test: `supabase/functions/coach-chat/validate_test.ts`

**Step 1: 寫失敗測試**

```ts
Deno.test("validateRequest accepts optional uuid requestId", () => {
  const parsed = validateRequest({
    ...baseRequest,
    requestId: "a3bb189e-8bf9-4888-9912-ace4e6543002",
  });
  assertEquals(parsed.requestId, "a3bb189e-8bf9-4888-9912-ace4e6543002");
});

Deno.test("validateRequest rejects non-uuid requestId", () => {
  assertThrows(() => validateRequest({ ...baseRequest, requestId: "not-a-uuid" }));
});
```

**Step 2: 跑測試確認失敗**（同 Task 1 指令，FAIL：unknown key）

**Step 3: 實作** — `RequestSchema` 加：

```ts
  requestId: z.string().uuid().nullable().optional(),
```

（Phase B 只驗格式、不使用；Phase C 帳本才消費它。格式先鎖 UUID＝keyboard 範本同款，避免 Phase C 收緊時破壞已部署 client。）

**Step 4: 跑測試確認通過**

**Step 5: Commit**

```bash
git add supabase/functions/coach-chat/schemas.ts supabase/functions/coach-chat/validate_test.ts
git commit -m "教練統一 Phase B：coach-chat 加 requestId 選填欄位（UUID 格式對齊 ADR #22）" && git push
```

---

## Task 3: `scope` 判別式欄位＋與頂層 id 一致性守門

**Files:**
- Modify: `supabase/functions/coach-chat/schemas.ts`
- Test: `supabase/functions/coach-chat/validate_test.ts`

**Step 1: 寫失敗測試**

```ts
Deno.test("validateRequest accepts conversation scope matching top-level id", () => {
  const parsed = validateRequest({
    ...baseRequest,
    scope: { type: "conversation", conversationId: "c1" },
  });
  assertEquals(parsed.scope?.type, "conversation");
});

Deno.test("validateRequest rejects conversation scope mismatching top-level id", () => {
  assertThrows(() =>
    validateRequest({
      ...baseRequest,
      scope: { type: "conversation", conversationId: "other" },
    })
  );
});

Deno.test("validateRequest accepts partner scope matching top-level partnerId", () => {
  const parsed = validateRequest({
    ...baseRequest,
    partnerId: "p1",
    scope: { type: "partner", partnerId: "p1" },
  });
  assertEquals(parsed.scope?.type, "partner");
});

Deno.test("validateRequest rejects partner scope mismatching top-level partnerId", () => {
  assertThrows(() =>
    validateRequest({
      ...baseRequest,
      partnerId: "p1",
      scope: { type: "partner", partnerId: "p2" },
    })
  );
});

Deno.test("validateRequest rejects scope with unknown keys", () => {
  assertThrows(() =>
    validateRequest({
      ...baseRequest,
      scope: { type: "conversation", conversationId: "c1", extra: 1 },
    })
  );
});
```

**Step 2: 跑測試確認失敗**

**Step 3: 實作** — `schemas.ts` 加（`LifecyclePhaseEnum` 附近）：

```ts
export const CoachScopeSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("conversation"),
    conversationId: z.string().min(1).max(100),
  }).strict(),
  z.object({
    type: z.literal("partner"),
    partnerId: z.string().min(1).max(100),
  }).strict(),
]);
```

`RequestSchema` 加欄位：

```ts
  scope: CoachScopeSchema.nullable().optional(),
```

既有 `.superRefine((payload, ctx) => { ... })` 內追加（保留原 dataQualityFlagged 檢查）：

```ts
  if (
    payload.scope?.type === "conversation" &&
    payload.scope.conversationId !== payload.conversationId
  ) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["scope", "conversationId"],
      message: "scope_conversation_id_mismatch",
    });
  }
  if (
    payload.scope?.type === "partner" &&
    payload.partnerId != null &&
    payload.scope.partnerId !== payload.partnerId
  ) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["scope", "partnerId"],
      message: "scope_partner_id_mismatch",
    });
  }
```

（一致性守門理由：Phase C `input_hash` 會蓋 `scopeKey`，此處先擋掉「scope 與頂層 id 打架」的 client bug，fail fast 於 400 而非 Phase C 的 REPLAY_MISMATCH。錯誤訊息照 repo 慣例英文 snake key。）

**Step 4: 跑測試確認通過**

**Step 5: Commit**

```bash
git add supabase/functions/coach-chat/schemas.ts supabase/functions/coach-chat/validate_test.ts
git commit -m "教練統一 Phase B：coach-chat 加 scope 判別式欄位＋頂層 id 一致性守門" && git push
```

---

## Task 4: prompt 三情境 framing 段落（條件式注入）

**Files:**
- Modify: `supabase/functions/coach-chat/prompts.ts`
- Test: `supabase/functions/coach-chat/prompts_test.ts`

**Step 1: 寫失敗測試**

在 `prompts_test.ts` 加（fixture 照該檔既有建構方式；若該檔用 `validateRequest` 就沿用，否則直接建最小 `CoachChatRequest` 物件）：

```ts
Deno.test("buildCoachChatPrompt omits lifecycle framing when absent", () => {
  const prompt = buildCoachChatPrompt(baseInput);
  assertEquals(prompt.includes("教練情境"), false);
});

Deno.test("buildCoachChatPrompt injects chatStalled framing", () => {
  const prompt = buildCoachChatPrompt({ ...baseInput, lifecyclePhase: "chatStalled" });
  assertStringIncludes(prompt, "教練情境");
  assertStringIncludes(prompt, "聊天卡住");
});

Deno.test("buildCoachChatPrompt injects prepareInvite framing", () => {
  const prompt = buildCoachChatPrompt({ ...baseInput, lifecyclePhase: "prepareInvite" });
  assertStringIncludes(prompt, "邀約");
});

Deno.test("buildCoachChatPrompt injects postDate framing", () => {
  const prompt = buildCoachChatPrompt({ ...baseInput, lifecyclePhase: "postDate" });
  assertStringIncludes(prompt, "約會結束");
});
```

**Step 2: 跑測試確認失敗**

Run: `deno test --allow-read --allow-env supabase/functions/coach-chat/prompts_test.ts`
Expected: 三個 inject 測試 FAIL（prompt 不含關鍵詞）；omit 測試此時本來就 PASS（正確——它是回歸鎖）。

**Step 3: 實作**

`prompts.ts` 加 import（自 `./schemas.ts`）：`LifecyclePhase` 型別。加常數與 helper（放 `section` helper 附近）：

```ts
const LIFECYCLE_FRAMING: Record<LifecyclePhase, string> = {
  chatStalled:
    "使用者目前的卡點：聊天卡住了（對話變冷、已讀不回、或訊息頻率明顯下降）。" +
    "優先診斷卡住的原因（話題耗盡、壓力過大、時機不對、對方興趣下降），" +
    "再給可立即使用的重啟策略；避免建議連續追問或帶情緒的質問。",
  prepareInvite:
    "使用者目前的卡點：想約她出來（從線上聊天推進到實際邀約）。" +
    "先評估目前互動熱度是否足以邀約；足夠就給具體的邀約措辭、時機與被婉拒時的備案；" +
    "不足就先給升溫步驟，明說現在還不是提出邀約的最佳時機。",
  postDate:
    "使用者目前的卡點：約會結束之後的下一步。" +
    "先釐清約會實際狀況與對方反應（若上下文不足，優先用釐清問題收集），" +
    "再給後續訊息策略（何時傳、傳什麼）與關係推進或修復建議。",
};

function formatLifecycleFraming(
  phase: LifecyclePhase | null | undefined,
): string | null {
  if (!phase) return null;
  return LIFECYCLE_FRAMING[phase] ?? null;
}
```

`buildCoachChatPrompt` 的 `context` 陣列（`:8-23`）**開頭**加一項：

```ts
    section("教練情境", formatLifecycleFraming(input.lifecyclePhase)),
```

**絕不改 `SYSTEM_PROMPT_BASE`。**

**Step 4: 跑測試確認通過**（prompts_test 全綠）

**Step 5: Commit**

```bash
git add supabase/functions/coach-chat/prompts.ts supabase/functions/coach-chat/prompts_test.ts
git commit -m "教練統一 Phase B：prompt 加三情境 framing 段落（缺席零注入）" && git push
```

---

## Task 5: telemetry 旗標（coach_chat_invoked）

**Files:**
- Modify: `supabase/functions/coach-chat/generation.ts:107-114`
- Test: `supabase/functions/coach-chat/generation_test.ts`（若該 log payload 已有測試就補斷言；沒有就只目檢＋跑既有測試不紅）

**Step 1: 實作** — `coach_chat_invoked` log payload 照既有旗標慣例追加：

```ts
      lifecyclePhase: request.lifecyclePhase ?? null,
      hasRequestId: request.requestId != null,
      hasScope: request.scope != null,
```

（`lifecyclePhase` 是封閉 enum 非用戶內容，記原值供 dogfood 分流觀察；其餘只記布林，符合鐵律 8「telemetry 不存來源文字」。）

**Step 2: 跑 generation 測試**

Run: `deno test --allow-read --allow-env supabase/functions/coach-chat/generation_test.ts`
Expected: PASS（零改動即綠；若有 log 形狀斷言測試才需同步更新）。

**Step 3: Commit**

```bash
git add supabase/functions/coach-chat/generation.ts
git commit -m "教練統一 Phase B：coach_chat_invoked telemetry 加新欄位旗標" && git push
```

---

## Task 6: 收尾驗證——全套測試＋byte-identity diff＋fmt

**Step 1: 全套 coach-chat 測試**

Run: `deno test --allow-read --allow-env supabase/functions/coach-chat`
Expected: 全綠、**既有測試零修改**（`git diff main -- '*_test.ts'` 只看得到新增測試）。

**Step 2: byte-identity diff（對 Task 0 快照）**

```bash
deno run --allow-read <scratchpad>/dump_prompt.ts > <scratchpad>/prompt_after.txt
diff <scratchpad>/prompt_before.txt <scratchpad>/prompt_after.txt && echo BYTE_IDENTICAL
```

Expected: 無 diff、印出 `BYTE_IDENTICAL`。有 diff＝破鐵律，回頭修（多半是動到 SYSTEM_PROMPT_BASE 或 section 無條件注入）。

**Step 3: fmt 檢查**

Run: `deno fmt --check supabase/functions/coach-chat`
Expected: 無輸出（或列出需修檔案→ `deno fmt` 修掉後重跑測試再補 commit）。

---

## Task 7: Codex 審查包＋APPROVED gate

**Step 1: 出包**（直呼 `codex:rescue`，照拍板不出 packet 給 Eric 路由）

- base ref：本分支對 main 的 merge-base（`git merge-base HEAD main`）。
- 檔案清單：`supabase/functions/coach-chat/{schemas.ts,prompts.ts,generation.ts,validate_test.ts,prompts_test.ts}`。
- 高風險焦點（設計文件 §7）：`.strict()` 相容性（舊 body 不會 400）、response byte-identity（欄位缺席時 prompt/行為逐字不變）、scope 一致性守門不誤傷、UUID 格式與 ADR #22 範本一致。
- 佐證：Deno 測試輸出＋Task 6 的 `BYTE_IDENTICAL` diff 證據。

**Step 2: 等 verdict**。非 APPROVED → 照 findings 修、重跑 Task 6、重審。**沒拿到 APPROVED 絕不稱 dogfood safe、絕不 rotate。**

---

## Task 8: 部署＋live 舊格式 smoke（APPROVED 後）

**Step 1: 確認部署路徑**

Run: `gh run list --limit 5` — 先看 push 是否已觸發 Edge 自動部署（repo 慣例：push 即 auto-deploy；坑：main 的 CI push 會蓋掉 branch 臨時部署，Phase B 零行為差異所以被蓋也無害）。未觸發則用 MCP `deploy_edge_function` 部署 `coach-chat`。

**Step 2: live smoke——舊格式仍 200**

用測試帳號（`vibesync.test@gmail.com`）JWT 對 prod `coach-chat` 送**不含任何新欄位**的舊格式 body，Expected: 200 且 response 形狀與現況相同。再送一發含 `lifecyclePhase: "chatStalled"` 的 body，Expected: 200（證明 Edge 已容忍新欄位）。

**Step 3: 回報**

對 Eric 回報 Phase B 完成：測試證據＋BYTE_IDENTICAL＋Codex APPROVED＋live smoke 結果。下一棒＝Phase C（exactly-once 帳本，最敏感、單獨隔離）。

---

## 明確不做（YAGNI，Phase B 邊界）

- 不動 `coach-follow-up/`（legacy shim，Phase F 才退場）。
- 不動 `index.ts`／`validate.ts`（request 路徑自動生效）、不動 rate-limit scope 字串（D-2 的統一 `coach` scope 屬後續 Phase）。
- 不加 `structuredAnswers`（D-4 拍板廢除固定表單）。
- 不建帳本表、不消費 `requestId`（Phase C）。
- 不改 client／不送新欄位（Phase E）。
- 不把 coach-chat 加進 CI deno test 清單（另議；本 Phase 以本地全套＋Codex 佐證）。
