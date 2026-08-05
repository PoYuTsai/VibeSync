# 練習室「正常一定要有輸出」實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 讓 hint 與 debrief 在新手／一般／Game 三種模式下，正常使用一定產出結果，不再因為守門把合格候選打回而轉 503。

**Architecture:** 把字面 grounding 從「絕對否決權」降級成「前兩發的偏好」。`runSingleShot` 兩發（Sonnet→Haiku）都沒過 gate 時，不再直接 503，而是進入 **salvage pass**：拿 `attemptFailures[].raw` 裡分數最好的候選，用「只保留不可退讓守門」的設定重新解析並端出。不可退讓＝安全/L4、內部詞洩漏、罐頭簽名、捏造對方主動邀約、fact ledger；可退讓＝字面 n-gram grounding 與主觀評分。

**Tech Stack:** Deno + TypeScript（Supabase Edge Function），測試 `deno test`。無 migration、無 client 改動。

---

## 背景與證據（開工前必讀）

**事故**：2026-08-05 使用者按「結束練習」後看到「拆解卡生成失敗，可以再按一次」，再按也不會好。

**ai_logs 實證**（`request_type=practice_debrief_standard`，13:44:47 與 13:45:19 各一筆）：
- `status=failed`、`error_code=schema_invalid`
- `error_message=debrief_quality_invalid_suggested_line_not_grounded`
- Sonnet 5 主發 + Haiku 4.5 補發，兩發全滅 → `SingleShotExhaustedError` → 503

**根因**：逐字稿只有「你好」「嗨～你好」。`evidenceFragments()` 對 compact 後長度 < 4 的句子只取整句當唯一錨點（`practice_visible_quality.ts:202`），錨點集合只剩 `{你好, 嗨你好}`。`assertPracticeTextGroundedInTurns` 要求貼句必須字面包含某個錨點，於是唯一能通過的建議句是複讀「你好」——那正是最糟的教練建議，兩顆模型都不會產出。

**被打回的候選其實都合格**（原文存在 `ai_logs.response_body.rejectedCandidates`），例如 Sonnet 5 那張：
- summary：對話僅止於打招呼，尚未展開任何話題，無法判斷互動品質。
- suggestedLine：嗨～剛看到你資料上有健身教練，平常帶課會很累嗎？

**同型 FP 不只 debrief**：她只回 emoji 時，一句自然的 hint（回應她的表情）也會被打回，因為它沒有複讀「我說」的原話。grounding 的證據窗包含使用者自己的 turn（非 latestOnly 時 `evidenceTurns = opts.turns`，兩種 role 都算），所以這道 gate 實際上在逼 hint 引用使用者自己說過的話，而不是回應她。

**Eric 拍板（2026-08-05）**：
1. grounding 只該負責擋「完全沒碰這場對話的萬用模板」，不再兼差擋捏造（fact ledger 的事）與階段越界（invite maturity 的事）。
2. 硬性不變量：**hint × debrief × (新手/一般/Game) 全部組合，正常一定要有輸出。**

**先前被否決的作法**：在 gate 內加 `waiveOnContentlessTranscript`（逐字稿沒實質內容就跳過比對）。Codex 審 REJECTED（P1），實測證實會讓下列句子在生產設定下被端到使用者面前：

| 攻擊句 | 走完整 parseDebriefCard |
|---|---|
| 最近過得怎樣？有什麼想聊的嗎？ | PASS（被端出去）|
| 感覺妳最近壓力很大，要不要聊聊？ | PASS（被端出去）|
| 妳應該剛失戀吧？想聊聊嗎？ | PASS（被端出去）|

原因：生產以 `relaxSubjectiveQualityRubrics: true` 呼叫，`rejectGenericPasteablePracticeText` 被跳過，而該函式實測對這三句本來也抓不到。**該補丁必須先撤除**（Task 1）。

---

## 守門分類（salvage 的依據）

實作前務必自行覆核；下表為 2026-08-05 讀碼結果。

| 守門 | 位置 | 何時跑 | 分類 |
|---|---|---|---|
| 內部標籤洩漏 | `debrief_card.ts:259` `rejectInternalLabelLeak` | 欄位解析時，無條件 | **不可退讓** |
| 溫度機制詞洩漏 | `debrief_card.ts:262` | 欄位解析時，無條件 | **不可退讓** |
| L4 露骨越界 | `debrief_card.ts:263` `rejectL4UnsafeVisibleText` | 欄位解析時，無條件 | **不可退讓** |
| 罐頭簽名 | `debrief_card.ts:1509` `rejectKnownCannedPracticeText` | `assertGeneratedDebriefQuality` 內，無條件 | **不可退讓** |
| 捏造對方主動邀約 | `debrief_card.ts:1513` `assertNoInventedPartnerInitiative` | 同上，無條件 | **不可退讓** |
| fact ledger 捏造 | `debrief_card.ts:1527/1539/1547` `assertHintFactClaimsSupported` | 同上 | **不可退讓** |
| hintAssessment 契約 | `debrief_card.ts:1785` | 有套用 hint 時 | **不可退讓** |
| 主觀評分（欄位角色/實質） | `debrief_card.ts:1514` 起，`!relaxSubjective` | 生產已關閉 | 可退讓 |
| **字面 grounding** | `debrief_card.ts:1592/1605` | 無條件 | **可退讓（本案降級對象）** |

Hint 側對應的 grounding 在 `hint.ts:2358`（warmUp/steady/coaching 三欄全走）。

---

## Task 1：撤除被否決的 contentless 補丁

**Files:**
- Modify: `supabase/functions/practice-chat/practice_visible_quality.ts`
- Modify: `supabase/functions/practice-chat/debrief_card.ts`
- Modify: `supabase/functions/practice-chat/practice_visible_quality_test.ts`
- Modify: `supabase/functions/practice-chat/debrief_card_test.ts`

**Step 1:** 確認工作區狀態

```bash
cd /mnt/c/Users/eric1/OneDrive/Desktop/VibeSync
git status --short
```

若 4 個檔案仍是未 commit 的修改（Task 1 的前提），直接：

```bash
git checkout -- supabase/functions/practice-chat/practice_visible_quality.ts \
  supabase/functions/practice-chat/debrief_card.ts \
  supabase/functions/practice-chat/practice_visible_quality_test.ts \
  supabase/functions/practice-chat/debrief_card_test.ts
```

若已經 commit，改用 `git revert` 該 commit。

**Step 2:** 確認回到乾淨基線

```bash
cd supabase/functions/practice-chat && deno test --allow-read --allow-env 2>&1 | tail -3
```
Expected: `ok | 1092 passed | 0 failed`（撤掉本案新增的 7 顆後的數字；若不同，先查明原因再繼續）

---

## Task 2：debrief salvage pass

**Files:**
- Modify: `supabase/functions/practice-chat/debrief_card.ts`（新增 `skipLexicalGrounding` 選項）
- Test: `supabase/functions/practice-chat/debrief_card_test.ts`

**Step 1: 寫失敗測試**

加到 `debrief_card_test.ts` 檔尾：

```ts
// ===== 2026-08-05：salvage pass 只放掉字面 grounding，不可退讓守門照跑 =====
const greetingOnlyTurns = [
  { role: "user" as const, text: "你好" },
  { role: "ai" as const, text: "嗨～你好" },
];

const salvageOptions = {
  requireCompleteCard: true,
  enforceGeneratedQuality: true,
  relaxSubjectiveQualityRubrics: true,
  skipLexicalGrounding: true,
  turns: greetingOnlyTurns,
} as const;

function greetingOnlyCard(suggestedLine: string): string {
  return JSON.stringify({
    summary: "對話僅止於打招呼，尚未展開任何話題，無法判斷互動品質。",
    strengths: ["有主動開口打招呼，禮貌開場"],
    watchouts: ["未接續任何話題，對話停在寒暄無法留下記憶點"],
    suggestedLine,
    vibe: "中性",
    dateChance: "low",
    dateChanceReason: "她只回了「嗨～你好」，未釋出任何延伸或時間線索。",
    nextInviteMove: "先從她的背景聊起，建立輕鬆話題後再觀察熱度。",
  });
}

Deno.test("salvage：ai_logs 當天被打回的真實候選解得出來", () => {
  const card = parseDebriefCard(
    greetingOnlyCard("嗨～剛看到你資料上有健身教練，平常帶課會很累嗎？"),
    salvageOptions,
  );
  assertEquals(
    card.suggestedLine,
    "嗨～剛看到你資料上有健身教練，平常帶課會很累嗎？",
  );
});

Deno.test("salvage 不放掉 L4：露骨候選照樣打回", () => {
  // 用 visible_text_guard_test.ts 裡既有的 L4 樣本，勿自行發明。
  // 實作時到該檔取一句確定會觸發 rejectL4UnsafeVisibleText 的字串。
  assertThrows(
    () => parseDebriefCard(greetingOnlyCard("<<L4 樣本>>"), salvageOptions),
    Error,
  );
});

Deno.test("salvage 不放掉罐頭簽名", () => {
  // KNOWN_CANNED_SIGNATURES 取一句，見 practice_visible_quality.ts
  assertThrows(
    () =>
      parseDebriefCard(
        greetingOnlyCard("妳剛說的那個點我有記住，我先分享我的版本，再聽妳的。"),
        salvageOptions,
      ),
    Error,
    "debrief_canned_visible_text",
  );
});

Deno.test("沒開 skipLexicalGrounding：前兩發行為完全不變", () => {
  assertThrows(
    () =>
      parseDebriefCard(
        greetingOnlyCard("嗨～剛看到你資料上有健身教練，平常帶課會很累嗎？"),
        { ...salvageOptions, skipLexicalGrounding: false },
      ),
    Error,
    "debrief_quality_invalid_suggested_line_not_grounded",
  );
});
```

**Step 2: 跑測試確認失敗**

```bash
deno test supabase/functions/practice-chat/debrief_card_test.ts 2>&1 | tail -20
```
Expected: 型別錯誤 `'skipLexicalGrounding' does not exist in type ...`（＝功能未實作）

**Step 3: 實作**

`debrief_card.ts` — 在 `assertGeneratedDebriefQuality` 的 opts 型別加：

```ts
    /**
     * 只有 salvage pass 可以開。跳過字面 n-gram grounding。
     *
     * grounding 的職責是擋「完全沒碰這場對話的萬用模板」，它是偏好不是否決權：
     * 前兩發沒過就換模型重試，兩發都沒過時寧可端出最佳候選也不要讓使用者拿到
     * 503（2026-08-05 Eric 拍板：hint/debrief × 新手/一般/Game 正常一定要有
     * 輸出）。安全/洩漏/罐頭/捏造等不可退讓守門在 salvage 一律照跑。
     */
    skipLexicalGrounding?: boolean;
```

把兩處 grounding 呼叫包起來：

```ts
  if (opts.skipLexicalGrounding !== true) {
    assertPracticeTextGroundedInTurns({
      visibleText: card.suggestedLine,
      turns: opts.turns,
      errorCode: "debrief_quality_invalid_suggested_line_not_grounded",
    });
  }
```

`gameBreakdown.nextFirstLine` 那處同理。同時把 `skipLexicalGrounding` 加進 `parseDebriefCard` 的 opts 型別並往下傳。

**Step 4: 跑測試確認通過**

```bash
deno test supabase/functions/practice-chat/debrief_card_test.ts 2>&1 | tail -5
```

**Step 5: commit**

```bash
git add supabase/functions/practice-chat/debrief_card.ts supabase/functions/practice-chat/debrief_card_test.ts
git commit -m "加：debrief 解析支援 skipLexicalGrounding，供 salvage pass 使用"
```

---

## Task 3：debrief handler 接上 salvage

**Files:**
- Modify: `supabase/functions/practice-chat/handler.ts:3408` 附近（`SingleShotExhaustedError` catch）
- Test: `supabase/functions/practice-chat/index_test.ts`

**Step 1: 寫失敗測試**

在 `index_test.ts` 加一顆整合測試：mock `callClaude` 讓兩發都回「合格但不接地」的卡（用 Task 2 的 `greetingOnlyCard`），逐字稿只有寒暄，斷言 HTTP 回應是 **200 且含拆解卡**，不是 503。參考同檔既有的 debrief 整合測試寫法。

**Step 2: 跑測試確認失敗（現在會拿到 503）**

**Step 3: 實作**

在 `catch (e)` 內、`return jsonResponse(... 503)` 之前插入 salvage：

```ts
        // salvage：兩發都沒過 gate 時，端出最佳候選而不是讓使用者拿到 503。
        // 只放掉字面 grounding；安全/洩漏/罐頭/捏造守門照跑，salvage 再失敗才 503。
        const salvaged = salvageDebriefCandidate({
          failures: e instanceof SingleShotExhaustedError
            ? e.attemptFailures
            : [],
          parseOptions: generatedDebriefParseOptions,
        });
        if (salvaged) {
          debriefCard = salvaged.card;
          debriefModel = salvaged.model;
          debriefSalvageUsed = true;
          // 不 return，往下走正常成功路徑
        } else {
          return jsonResponse(
            { error: "practice_debrief_generation_retryable", retryable: true },
            503,
          );
        }
```

新增純函式（放在 `debrief_card.ts`，可單獨測）：

```ts
/** 從被 gate 打回的候選裡搶救一張可端出的卡；全部搶救失敗回 null。 */
export function salvageDebriefCandidate(opts: {
  failures: readonly { model: string; raw?: string }[];
  parseOptions: Record<string, unknown>;
}): { card: DebriefCard; model: string } | null {
  for (const failure of opts.failures) {
    if (typeof failure.raw !== "string" || failure.raw.length === 0) continue;
    try {
      const card = parseDebriefCard(failure.raw, {
        ...opts.parseOptions,
        skipLexicalGrounding: true,
      } as never);
      return { card, model: failure.model };
    } catch {
      continue; // 這張搶救不了，換下一張
    }
  }
  return null;
}
```

**注意**：候選順序＝attemptFailures 順序（Sonnet 先、Haiku 後），即優先採用主模型的候選。

**Step 4-5:** 跑測試、commit。

---

## Task 4：hint salvage（同法）

**Files:**
- Modify: `supabase/functions/practice-chat/hint.ts`（`skipLexicalGrounding` 選項 + `salvageHintCandidate`）
- Modify: `supabase/functions/practice-chat/handler.ts:2704` 附近
- Test: `supabase/functions/practice-chat/hint_test.ts`、`index_test.ts`

與 Task 2/3 對稱。額外注意：

- hint 的 grounding 在 `hint.ts:2358`，warmUp/steady/coaching 三欄都走，salvage 時三欄一起跳過。
- **既有測試 `hint_test.ts:4954`（「fails closed on short, Latin, or emoji-only latest replies instead of serving generic copy」）必須保持綠**：那是「前兩發」的契約，salvage 是它之後的獨立階段，不得因為 salvage 而放寬 `parseHintResult` 的預設行為。
- prefetch 路徑（`requestIsPrefetch`）也要走 salvage，否則預產仍會失敗。

---

## Task 5：telemetry — salvage 必須看得見

**Files:**
- Modify: `supabase/functions/practice-chat/handler.ts`（`scheduleGenerationTelemetry` 呼叫）

salvage 端出的結果必須在 `ai_logs` 可辨識，否則「品質下滑」會變成看不見的債。

- 新增欄位 `salvageUsed: boolean` 與 `salvageReason: string[]`（＝原本的 `failureCodes`）進 telemetry payload。
- `status` 仍記 `success`，但 `fallback_used` 或新欄位要能區分「一次過」與「搶救來的」。

**驗收查詢**（部署後 24h 內跑）：

```sql
select request_type,
       count(*) filter (where response_body ? 'salvageUsed') as salvaged,
       count(*) as total
from ai_logs
where created_at > now() - interval '1 day'
  and request_type like 'practice_%'
group by 1;
```

salvage 率若長期 > 20%，代表 gate 誤殺仍嚴重，要回頭修 gate 本身而不是靠搶救。

---

## Task 6：對抗測試（Codex P3 要求）

**Files:**
- Modify: `supabase/functions/practice-chat/debrief_card_test.ts`

補上「salvage 之下仍必須被擋」的負向測試，至少涵蓋：
- 罐頭簽名（Task 2 已有）
- L4 露骨（Task 2 已有）
- 內部標籤／溫度機制詞洩漏
- 捏造對方主動邀約（`assertNoInventedPartnerInitiative`）
- fact ledger 未支持的具體事實宣稱（職業/地點/行程）

---

## 已知缺口（**不在本案範圍**，另案處理）

1. **捏造對方心理狀態沒有守門**：「感覺妳最近壓力很大」「妳應該剛失戀吧？」不在 fact ledger 建模的 domain（職業/地點/行程/偏好/生活習慣），任何 gate 都抓不到。這是**既有缺口**，不是 salvage 造成——只要句子碰巧含一個接地 n-gram，今天就過得了。Eric 判讀：這類句子該擋的理由是「階段不對」（破冰期越界）而非捏造，應由 invite maturity／階段守門處理。
2. **`evidenceFragments` 的 <4 字門檻**（`practice_visible_quality.ts:202`）對中文/Latin 分類不一致（`OK`/`Hi` 與 `Okay`/`haha` 待遇不同）。salvage 之後不再是致命問題，但仍是誤殺來源。

---

## 驗證與交付

**每個 Task 後**：`deno test --allow-read --allow-env supabase/functions/practice-chat/` 必須全綠。

**全部完成後**：
1. `deno fmt` 4 個檔案
2. 全套 deno test（目前基線 1092 顆）
3. **跨模型獨立審**（本案改的是 AI 守門行為＝高風險；執行者不審自己的活）。審查重點：salvage 是否讓不可退讓守門被繞過、`skipLexicalGrounding` 有沒有可能被前兩發誤開。
4. Edge pre-push 稽核：比對上次成功 `Deploy Edge Function` 以來 `supabase/functions` 的變更，確認不夾帶未審的 function
5. commit（繁體中文訊息，一 commit 一件事）→ push main（會自動部署 Edge）
6. 監看 `Deploy Edge Function` 與 `Build & Distribute`
7. 部署後撈 ai_logs 確認 salvage 生效且 503 消失

**CI 注意**：`.github/workflows/` **沒有**跑 practice-chat 的 deno test，本機測試是唯一的門，不要指望 CI 攔截。

**無 migration、無 client 改動。**
